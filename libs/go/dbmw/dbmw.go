// Package dbmw wires pgx with OTel tracing + per-query metrics (ADR-0500).
package dbmw

import (
	"context"
	"fmt"
	"time"

	"github.com/exaring/otelpgx"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
)

// MustOpen opens a pgxpool with the platform-default tracer.
// dsn typically comes from an envFrom-mounted Secret (ADR-0202).
func MustOpen(ctx context.Context, dsn string) *pgxpool.Pool {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		panic(err)
	}
	// PgBouncer transaction-mode compatibility (ADR-0300): `DescribeExec` describes a statement without creating a
	// server-side prepared statement. Still required — PgBouncer honours them only when `max_prepared_statements`
	// is above zero, and the CNPG Pooler does not set it. Turning it on is an ADR-0300 amendment, not a values edit.
	cfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeDescribeExec
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		panic(err)
	}
	// Bounded startup retry: on a cold cluster Postgres may not accept connections yet, and a panic here yields
	// CrashLoopBackOff with a growing delay. Runtime blips need nothing: pgxpool reconnects and /readyz parks the pod.
	err = retry(ctx, pool.Ping)
	if err != nil {
		panic(err)
	}
	// Auto-register the /readyz check for this dependency (ADR-0500).
	observability.RegisterReadinessCheck("postgres", pool.Ping)
	return pool
}

// retry calls fn until it succeeds, a ~60s budget elapses, or ctx is cancelled,
// backing off 500ms→5s between attempts. Returns fn's last error on give-up.
func retry(ctx context.Context, fn func(context.Context) error) error {
	const budget = 60 * time.Second
	deadline := time.Now().Add(budget)
	delay := 500 * time.Millisecond
	for {
		err := fn(ctx)
		if err == nil {
			return nil
		}
		if time.Now().After(deadline) {
			return err
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("dbmw: startup retry cancelled: %w", ctx.Err())
		case <-time.After(delay):
		}
		if delay < 5*time.Second {
			delay *= 2
		}
	}
}
