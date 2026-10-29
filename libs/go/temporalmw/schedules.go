package temporalmw

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/temporal"
	"gopkg.in/yaml.v3"
)

// ownerMemo marks a schedule that a worker's committed file owns. A reconcile deletes such a schedule once the file
// drops it, and never deletes a schedule without the key.
const ownerMemo = "owner"

// Schedule is one entry of a worker's committed schedule file, per ADR-0302.
type Schedule struct {
	ID        string `yaml:"id"`
	Workflow  string `yaml:"workflow"`
	TaskQueue string `yaml:"taskQueue"`
	Cron      string `yaml:"cron"`
	Args      []any  `yaml:"args"`
	Note      string `yaml:"note"`
}

// ParseSchedules reads a schedule file. It fails on a repeated id, and on an entry that lacks an id, a workflow, a
// task queue, or a cron.
func ParseSchedules(data []byte) ([]Schedule, error) {
	var file struct {
		Schedules []Schedule `yaml:"schedules"`
	}
	err := yaml.Unmarshal(data, &file)
	if err != nil {
		return nil, fmt.Errorf("temporalmw: parse schedules: %w", err)
	}
	seen := map[string]bool{}
	for i, s := range file.Schedules {
		if s.ID == "" || s.Workflow == "" || s.TaskQueue == "" || s.Cron == "" {
			return nil, fmt.Errorf("temporalmw: schedule %d needs an id, a workflow, a taskQueue, and a cron", i)
		}
		if seen[s.ID] {
			return nil, fmt.Errorf("temporalmw: schedule id %s appears twice", s.ID)
		}
		seen[s.ID] = true
	}
	return file.Schedules, nil
}

// scheduleAPI is the part of client.ScheduleClient that a reconcile uses.
type scheduleAPI interface {
	Create(ctx context.Context, options client.ScheduleOptions) (client.ScheduleHandle, error)
	List(ctx context.Context, options client.ScheduleListOptions) (client.ScheduleListIterator, error)
	GetHandle(ctx context.Context, scheduleID string) client.ScheduleHandle
}

// ReconcileSchedules makes the cluster's schedules match want, per ADR-0302. It creates and updates each schedule in
// want, deletes only the schedules that owner created, and keeps each schedule's paused state.
func ReconcileSchedules(ctx context.Context, sc scheduleAPI, owner string, want []Schedule) error {
	named := map[string]bool{}
	for _, s := range want {
		named[s.ID] = true
		err := apply(ctx, sc, owner, s)
		if err != nil {
			return err
		}
	}
	return prune(ctx, sc, owner, named)
}

func apply(ctx context.Context, sc scheduleAPI, owner string, s Schedule) error {
	action := &client.ScheduleWorkflowAction{
		ID:        s.ID + "-run",
		Workflow:  s.Workflow,
		Args:      s.Args,
		TaskQueue: s.TaskQueue,
	}
	spec := client.ScheduleSpec{CronExpressions: []string{s.Cron}}
	_, err := sc.Create(
		ctx,
		client.ScheduleOptions{
			ID:     s.ID,
			Spec:   spec,
			Action: action,
			Note:   s.Note,
			Memo:   map[string]any{ownerMemo: owner},
		},
	)
	if err == nil {
		slog.InfoContext(ctx, "schedule created", "temporal.schedule.id", s.ID)
		return nil
	}
	if !errors.Is(err, temporal.ErrScheduleAlreadyRunning) {
		return fmt.Errorf("temporalmw: create schedule %s: %w", s.ID, err)
	}
	err = sc.GetHandle(ctx, s.ID).Update(
		ctx,
		client.ScheduleUpdateOptions{
			DoUpdate: func(in client.ScheduleUpdateInput) (*client.ScheduleUpdate, error) {
				current := in.Description.Schedule
				current.Spec = &spec
				current.Action = action
				if current.State == nil {
					current.State = &client.ScheduleState{}
				}
				current.State.Note = s.Note
				return &client.ScheduleUpdate{Schedule: &current}, nil
			},
		},
	)
	if err != nil {
		return fmt.Errorf("temporalmw: update schedule %s: %w", s.ID, err)
	}
	slog.InfoContext(ctx, "schedule updated", "temporal.schedule.id", s.ID)
	return nil
}

func prune(ctx context.Context, sc scheduleAPI, owner string, named map[string]bool) error {
	it, err := sc.List(ctx, client.ScheduleListOptions{})
	if err != nil {
		return fmt.Errorf("temporalmw: list schedules: %w", err)
	}
	for it.HasNext() {
		entry, err := it.Next()
		if err != nil {
			return fmt.Errorf("temporalmw: list schedules: %w", err)
		}
		if named[entry.ID] || memoOwner(entry) != owner {
			continue
		}
		err = sc.GetHandle(ctx, entry.ID).Delete(ctx)
		if err != nil {
			return fmt.Errorf("temporalmw: delete schedule %s: %w", entry.ID, err)
		}
		slog.InfoContext(ctx, "schedule deleted", "temporal.schedule.id", entry.ID)
	}
	return nil
}

func memoOwner(entry *client.ScheduleListEntry) string {
	if entry.Memo == nil {
		return ""
	}
	payload, ok := entry.Memo.GetFields()[ownerMemo]
	if !ok {
		return ""
	}
	var owner string
	err := converter.GetDefaultDataConverter().FromPayload(payload, &owner)
	if err != nil {
		return ""
	}
	return owner
}
