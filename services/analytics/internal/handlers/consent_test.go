package handlers

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	analytics "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/analytics"
	"github.com/tabmadi/sovereign-platform-template/services/analytics/internal/store"
)

// fakeConsent answers GetConsent and counts the inserts. Any other store call panics, because ingest makes none.
type fakeConsent struct {
	store.Querier

	consent  store.GetConsentRow
	err      error
	inserted int
}

func (f *fakeConsent) GetConsent(context.Context, string) (store.GetConsentRow, error) {
	return f.consent, f.err
}

func (f *fakeConsent) InsertEvent(context.Context, store.InsertEventParams) error {
	f.inserted++
	return nil
}

func twoEvents() *analytics.EventBatch {
	at := time.Date(2026, 10, 3, 9, 0, 0, 0, time.UTC)
	return &analytics.EventBatch{
		SessionID: "session-1",
		Events:    []analytics.Event{{Name: "viewed", OccurredAt: at}, {Name: "added", OccurredAt: at}},
	}
}

// The second enforcement point of ADR-0700. The browser wrapper is the first, and it runs on a client that the
// platform does not control.
func TestRecordEventsConsent(t *testing.T) {
	t.Parallel()

	drops := []struct {
		name string
		q    *fakeConsent
	}{
		{"ANL-001 a session with no decision drops the batch", &fakeConsent{err: pgx.ErrNoRows}},
		{"ANL-002 a withdrawn grant drops the batch", &fakeConsent{consent: store.GetConsentRow{State: "withdrawn"}}},
	}
	for _, tc := range drops {
		t.Run(
			tc.name,
			func(t *testing.T) {
				t.Parallel()
				h := &Handlers{q: tc.q}
				res, err := h.RecordEvents(context.Background(), twoEvents())
				if err != nil {
					t.Fatalf("a drop is not an error: %v", err)
				}
				if res.Stored != 0 || res.Dropped != 2 || tc.q.inserted != 0 {
					t.Fatalf("stored %d, dropped %d, inserted %d, want 0, 2, 0", res.Stored, res.Dropped, tc.q.inserted)
				}
			},
		)
	}

	t.Run(
		"ANL-003 a granted session stores every event",
		func(t *testing.T) {
			t.Parallel()
			q := &fakeConsent{consent: store.GetConsentRow{State: stateGranted}}
			h := &Handlers{q: q}
			res, err := h.RecordEvents(context.Background(), twoEvents())
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if res.Stored != 2 || res.Dropped != 0 || q.inserted != 2 {
				t.Fatalf("stored %d, dropped %d, inserted %d, want 2, 0, 2", res.Stored, res.Dropped, q.inserted)
			}
		},
	)

	// An unreadable consent table is an outage, not a refusal. Reading it as a refusal would drop every event.
	t.Run(
		"ANL-004 a failed consent read is internal and stores nothing",
		func(t *testing.T) {
			t.Parallel()
			q := &fakeConsent{err: errors.New("db down")}
			h := &Handlers{q: q, log: slog.New(slog.DiscardHandler)}
			_, err := h.RecordEvents(context.Background(), twoEvents())
			e, ok := apierr.As(err)
			if !ok || e.Status != 500 {
				t.Fatalf("err = %v, want a 500", err)
			}
			if q.inserted != 0 {
				t.Fatalf("inserted %d, want 0", q.inserted)
			}
		},
	)
}
