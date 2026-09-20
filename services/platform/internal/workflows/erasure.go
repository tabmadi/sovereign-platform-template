package workflows

import (
	"fmt"

	"go.temporal.io/sdk/workflow"
)

type EraseSubjectInput struct {
	// IdentityID is the Kratos identity — the `user:<id>` subject every store keys
	// personal data by.
	IdentityID string
}

// EraseSubject runs a right-to-erasure request across every store holding the subject's data (GDPR Art. 17).
// The authz tuples go last: while they exist the services can still answer questions about the subject, which is
// what lets a failed run be retried. Each store is its own activity, so a failure names the store that failed.
func EraseSubject(ctx workflow.Context, in EraseSubjectInput) error {
	ctx = activityOptions(ctx)

	// Each activity decides delete-versus-anonymise from the column's declared class. That decision is per category and
	// never per request, because a request that could choose could erase an audit obligation.
	for _, service := range []string{"orgs", "orders", "payment", "catalog", "analytics"} {
		err := workflow.ExecuteActivity(ctx, "EraseServiceDataActivity", service, in.IdentityID).
			Get(ctx, nil)
		if err != nil {
			return fmt.Errorf("erase subject: %s: %w", service, err)
		}
	}

	// The identity itself, which is what makes the subject unable to sign in again.
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

// ExportSubject reads the same stores erasure writes, in the same order (GDPR Art. 15 and 20, ADR-0301): the tuples
// describe what the subject could reach, and reading them first would describe a state the export does not match.
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

// RetentionPass: Driven by the registry rather than a list here (ADR-0301): docs/reference/data-classes.md is
// generated from the migrations' tags, so a newly tagged column is covered without anyone adding it.
func RetentionPass(ctx workflow.Context) error {
	ctx = activityOptions(ctx)
	err := workflow.ExecuteActivity(ctx, "ApplyRetentionActivity").Get(ctx, nil)
	if err != nil {
		return fmt.Errorf("retention pass: %w", err)
	}
	return nil
}
