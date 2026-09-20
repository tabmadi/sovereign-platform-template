// Package temporalmw is the platform-default Temporal client and worker wiring, with tracing, data converters and
// identity pre-configured (ADR-0302).
package temporalmw

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"go.temporal.io/sdk/client"
	temporaloteltracer "go.temporal.io/sdk/contrib/opentelemetry"
	"go.temporal.io/sdk/interceptor"
	tlog "go.temporal.io/sdk/log"
	"go.temporal.io/sdk/worker"
	"go.temporal.io/sdk/workflow"

	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
)

// Address resolves the Temporal frontend host from $TEMPORAL_HOST_PORT.
func Address() string {
	v := os.Getenv("TEMPORAL_HOST_PORT")
	if v != "" {
		return v
	}
	return "temporal-frontend.platform.svc.cluster.local:7233"
}

// Namespace resolves $TEMPORAL_NAMESPACE, defaulting to "default".
func Namespace() string {
	v := os.Getenv("TEMPORAL_NAMESPACE")
	if v != "" {
		return v
	}
	return "default"
}

func NewClient(serviceName string) (client.Client, error) {
	tracingInterceptor, err := temporaloteltracer.NewTracingInterceptor(temporaloteltracer.TracerOptions{})
	if err != nil {
		return nil, fmt.Errorf("temporalmw: new tracing interceptor: %w", err)
	}
	opts := client.Options{
		HostPort:     Address(),
		Namespace:    Namespace(),
		Identity:     serviceName,
		Interceptors: []interceptor.ClientInterceptor{tracingInterceptor},
		// The default Temporal logger writes to the stdlib log package, so a worker's lines never reach Loki.
		// Callers run obs.Init before NewClient, so slog.Default() is the OTLP fan-out by the time we dial.
		Logger: tlog.NewStructuredLogger(slog.Default()),
	}
	// Bounded startup retry: on a cold cluster the frontend may not be reachable yet, and the caller panics on error.
	// Runtime blips are the SDK's reconnection and the /readyz gate, not this.
	var c client.Client
	err = retry(
		func() error {
			var derr error
			c, derr = client.Dial(opts)
			if derr != nil {
				return fmt.Errorf("temporalmw: dial: %w", derr)
			}
			return nil
		},
	)
	if err != nil {
		return nil, err
	}
	// Auto-register the /readyz check for this dependency (ADR-0500).
	observability.RegisterReadinessCheck(
		"temporal",
		func(ctx context.Context) error {
			_, herr := c.CheckHealth(ctx, &client.CheckHealthRequest{})
			if herr != nil {
				return fmt.Errorf("temporalmw: health: %w", herr)
			}
			return nil
		},
	)
	return c, nil
}

// retry calls fn until it succeeds or a ~60s budget elapses, backing off 500ms→5s
// between attempts. Returns fn's last error on give-up.
func retry(fn func() error) error {
	const budget = 60 * time.Second
	deadline := time.Now().Add(budget)
	delay := 500 * time.Millisecond
	for {
		err := fn()
		if err == nil {
			return nil
		}
		if time.Now().After(deadline) {
			return err
		}
		time.Sleep(delay)
		if delay < 5*time.Second {
			delay *= 2
		}
	}
}

// The SDK default is 0s, so every Activity still executing when a pod is rolled is abandoned until its
// StartToCloseTimeout expires. The chart derives terminationGracePeriodSeconds from this, so kubelet always
// waits strictly longer than the worker does.
func stopTimeout() time.Duration {
	v := os.Getenv("TEMPORAL_WORKER_STOP_TIMEOUT")
	if v == "" {
		return 25 * time.Second
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		slog.Warn("bad TEMPORAL_WORKER_STOP_TIMEOUT, using default", "value", v, "error", err)
		return 25 * time.Second
	}
	return d
}

// Versioning is on whenever both $TEMPORAL_DEPLOYMENT_NAME and $TEMPORAL_WORKER_BUILD_ID are set (ADR-0302).
// DefaultVersioningBehavior is Pinned, so a deploy cannot break a Workflow already in flight. A workflow that
// must follow the newest code returns AutoUpgrade, and owes a versioning plan and replay tests.
func deploymentOptions() worker.DeploymentOptions {
	name, buildID := os.Getenv("TEMPORAL_DEPLOYMENT_NAME"), os.Getenv("TEMPORAL_WORKER_BUILD_ID")
	if name == "" || buildID == "" {
		return worker.DeploymentOptions{}
	}
	return worker.DeploymentOptions{
		UseVersioning: true,
		Version: worker.WorkerDeploymentVersion{
			DeploymentName: name,
			BuildID:        buildID,
		},
		DefaultVersioningBehavior: workflow.VersioningBehaviorPinned,
	}
}

// NewWorker: EnableSessionWorker is deliberately not set: the SDK forbids combining it with Worker Deployment
// Versioning, so a service that needs sessions opts out of versioning explicitly rather than inheriting both.
func NewWorker(c client.Client, taskQueue string) worker.Worker {
	return worker.New(
		c,
		taskQueue,
		worker.Options{
			MaxConcurrentActivityExecutionSize: 50,
			WorkerStopTimeout:                  stopTimeout(),
			DeploymentOptions:                  deploymentOptions(),
		},
	)
}
