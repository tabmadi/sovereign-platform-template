package workflows

import (
	"context"
	"strings"
	"sync"
	"testing"

	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/testsuite"
)

// EraseSubject gives every store the same pseudonym, and it erases the identity and then the tuples after the stores.
func TestEraseSubjectOrderAndPseudonym(t *testing.T) {
	t.Parallel()
	var ts testsuite.WorkflowTestSuite
	env := ts.NewTestWorkflowEnvironment()

	var mu sync.Mutex
	var steps []string
	pseudonyms := map[string]bool{}
	env.RegisterActivityWithOptions(
		func(_ context.Context, service, _, pseudonym string) error {
			mu.Lock()
			defer mu.Unlock()
			steps = append(steps, service)
			pseudonyms[pseudonym] = true
			return nil
		},
		activity.RegisterOptions{Name: "EraseServiceDataActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string) error { steps = append(steps, "identity"); return nil },
		activity.RegisterOptions{Name: "EraseIdentityActivity"},
	)
	env.RegisterActivityWithOptions(
		func(context.Context, string) error { steps = append(steps, "tuples"); return nil },
		activity.RegisterOptions{Name: "EraseAuthzTuplesActivity"},
	)

	env.ExecuteWorkflow(EraseSubject, EraseSubjectInput{IdentityID: "id-1"})
	err := env.GetWorkflowError()
	if err != nil {
		t.Fatal(err)
	}
	got := strings.Join(steps, ",")
	if got != "orgs,orders,payment,catalog,analytics,identity,tuples" {
		t.Errorf("steps = %s", got)
	}
	if len(pseudonyms) != 1 {
		t.Fatalf("pseudonyms = %v, want one for every store", pseudonyms)
	}
	for p := range pseudonyms {
		if !strings.HasPrefix(p, "erased-") {
			t.Errorf("pseudonym %q has no erased- prefix", p)
		}
	}
}
