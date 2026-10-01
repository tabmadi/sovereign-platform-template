// Package temporalmw is the platform-default Temporal client and worker wiring. It sets up tracing, data converters,
// and identity, per ADR-0302.
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

// Namespace resolves $TEMPORAL_NAMESPACE. The default is `default`.
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
		// Callers run obs.Init before NewClient, so slog.Default() is the OTLP fan-out when the client dials.
		Logger: tlog.NewStructuredLogger(slog.Default()),
	}
	// A bounded startup retry. On a cold cluster, the frontend can be unreachable, and the caller panics on error.
	// The SDK's reconnection and the /readyz gate handle short faults at runtime, not this retry.
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
	// Register the /readyz check for this dependency, per ADR-0500.
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

// retry calls fn until it succeeds or a budget of about 60s ends. The wait between
// attempts grows from 500ms to 5s. When it stops, it returns fn's last error.
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

// The SDK default is 0s. Then every Activity that still runs during a pod roll is abandoned until its
// StartToCloseTimeout expires. The chart derives terminationGracePeriodSeconds from this value, so kubelet
// always waits longer than the worker.
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

// Versioning is on when $TEMPORAL_DEPLOYMENT_NAME and $TEMPORAL_WORKER_BUILD_ID are both set, per ADR-0302.
// DefaultVersioningBehavior is Pinned, so a deploy cannot break a running Workflow. A workflow that must follow
// the newest code returns AutoUpgrade and needs a versioning plan and replay tests.
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

// NewWorker leaves EnableSessionWorker unset on purpose. The SDK forbids it together with Worker Deployment
// Versioning. A service that needs sessions turns off versioning explicitly and does not inherit both.
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
