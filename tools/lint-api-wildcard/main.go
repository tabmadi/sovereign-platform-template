// Command lint-api-wildcard enforces that the product edge rule never matches /api/ with an open path wildcard
// (ADR-0306).
package main

import (
	"errors"
	"os"
	"regexp"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/edge"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
)

// A wildcard token (`<*>`, `<**>`, or a bare `*`) directly after `/api/` — the
// collision-prone form. `/api/<{products,...}>` (an enumerated alternation) and
// literal segments are fine.
var bareAPIWildcard = regexp.MustCompile(`/api/(<\*|\*)`)

func main() {
	lint.Main("product /api rules must enumerate resources, never a bare /api wildcard", run)
}

func run(r *lint.Report) error {
	if len(os.Args) != 2 {
		return errors.New("usage: lint-api-wildcard <access-rules.json>")
	}
	rules, err := edge.Rules(os.Args[1])
	if err != nil {
		return err
	}
	for _, rule := range rules {
		if bareAPIWildcard.MatchString(rule.Match.URL) {
			const form = "%s: match url %q has a bare wildcard after /api/ — enumerate resources instead (/api/<{a,b,c}>)"
			r.Addf(form, rule.ID, rule.Match.URL)
		}
	}
	r.Okf("no bare /api wildcard in %d rules", len(rules))
	return nil
}
