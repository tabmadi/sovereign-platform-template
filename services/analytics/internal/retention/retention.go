// Package retention keeps the monthly partitions of `events`, per ADR-0301 and ADR-0700. It creates each month before
// its events arrive, and it drops each month whose rows are past retention.
package retention

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Period is how long an event row is kept. A row holds a `device` column, the class with the shortest period in
// tools/codegen/retention.yaml, so the whole row goes when that class expires.
const Period = 90 * 24 * time.Hour

const (
	prefix      = "events_"
	monthLayout = "2006_01"
	// columns are the columns of `events`, named, so a moved row keeps every value in its own column.
	columns = "id, session_id, identity_id, name, properties, device_class, occurred_at, created_at"
	// checkViolation is the SQLSTATE of a new partition whose range already has rows in the default partition.
	checkViolation = "23514"
)

type Result struct {
	Created            []string
	Dropped            []string
	DefaultRowsDeleted int64
}

// Name is the partition of t's month, in UTC, such as `events_2026_10`.
func Name(t time.Time) string {
	return prefix + monthStart(t).Format(monthLayout)
}

func monthStart(t time.Time) time.Time {
	t = t.UTC()
	return time.Date(t.Year(), t.Month(), 1, 0, 0, 0, 0, time.UTC)
}

// month parses a partition name. A table that does not follow the naming is not this package's to manage.
func month(name string) (time.Time, bool) {
	rest, ok := strings.CutPrefix(name, prefix)
	if !ok {
		return time.Time{}, false
	}
	t, err := time.Parse(monthLayout, rest)
	if err != nil {
		return time.Time{}, false
	}
	return t, true
}

// Expired returns the partitions whose month ended at or before the cutoff. Every row in them is past retention.
func Expired(names []string, now time.Time) []string {
	cutoff := now.Add(-Period)
	var out []string
	for _, n := range names {
		m, ok := month(n)
		if ok && !m.AddDate(0, 1, 0).After(cutoff) {
			out = append(out, n)
		}
	}
	return out
}

// Wanted returns this month and the next. The next one exists before its first event, so that event never lands in
// the default partition.
func Wanted(now time.Time) []time.Time {
	first := monthStart(now)
	return []time.Time{first, first.AddDate(0, 1, 0)}
}

// Apply creates the wanted partitions, drops the expired ones, and deletes the expired rows of the default partition.
// Each step checks the catalog first, so a second run changes nothing.
func Apply(ctx context.Context, db *pgxpool.Pool, now time.Time) (Result, error) {
	var res Result
	existing, err := partitions(ctx, db)
	if err != nil {
		return res, err
	}
	have := make(map[string]bool, len(existing))
	for _, n := range existing {
		have[n] = true
	}
	for _, m := range Wanted(now) {
		if have[Name(m)] {
			continue
		}
		err = create(ctx, db, m)
		if err != nil {
			return res, err
		}
		res.Created = append(res.Created, Name(m))
	}
	for _, n := range Expired(existing, now) {
		_, err = db.Exec(ctx, "drop table "+pgx.Identifier{n}.Sanitize())
		if err != nil {
			return res, fmt.Errorf("drop %s: %w", n, err)
		}
		res.Dropped = append(res.Dropped, n)
	}
	tag, err := db.Exec(ctx, "delete from events_default where occurred_at < $1", now.Add(-Period))
	if err != nil {
		return res, fmt.Errorf("prune the default partition: %w", err)
	}
	res.DefaultRowsDeleted = tag.RowsAffected()
	return res, nil
}

func partitions(ctx context.Context, db *pgxpool.Pool) ([]string, error) {
	rows, err := db.Query(
		ctx,
		`
		select c.relname from pg_inherits as i
		join pg_class as c on c.oid = i.inhrelid
		where i.inhparent = 'events'::regclass`,
	)
	if err != nil {
		return nil, fmt.Errorf("list partitions: %w", err)
	}
	names, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("list partitions: %w", err)
	}
	return names, nil
}

// create adds one month. When the default partition already holds rows of that month, Postgres refuses the new
// partition. Those rows move into it in the same transaction, so no event is lost and none is counted twice.
func create(ctx context.Context, db *pgxpool.Pool, m time.Time) error {
	name := pgx.Identifier{Name(m)}.Sanitize()
	from, to := m.Format(time.RFC3339), m.AddDate(0, 1, 0).Format(time.RFC3339)
	ddl := fmt.Sprintf("create table %s partition of events for values from ('%s') to ('%s')", name, from, to)

	_, err := db.Exec(ctx, ddl)
	var pgErr *pgconn.PgError
	if err == nil || !errors.As(err, &pgErr) || pgErr.Code != checkViolation {
		if err != nil {
			return fmt.Errorf("create %s: %w", name, err)
		}
		return nil
	}

	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("create %s: begin: %w", name, err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	steps := []string{
		"create temporary table moved (like events) on commit drop",
		"with d as (delete from events_default where occurred_at >= $1 and occurred_at < $2 returning " + columns +
			") insert into moved (" + columns + ") select " + columns + " from d",
		ddl,
		"insert into events (" + columns + ") select " + columns + " from moved",
	}
	for i, sql := range steps {
		args := []any{}
		if i == 1 {
			args = []any{m, m.AddDate(0, 1, 0)}
		}
		_, err = tx.Exec(ctx, sql, args...)
		if err != nil {
			return fmt.Errorf("create %s from the default partition: %w", name, err)
		}
	}
	err = tx.Commit(ctx)
	if err != nil {
		return fmt.Errorf("create %s: commit: %w", name, err)
	}
	return nil
}
