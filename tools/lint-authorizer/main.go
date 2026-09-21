// Command lint-authorizer enforces the ops-tier authorizer policy (ADR-0306):
package main

import (
	"errors"
	"os"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/edge"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
)

func main() {
	lint.Main("ops dashboard rules must authorize via remote_json, never allow", run)
}

func run(r *lint.Report) error {
	if len(os.Args) != 2 {
		return errors.New("usage: lint-authorizer <access-rules.json>")
	}
	rules, err := edge.Rules(os.Args[1])
	if err != nil {
		return err
	}
	ops := 0
	for _, rule := range rules {
		// Ops dashboards are identified by the `ops-` rule-id prefix (one origin
		// per tool under *.ops.<host>). They must use remote_json, not allow.
		if !strings.HasPrefix(rule.ID, "ops-") {
			continue
		}
		ops++
		if rule.Authorizer.Handler != "remote_json" {
			r.Addf("%s: authorizer is %q, expected \"remote_json\"", rule.ID, rule.Authorizer.Handler)
		}
	}
	r.Okf("all ops dashboard rules use remote_json (%d rules)", ops)
	return nil
}
