// Package handlers implements the ogen-generated analytics.Handler interface (ADR-0303, ADR-0700).
package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	"github.com/tabmadi/sovereign-platform-template/libs/go/id"
	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
	analytics "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/analytics"
	"github.com/tabmadi/sovereign-platform-template/services/analytics/internal/funnels"
	"github.com/tabmadi/sovereign-platform-template/services/analytics/internal/rollup"
	"github.com/tabmadi/sovereign-platform-template/services/analytics/internal/store"
)

// stateGranted is the one consent state that permits storing an event. Withdrawn
// and refused both stop emission, and the difference between them is a record of
// what the visitor did rather than a difference in what may be stored.
const stateGranted = "granted"

// maxRollupBuckets bounds one pass, so a drifted schedule cannot ask the rollup to scan the whole events table.
// Roughly a quarter.
const maxRollupBuckets = 92

type Handlers struct {
	q       *store.Queries
	funnels *funnels.Set
	log     *slog.Logger
}

func New(db *pgxpool.Pool, defs *funnels.Set, log *slog.Logger) *Handlers {
	if log == nil {
		log = slog.Default()
	}
	return &Handlers{q: store.New(db), funnels: defs, log: log}
}

var _ analytics.Handler = (*Handlers)(nil)

// RecordEvents stores a batch, and drops it whole if the session has no grant — ADR-0700's second enforcement
// point, because the first runs on a client the platform does not control.
// A drop is not an error: the collector cannot fix a missing grant and must not retry.
func (h *Handlers) RecordEvents(ctx context.Context, req *analytics.EventBatch) (*analytics.RecordResult, error) {
	granted, err := h.hasGrant(ctx, req.SessionID)
	if err != nil {
		observability.RecordError(ctx, err, observability.KindDependency)
		h.log.Error("read consent", "err", err)
		return nil, apierr.Internal("failed to read consent")
	}
	if !granted {
		return &analytics.RecordResult{Stored: 0, Dropped: len(req.Events)}, nil
	}

	stored := 0
	for i := range req.Events {
		err = h.insert(ctx, req, &req.Events[i])
		if err != nil {
			observability.RecordError(ctx, err, observability.KindDependency)
			h.log.Error("insert event", "err", err)
			return nil, apierr.Internal("failed to record events")
		}
		stored++
	}
	return &analytics.RecordResult{Stored: stored, Dropped: 0}, nil
}

// SummariseEvents: Read-only and carrying no authorization of its own (ADR-0700): the panel performs the
// authoritative check in its render layer, and this service is not reachable from a browser.
func (h *Handlers) SummariseEvents(
	ctx context.Context, params analytics.SummariseEventsParams,
) ([]analytics.EventSummary, error) {
	since := pgtype.Timestamptz{Time: params.Since.UTC(), Valid: true}
	rows, err := h.q.SummariseEvents(ctx, since)
	if err != nil {
		observability.RecordError(ctx, err, observability.KindDependency)
		h.log.Error("summarise events", "err", err)
		return nil, apierr.Internal("failed to summarise events")
	}
	out := make([]analytics.EventSummary, 0, len(rows))
	for _, row := range rows {
		summary := analytics.EventSummary{
			Name:        row.Name,
			Occurrences: int(row.Occurrences),
			Sessions:    int(row.Sessions),
		}
		out = append(out, summary)
	}
	return out, nil
}

// RecordConsent: Every field makes the consent demonstrable later (GDPR Art. 7(1)): the purpose version, because a
// changed purpose is a new consent, and the source, because a `gpc` row is a refusal nobody was prompted for.
func (h *Handlers) RecordConsent(ctx context.Context, req *analytics.ConsentInput) (*analytics.Consent, error) {
	params := store.UpsertConsentParams{
		SessionID:      req.SessionID,
		IdentityID:     optText(req.IdentityID),
		State:          string(req.State),
		PurposeVersion: req.PurposeVersion,
		Source:         string(req.Source),
	}
	row, err := h.q.UpsertConsent(ctx, params)
	if err != nil {
		observability.RecordError(ctx, err, observability.KindDependency)
		h.log.Error("upsert consent", "err", err)
		return nil, apierr.Internal("failed to record consent")
	}
	return &analytics.Consent{
		SessionID:      row.SessionID,
		IdentityID:     fromText(row.IdentityID),
		State:          analytics.ConsentState(row.State),
		PurposeVersion: row.PurposeVersion,
		Source:         analytics.ConsentSource(row.Source),
		DecidedAt:      row.DecidedAt.Time,
	}, nil
}

