// Package edge reads the Oathkeeper access-rule file the edge gates judge (ADR-0305, ADR-0306).
package edge

import "github.com/tabmadi/sovereign-platform-template/tools/internal/repo"

type Rule struct {
	ID    string `json:"id"`
	Match struct {
		URL string `json:"url"`
	} `json:"match"`
	Authorizer struct {
		Handler string `json:"handler"`
	} `json:"authorizer"`
}

func Rules(path string) ([]Rule, error) {
	return repo.ReadJSON[[]Rule](path)
}
