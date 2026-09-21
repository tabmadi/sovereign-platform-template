// Command lint-api-audience gates audience against exposure, failing closed at cluster (ADR-0303).
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

const (
	audienceCluster  = "cluster"
	audienceInternal = "internal"
	audiencePublic   = "public"
)

// The OpenAPI operation keys under a path item; other keys (parameters, servers,
// summary) are not operations and carry no audience.
var httpMethods = map[string]bool{
	"get": true, "put": true, "post": true, "delete": true,
	"patch": true, "options": true, "head": true, "trace": true,
}

func main() {
	lint.Main("API audience does not match edge exposure (ADR-0303)", run)
}

func run(r *lint.Report) error {
	specs, err := filepath.Glob(filepath.Join("services", "*", "openapi.yaml"))
	if err != nil {
		return fmt.Errorf("glob specs: %w", err)
	}
	for _, path := range specs {
		svc := filepath.Base(filepath.Dir(path))
		auds, err := effectiveAudiences(path)
		if err != nil {
			return err
		}
		exposed, err := edgeExposed(svc)
		if err != nil {
			return err
		}
		r.Add(check(svc, auds, exposed)...)
	}
	r.Okf("%d API specs: x-audience matches edge exposure", len(specs))
	return nil
}

func check(svc string, auds []string, exposed bool) []string {
	problems := make([]string, 0, len(auds))
	hasEdge := false
	for _, a := range auds {
		switch a {
		case audienceCluster:
		case audienceInternal, audiencePublic:
			hasEdge = true
		default:
			msg := fmt.Sprintf("%s: unknown x-audience %q (expected cluster, internal, or public)", svc, a)
			problems = append(problems, msg)
		}
	}
	switch {
	case hasEdge && !exposed:
		msg := svc + ": has edge operations (x-audience internal/public) but no /api route (ingress.resources empty)"
		problems = append(problems, msg)
	case !hasEdge && exposed:
		msg := svc + ": edge-exposed (ingress.resources set) but every operation is x-audience: cluster (east-west)"
		problems = append(problems, msg)
	}
	return problems
}

// effectiveAudiences resolves each operation's audience: its own x-audience, else the
// service default (info.x-audience), else the fail-closed `cluster`.
func effectiveAudiences(path string) ([]string, error) {
	s, err := repo.ReadYAML[struct {
		Info struct {
			XAudience string `yaml:"x-audience"`
		} `yaml:"info"`
		Paths map[string]map[string]yaml.Node `yaml:"paths"`
	}](path)
	if err != nil {
		return nil, err
	}
	def := s.Info.XAudience
	if def == "" {
		def = audienceCluster
	}
	var auds []string
	for _, methods := range s.Paths {
		for method, node := range methods {
			if !httpMethods[method] {
				continue
			}
			var op struct {
				XAudience string `yaml:"x-audience"`
			}
			err := node.Decode(&op)
			if err != nil {
				return nil, fmt.Errorf("parse %s operation %q: %w", path, method, err)
			}
			a := op.XAudience
			if a == "" {
				a = def
			}
			auds = append(auds, a)
		}
	}
	return auds, nil
}

// edgeExposed reports whether the service has an /api route, read from its canonical
// dev gitops values. A service with no such file (e.g. the _template scaffold) is
// treated as not deployed, hence not edge-exposed.
func edgeExposed(svc string) (bool, error) {
	path := filepath.Join("infra", "gitops", "services", "dev", "values", svc+".yaml")
	v, err := repo.ReadYAML[struct {
		Ingress struct {
			Enabled   *bool    `yaml:"enabled"`
			Resources []string `yaml:"resources"`
		} `yaml:"ingress"`
	}](path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	enabled := v.Ingress.Enabled == nil || *v.Ingress.Enabled // chart default is true
	return enabled && len(v.Ingress.Resources) > 0, nil
}