// GetConsent: A session with no row has not answered, which is a 404 rather than an invented refusal: the control
// prompts for one and must never prompt for the other.
func (h *Handlers) GetConsent(ctx context.Context, params analytics.GetConsentParams) (*analytics.Consent, error) {
	row, err := h.q.GetConsent(ctx, params.SessionID)
	if err != nil {
		return nil, apierr.NotFound("no consent decision for that session")
	}
	return &analytics.Consent{
		SessionID:      row.SessionID,
		IdentityID:     fromText(row.IdentityID),
		State:          analytics.ConsentState(row.State),
		PurposeVersion: row.PurposeVersion,
		Source:         analytics.ConsentSource(row.Source),
		DecidedAt:      row.DecidedAt.Time,
	}, nil
}

// NewError renders any handler error as RFC 9457 problem details (ADR-0303).
func (h *Handlers) NewError(ctx context.Context, err error) *analytics.ErrorStatusCode {
	e, ok := apierr.As(err)
	if !ok {
		e = apierr.Internal(err.Error())
	}
	e = e.WithTrace(ctx)

	problem := analytics.Problem{Type: e.Type, Title: e.Title, Status: e.Status}
	if e.Detail != "" {
		problem.Detail = analytics.NewOptString(e.Detail)
	}
	if e.TraceID != "" {
		problem.TraceID = analytics.NewOptString(e.TraceID)
	}
	for _, v := range e.Errors {
		problem.Errors = append(problem.Errors, analytics.ProblemErrorsItem{Pointer: v.Pointer, Message: v.Message})
	}
	return &analytics.ErrorStatusCode{StatusCode: e.Status, Response: problem}
}

func optText(v analytics.OptString) pgtype.Text {
	s, ok := v.Get()
	if !ok {
		return pgtype.Text{}
	}
	return pgtype.Text{String: s, Valid: true}
}

func fromText(v pgtype.Text) analytics.OptString {
	if !v.Valid {
		return analytics.OptString{}
	}
	return analytics.NewOptString(v.String)
}

// ComputeFunnelRollup: Driven by a Temporal Schedule and idempotent by construction: each bucket is replaced, so a
// pass over a window that is still filling is the normal case (ADR-0700, ADR-0302). The window is bounded here rather
// than trusted from the caller.
func (h *Handlers) ComputeFunnelRollup(
	ctx context.Context, req *analytics.RollupWindow, params analytics.ComputeFunnelRollupParams,
) (*analytics.RollupResult, error) {
	fn, ok := h.funnels.Get(params.Funnel)
	if !ok {
		return nil, apierr.NotFound("no funnel with that id")
	}
	if !req.From.Before(req.To) {
		return nil, apierr.BadRequest("`from` must be before `to`")
	}
	buckets := rollup.Buckets(req.From, req.To)
	if len(buckets) > maxRollupBuckets {
		detail := fmt.Sprintf(
			"the window covers %d days; the limit is %d",
			len(buckets),
			maxRollupBuckets,
		)
		return nil, apierr.BadRequest(detail)
	}

	written := 0
	for _, b := range buckets {
		n, err := h.rollupBucket(ctx, fn, b)
		if err != nil {
			return nil, err
		}
		written += n
	}

	return &analytics.RollupResult{
		Funnel:  fn.ID,
		Buckets: len(buckets),
		Rows:    written,
	}, nil
}

