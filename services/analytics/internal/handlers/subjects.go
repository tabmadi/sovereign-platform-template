package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/go-faster/jx"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	analytics "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/analytics"
	"github.com/tabmadi/sovereign-platform-template/services/analytics/internal/retention"
	"github.com/tabmadi/sovereign-platform-template/services/analytics/internal/store"
)

// defaultSubjectPage is the page size when the caller names none.
const defaultSubjectPage = 500

// ApplyAnalyticsRetention runs from the platform worker's daily RetentionPass, per ADR-0301.
func (h *Handlers) ApplyAnalyticsRetention(ctx context.Context) (*analytics.RetentionResult, error) {
	res, err := retention.Apply(ctx, h.db, time.Now())
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	h.log.InfoContext(
		ctx,
		"retention pass applied",
		"partitions_created",
		res.Created,
		"partitions_dropped",
		res.Dropped,
		"default_rows_deleted",
		res.DefaultRowsDeleted,
	)
	return &analytics.RetentionResult{
		PartitionsCreated:  nonNil(res.Created),
		PartitionsDropped:  nonNil(res.Dropped),
		DefaultRowsDeleted: int(res.DefaultRowsDeleted),
	}, nil
}

// ListAnalyticsSubjects pages through the identities that this store holds data for, for the retention sweep.
func (h *Handlers) ListAnalyticsSubjects(
	ctx context.Context, params analytics.ListAnalyticsSubjectsParams,
) (*analytics.SubjectPage, error) {
	limit := params.Limit.Or(defaultSubjectPage)
	ids, err := h.q.ListAnalyticsSubjects(
		ctx,
		store.ListAnalyticsSubjectsParams{
			After:    params.After.Or(""),
			PageSize: int64(limit),
		},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	page := &analytics.SubjectPage{Subjects: nonNil(ids)}
	if len(ids) == limit {
		page.Next = analytics.NewOptString(ids[len(ids)-1])
	}
	return page, nil
}

// ExportAnalyticsSubject reads every event and consent record of the subject's sessions, per ADR-0301.
func (h *Handlers) ExportAnalyticsSubject(
	ctx context.Context, params analytics.ExportAnalyticsSubjectParams,
) (*analytics.SubjectAnalytics, error) {
	events, err := h.q.ExportSubjectEvents(ctx, params.IdentityID)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	consents, err := h.q.ExportSubjectConsent(ctx, params.IdentityID)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	out := &analytics.SubjectAnalytics{
		Events:   make([]analytics.SubjectEvent, 0, len(events)),
		Consents: make([]analytics.SubjectConsent, 0, len(consents)),
	}
	for _, e := range events {
		props, err := properties(e.Properties)
		if err != nil {
			return nil, apierr.Internal(err.Error())
		}
		out.Events = append(
			out.Events,
			analytics.SubjectEvent{
				SessionID:   e.SessionID,
				Name:        e.Name,
				Properties:  props,
				DeviceClass: e.DeviceClass,
				OccurredAt:  e.OccurredAt.Time,
			},
		)
	}
	for _, c := range consents {
		out.Consents = append(
			out.Consents,
			analytics.SubjectConsent{
				SessionID:      c.SessionID,
				State:          analytics.SubjectConsentState(c.State),
				PurposeVersion: c.PurposeVersion,
				Source:         analytics.SubjectConsentSource(c.Source),
				DecidedAt:      c.DecidedAt.Time,
				UpdatedAt:      c.UpdatedAt.Time,
			},
		)
	}
	return out, nil
}

// EraseAnalyticsSubject anonymises the subject's identifiers, per ADR-0301. A second call finds nothing to change.
func (h *Handlers) EraseAnalyticsSubject(
	ctx context.Context, req *analytics.ErasureRequest, params analytics.EraseAnalyticsSubjectParams,
) (*analytics.AnalyticsErasure, error) {
	row, err := h.q.EraseSubjectAnalytics(
		ctx,
		store.EraseSubjectAnalyticsParams{
			IdentityID: params.IdentityID,
			Pseudonym:  req.Pseudonym,
		},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	return &analytics.AnalyticsErasure{Events: int(row.Events), Consents: int(row.Consents)}, nil
}

func properties(raw []byte) (analytics.SubjectEventProperties, error) {
	fields := map[string]json.RawMessage{}
	err := json.Unmarshal(raw, &fields)
	if err != nil {
		return nil, fmt.Errorf("decode event properties: %w", err)
	}
	out := make(analytics.SubjectEventProperties, len(fields))
	for k, v := range fields {
		out[k] = jx.Raw(v)
	}
	return out, nil
}

// nonNil keeps an empty list `[]` on the wire. The contract requires the field, and `null` is not a list.
func nonNil(v []string) []string {
	if v == nil {
		return []string{}
	}
	return v
}
