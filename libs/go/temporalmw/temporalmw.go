// Package temporalmw is the platform-default Temporal client/worker wiring
// (ADR-0006). Every server and worker calls NewClient / NewWorker; tracing,
// data converters, and identity all come pre-configured.
package temporalmw

import (
	"context"
	"fmt"
	"os"
	"time"

	"go.temporal.io/sdk/client"
	temporaloteltracer "go.temporal.io/sdk/contrib/opentelemetry"
	"go.temporal.io/sdk/interceptor"
	"go.temporal.io/sdk/worker"

	"github.com/tabmadi/microservices-monorepo-template/libs/go/observability"
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

// NewClient dials Temporal with the platform interceptors attached.
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
	}
	// Bounded startup retry: on a cold cluster the frontend may not be reachable
	// yet. Retry instead of returning on the first miss (the caller panics on
	// error → CrashLoopBackOff with a growing delay). Runtime blips are handled by
	// the SDK's own reconnection plus the /readyz gate, not here.
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
	// Auto-register the /readyz check for this dependency (ADR-0011).
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

// NewWorker constructs a Temporal worker with the platform-default options.
func NewWorker(c client.Client, taskQueue string) worker.Worker {
	return worker.New(
		c,
		taskQueue,
		worker.Options{
			EnableSessionWorker:                true,
			MaxConcurrentActivityExecutionSize: 50,
		},
	)
}
