// Package dbmw wires pgx with OTel tracing and per-query metrics, per ADR-0500.
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
// dsn usually comes from a Secret mounted with envFrom, per ADR-0202.
func MustOpen(ctx context.Context, dsn string) *pgxpool.Pool {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		panic(err)
	}
	// PgBouncer transaction mode needs this, per ADR-0300. `DescribeExec` describes a statement and creates no
	// server-side prepared statement. PgBouncer honours prepared statements only when `max_prepared_statements` is
	// above zero, and the CNPG Pooler does not set it. To turn it on, amend ADR-0300. A values edit is not enough.
	cfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeDescribeExec
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		panic(err)
	}
	// A bounded startup retry. On a cold cluster, Postgres can refuse connections, and a panic here gives
	// CrashLoopBackOff with a growing delay. A short fault at runtime needs nothing: pgxpool reconnects and /readyz
	// parks the pod.
	err = retry(ctx, pool.Ping)
	if err != nil {
		panic(err)
	}
	// Register the /readyz check for this dependency, per ADR-0500.
	observability.RegisterReadinessCheck("postgres", pool.Ping)
	return pool
}

// retry calls fn until it succeeds, a budget of about 60s ends, or ctx is cancelled.
// The wait between attempts grows from 500ms to 5s. When it stops, it returns fn's last error.
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
