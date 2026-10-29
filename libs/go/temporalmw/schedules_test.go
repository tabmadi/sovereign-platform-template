package temporalmw

import (
	"context"
	"fmt"
	"slices"
	"testing"

	commonpb "go.temporal.io/api/common/v1"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/temporal"
)

type fakeSchedules struct {
	existing map[string]*client.ScheduleDescription
	memo     map[string]*commonpb.Memo
	created  []string
	updated  []string
	deleted  []string
}

func (f *fakeSchedules) Create(_ context.Context, o client.ScheduleOptions) (client.ScheduleHandle, error) {
	if _, ok := f.existing[o.ID]; ok {
		return nil, temporal.ErrScheduleAlreadyRunning
	}
	f.created = append(f.created, o.ID)
	return &fakeHandle{fake: f, id: o.ID}, nil
}

func (f *fakeSchedules) List(context.Context, client.ScheduleListOptions) (client.ScheduleListIterator, error) {
	var entries []*client.ScheduleListEntry
	for id := range f.existing {
		entries = append(entries, &client.ScheduleListEntry{ID: id, Memo: f.memo[id]})
	}
	return &fakeIterator{entries: entries}, nil
}

func (f *fakeSchedules) GetHandle(_ context.Context, id string) client.ScheduleHandle {
	return &fakeHandle{fake: f, id: id}
}

type fakeIterator struct{ entries []*client.ScheduleListEntry }

func (it *fakeIterator) HasNext() bool { return len(it.entries) > 0 }

func (it *fakeIterator) Next() (*client.ScheduleListEntry, error) {
	e := it.entries[0]
	it.entries = it.entries[1:]
	return e, nil
}

type fakeHandle struct {
	client.ScheduleHandle

	fake *fakeSchedules
	id   string
}

func (h *fakeHandle) Update(_ context.Context, o client.ScheduleUpdateOptions) error {
	u, err := o.DoUpdate(client.ScheduleUpdateInput{Description: *h.fake.existing[h.id]})
	if err != nil {
		return fmt.Errorf("do update: %w", err)
	}
	h.fake.existing[h.id].Schedule = *u.Schedule
	h.fake.updated = append(h.fake.updated, h.id)
	return nil
}

func (h *fakeHandle) Delete(context.Context) error {
	h.fake.deleted = append(h.fake.deleted, h.id)
	return nil
}

func ownedBy(t *testing.T, owner string) *commonpb.Memo {
	t.Helper()
	p, err := converter.GetDefaultDataConverter().ToPayload(owner)
	if err != nil {
		t.Fatal(err)
	}
	return &commonpb.Memo{Fields: map[string]*commonpb.Payload{ownerMemo: p}}
}

// PLT-015, PLT-016, and PLT-017.
const (
	kept    = "kept"
	dropped = "dropped"
)

func TestReconcileSchedules(t *testing.T) {
	t.Parallel()
	paused := &client.ScheduleDescription{Schedule: client.Schedule{State: &client.ScheduleState{Paused: true}}}
	f := &fakeSchedules{
		existing: map[string]*client.ScheduleDescription{
			kept:       paused,
			dropped:    {},
			"foreign":  {},
			"stranger": {},
		},
		memo: map[string]*commonpb.Memo{
			dropped:    ownedBy(t, "platform"),
			"foreign":  ownedBy(t, "orders"),
			"stranger": nil,
		},
	}
	want := []Schedule{
		{ID: kept, Workflow: "A", TaskQueue: "q", Cron: "0 3 * * *", Note: "n"},
		{ID: "new", Workflow: "B", TaskQueue: "q", Cron: "0 4 * * *"},
	}
	err := ReconcileSchedules(context.Background(), f, "platform", want)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(f.created, []string{"new"}) {
		t.Errorf("created: got %v, want [new]", f.created)
	}
	if !slices.Equal(f.updated, []string{kept}) {
		t.Errorf("updated: got %v, want [kept]", f.updated)
	}
	if !slices.Equal(f.deleted, []string{dropped}) {
		t.Errorf("deleted: got %v, want [dropped], since only the owner's dropped schedule goes", f.deleted)
	}
	got := f.existing[kept].Schedule
	if !got.State.Paused || got.State.Note != "n" || got.Spec.CronExpressions[0] != "0 3 * * *" {
		t.Errorf("kept: got %+v %+v, want the new spec and note with the pause kept", got.State, got.Spec)
	}
}

func TestParseSchedules(t *testing.T) {
	t.Parallel()
	const entry = "  - {id: a, workflow: W, taskQueue: q, cron: c}\n"
	cases := []struct {
		name, data string
		ok         bool
	}{
		{"a full entry", "schedules:\n  - {id: a, workflow: W, taskQueue: q, cron: '0 3 * * *', args: [[x, y]]}\n", true},
		{"no cron", "schedules:\n  - {id: a, workflow: W, taskQueue: q}\n", false},
		{"a repeated id", "schedules:\n" + entry + entry, false},
	}
	for _, c := range cases {
		t.Run(
			c.name,
			func(t *testing.T) {
				t.Parallel()
				_, err := ParseSchedules([]byte(c.data))
				if (err == nil) != c.ok {
					t.Errorf("err: got %v, want ok=%v", err, c.ok)
				}
			},
		)
	}
}
