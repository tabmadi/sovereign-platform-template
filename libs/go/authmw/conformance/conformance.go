// Package conformance exercises the edge→service identity contract (ADR-0305, ADR-0304).
package conformance

import (
	_ "embed"
	"encoding/json"
	"fmt"

	"github.com/tabmadi/sovereign-platform-template/libs/go/authmw"
)

//go:embed fixtures.json
var fixturesJSON []byte

type Fixture struct {
	Name        string            `json:"name"`
	Headers     map[string]string `json:"headers"`
	Want        WantPrincipal     `json:"want"`
	Subject     string            `json:"subject"`
	RequireRole string            `json:"require_role"`
	WantAllowed bool              `json:"want_allowed"`
}

type WantPrincipal struct {
	UserID string   `json:"user_id"`
	OrgID  string   `json:"org_id"`
	Roles  []string `json:"roles"`
}

func Fixtures() ([]Fixture, error) {
	var fs []Fixture
	err := json.Unmarshal(fixturesJSON, &fs)
	if err != nil {
		return nil, fmt.Errorf("decode fixtures: %w", err)
	}
	return fs, nil
}

// RoleAllowed is the hermetic stand-in for the OpenFGA Checker (ADR-0304); real services delegate to libs/go/authz.
func RoleAllowed(p *authmw.Principal, requiredRole string) bool {
	return p.Authenticated() && p.HasRole(requiredRole)
}