func (h *Handlers) GetFunnelRollup(
	ctx context.Context, params analytics.GetFunnelRollupParams,
) ([]analytics.FunnelRollupRow, error) {
	_, ok := h.funnels.Get(params.Funnel)
	if !ok {
		return nil, apierr.NotFound("no funnel with that id")
	}
	rows, err := h.q.GetFunnelRollup(
		ctx,
		store.GetFunnelRollupParams{
			Funnel:        params.Funnel,
			BucketStart:   pgtype.Timestamptz{Time: params.From.UTC(), Valid: true},
			BucketStart_2: pgtype.Timestamptz{Time: params.To.UTC(), Valid: true},
		},
	)
	if err != nil {
		observability.RecordError(ctx, err, observability.KindDependency)
		h.log.Error("read funnel rollup", "funnel", params.Funnel, "err", err)
		return nil, apierr.Internal("failed to read the rollup")
	}
	out := make([]analytics.FunnelRollupRow, 0, len(rows))
	for _, r := range rows {
		out = append(
			out,
			analytics.FunnelRollupRow{
				Funnel:      r.Funnel,
				StepIndex:   int(r.StepIndex),
				StepName:    r.StepName,
				BucketStart: r.BucketStart.Time,
				BucketEnd:   r.BucketEnd.Time,
				Sessions:    int(r.Sessions),
			},
		)
	}
	return out, nil
}

// A session with no row never answered, and the answer is a plain no. Any other error is the database being
// unreachable, and reading that as "no consent" would discard every event during an outage.
func (h *Handlers) hasGrant(ctx context.Context, sessionID string) (bool, error) {
	row, err := h.q.GetConsent(ctx, sessionID)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("read consent: %w", err)
	}
	return row.State == stateGranted, nil
}

func (h *Handlers) insert(ctx context.Context, batch *analytics.EventBatch, event *analytics.Event) error {
	key, err := id.New("evt")
	if err != nil {
		return fmt.Errorf("mint event id: %w", err)
	}
	properties := []byte("{}")
	props, ok := event.Properties.Get()
	if ok {
		properties, err = json.Marshal(props)
		if err != nil {
			return fmt.Errorf("marshal event properties: %w", err)
		}
	}
	deviceClass := "unknown"
	class, ok := batch.DeviceClass.Get()
	if ok {
		deviceClass = string(class)
	}
	params := store.InsertEventParams{
		ID:          pgtype.UUID{Bytes: key.UUID(), Valid: true},
		SessionID:   batch.SessionID,
		IdentityID:  optText(batch.IdentityID),
		Name:        event.Name,
		Properties:  properties,
		DeviceClass: deviceClass,
		OccurredAt:  pgtype.Timestamptz{Time: event.OccurredAt.UTC(), Valid: true},
	}
	err = h.q.InsertEvent(ctx, params)
	if err != nil {
		return fmt.Errorf("insert event: %w", err)
	}
	return nil
}

// rollupBucket computes and writes one bucket, returning the rows written.
func (h *Handlers) rollupBucket(
	ctx context.Context, fn funnels.Funnel, b [2]time.Time,
) (int, error) {
	rows, err := h.q.FunnelStepFirstSeen(
		ctx,
		store.FunnelStepFirstSeenParams{
			OccurredAt:   pgtype.Timestamptz{Time: b[0], Valid: true},
			OccurredAt_2: pgtype.Timestamptz{Time: b[1], Valid: true},
			Column3:      fn.Steps,
		},
	)
	if err != nil {
		observability.RecordError(ctx, err, observability.KindDependency)
		h.log.Error("funnel rollup: read steps", "funnel", fn.ID, "bucket", b[0], "err", err)
		return 0, apierr.Internal("failed to compute the rollup")
	}

	steps := make([]rollup.Step, 0, len(rows))
	for _, r := range rows {
		steps = append(
			steps,
			rollup.Step{
				SessionID: r.SessionID,
				Name:      r.Name,
				FirstSeen: r.FirstSeen.Time,
			},
		)
	}
	counts := rollup.Count(fn.Steps, steps)

	// Every step is written, including the zeroes. A bucket missing its later steps
	// would render as a funnel that ends early rather than one nobody completed, and
	// those are different findings.
	written := 0
	for i, name := range fn.Steps {
		err = h.q.UpsertFunnelRollup(
			ctx,
			store.UpsertFunnelRollupParams{
				Funnel:      fn.ID,
				StepIndex:   int32(i),
				StepName:    name,
				BucketStart: pgtype.Timestamptz{Time: b[0], Valid: true},
				BucketEnd:   pgtype.Timestamptz{Time: b[1], Valid: true},
				Sessions:    counts[i],
			},
		)
		if err != nil {
			observability.RecordError(ctx, err, observability.KindDependency)
			h.log.Error("funnel rollup: write bucket", "funnel", fn.ID, "step", name, "err", err)
			return 0, apierr.Internal("failed to write the rollup")
		}
		written++
	}
	return written, nil
}
