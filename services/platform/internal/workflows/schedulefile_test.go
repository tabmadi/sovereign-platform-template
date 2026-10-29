package workflows_test

import (
	"reflect"
	"runtime"
	"strings"
	"testing"

	"github.com/tabmadi/sovereign-platform-template/libs/go/temporalmw"
	"github.com/tabmadi/sovereign-platform-template/services/platform/internal/workflows"
)

// PLT-014. A schedule that names an unregistered workflow starts a run that no worker picks up.
func TestScheduleFileNamesRegisteredWorkflows(t *testing.T) {
	t.Parallel()
	registered := map[string]bool{}
	for _, wf := range workflows.All() {
		full := runtime.FuncForPC(reflect.ValueOf(wf).Pointer()).Name()
		registered[full[strings.LastIndex(full, ".")+1:]] = true
	}
	schedules, err := temporalmw.ParseSchedules(workflows.ScheduleFile)
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range schedules {
		if !registered[s.Workflow] {
			t.Errorf("schedule %s names %s, which the worker does not register", s.ID, s.Workflow)
		}
	}
}
