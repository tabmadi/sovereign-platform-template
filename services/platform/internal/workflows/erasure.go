package workflows

import (
	"fmt"

	"go.temporal.io/sdk/workflow"
)

type EraseSubjectInput struct {
	// IdentityID is the Kratos identity: the `user:<id>` subject that every store uses
	// as the key for personal data.
	IdentityID string
}

// EraseSubject runs a right-to-erasure request across every store with the subject's data, per GDPR Art. 17.
// The authz tuples go last. While they exist, the services can still answer questions about the subject, so a failed
// run can be retried. Each store is its own activity, so a failure names the store that failed.
func EraseSubject(ctx workflow.Context, in EraseSubjectInput) error {
	ctx = activityOptions(ctx)

	// Each activity chooses to delete or anonymise from the column's declared class. That choice is per category and
	// never per request, because a request that could choose could erase an audit obligation.
	for _, service := range []string{"orgs", "orders", "payment", "catalog", "analytics"} {
		err := workflow.ExecuteActivity(ctx, "EraseServiceDataActivity", service, in.IdentityID).
			Get(ctx, nil)
		if err != nil {
			return fmt.Errorf("erase subject: %s: %w", service, err)
		}
	}

	// The identity itself. Its erasure stops the subject from signing in again.
	err := workflow.ExecuteActivity(ctx, "EraseIdentityActivity", in.IdentityID).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("erase subject: identity: %w", err)
	}

	// The authz tuples last, for the reason above.
	err = workflow.ExecuteActivity(ctx, "EraseAuthzTuplesActivity", in.IdentityID).Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("erase subject: authz tuples: %w", err)
	}
	return nil
}

// ExportSubject reads the same stores that erasure writes, in the same order, per GDPR Art. 15 and 20 and ADR-0301.
// The tuples describe what the subject could reach. Reading them first would describe a state that the export does
// not match.
func ExportSubject(ctx workflow.Context, in EraseSubjectInput) (string, error) {
	ctx = activityOptions(ctx)
	var location string
	err := workflow.ExecuteActivity(ctx, "ExportSubjectDataActivity", in.IdentityID).
		Get(ctx, &location)
	if err != nil {
		return "", fmt.Errorf("export subject: %w", err)
	}
	return location, nil
}

// RetentionPass reads the registry and not a list here, per ADR-0301. docs/reference/data-classes.md is generated
// from the migrations' tags, so a newly tagged column is covered and nobody needs to add it.
func RetentionPass(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	err := workflow.ExecuteActivity(ctx, "ApplyRetentionActivity").Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("retention pass: %w", err)
	}
	return nil
}
