// Command lint-alert-severity asserts every alert rule carries a severity ADR-0502 admits, and that the Watchdog
// exists.
package main

import (
	"path/filepath"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

const rulesDir = "infra/observability/alerts"

// watchdogAlert is the dead man's switch ADR-0502 names.
const watchdogAlert = "Watchdog"

// The vocabulary. Not configurable: it is the routing tree's matcher set.
var allowed = map[string]bool{"page": true, "ticket": true}

type ruleFile struct {
	Groups []struct {
		Name  string `yaml:"name"`
		Rules []struct {
			Alert  string            `yaml:"alert"`
			Record string            `yaml:"record"`
			Labels map[string]string `yaml:"labels"`
		} `yaml:"rules"`
	} `yaml:"groups"`
}

func main() {
	lint.Main("alert severities do not match ADR-0502", run)
}

func run(r *lint.Report) error {
	paths, err := repo.Glob(filepath.Join(rulesDir, "*.yaml"))
	if err != nil {
		return err
	}
	alerts, watchdog := 0, false
	for _, path := range paths {
		// Chart.yaml and any other non-rule YAML that lands here parses cleanly
		// into an empty Groups, so it is skipped rather than reported.
		rf, err := repo.ReadYAML[ruleFile](path)
		if err != nil {
			r.Addf("%v", err)
			continue
		}
		for _, g := range rf.Groups {
			for _, rule := range g.Rules {
				if rule.Alert == "" {
					continue // a recording rule carries no severity
				}
				alerts++
				if rule.Alert == watchdogAlert {
					watchdog = true
				}
				sev, ok := rule.Labels["severity"]
				switch {
				case !ok:
					r.Addf("%s: %s carries no severity", path, rule.Alert)
				case !allowed[sev]:
					r.Addf("%s: %s carries severity %q, which is not page or ticket", path, rule.Alert, sev)
				}
			}
		}
	}
	if !watchdog {
		r.Addf("no %s rule in %s — nothing detects a dead alerting pipeline (ADR-0502)", watchdogAlert, rulesDir)
	}
	r.Okf("%d alert rules carry page or ticket, and the Watchdog exists", alerts)
	return nil
}
