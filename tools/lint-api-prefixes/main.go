// Command lint-api-prefixes enforces resource-prefix ownership across the flat /api namespace (ADR-0303, ADR-0306).
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

func main() {
	lint.Main("resource-prefix ownership (ADR-0303, ADR-0306)", run)
}

func run(r *lint.Report) error {
	specs, err := repo.Glob(filepath.Join("services", "*", "openapi.yaml"))
	if err != nil {
		return err
	}

	// owner maps a resource to every service declaring it, so a collision reports
	// all claimants rather than just the second one.
	owner := map[string][]string{}

	for _, spec := range specs {
		svc := filepath.Base(filepath.Dir(spec))

		routed, err := routedResources(svc)
		if err != nil {
			return fmt.Errorf("%s: %w", svc, err)
		}
		if len(routed) == 0 {
			continue // east-west service: it claims nothing in the /api namespace
		}

		served, err := servedPrefixes(spec)
		if err != nil {
			return fmt.Errorf("%s: %w", spec, err)
		}

		for _, resource := range routed {
			owner[resource] = append(owner[resource], svc)
			if !served[resource] {
				r.Addf("%s: routes %q at the edge but its spec has no /%s path", svc, resource, resource)
			}
		}
		for prefix := range served {
			if slices.Contains(routed, prefix) {
				continue
			}
			r.Addf("%s: spec serves /%s but the edge route table does not claim %q", svc, prefix, prefix)
		}
	}

	for _, resource := range sortedKeys(owner) {
		claimants := owner[resource]
		if len(claimants) < 2 {
			continue
		}
		const form = "resource %q is claimed by %s — one flat /api namespace admits one owner"
		r.Addf(form, resource, strings.Join(claimants, ", "))
	}

	r.Okf("%d resource prefixes, each owned by one service", len(owner))
	return nil
}

// routedResources reads the service's edge route table from its canonical dev
// values. A service with no values file (the _template scaffold) is not deployed
// and routes nothing.
func routedResources(svc string) ([]string, error) {
	path := filepath.Join("infra", "gitops", "services", "dev", "values", svc+".yaml")
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var v struct {
		Ingress struct {
			Enabled   *bool    `yaml:"enabled"`
			Resources []string `yaml:"resources"`
		} `yaml:"ingress"`
	}
	err = yaml.Unmarshal(data, &v)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if v.Ingress.Enabled != nil && !*v.Ingress.Enabled { // chart default is true
		return nil, nil
	}
	return v.Ingress.Resources, nil
}

// httpMethods are the OpenAPI operation keys under a path item; other keys
// (parameters, servers, summary) are not operations and carry no audience.
var httpMethods = map[string]bool{
	"get": true, "put": true, "post": true, "delete": true,
	"patch": true, "options": true, "head": true, "trace": true,
}

// servedPrefixes is the set of top-level segments the spec exposes at the edge. A path resolving entirely to
// `x-audience: cluster` is east-west — the Kratos identity webhook into orgs — and is deliberately unrouted.
func servedPrefixes(spec string) (map[string]bool, error) {
	data, err := os.ReadFile(spec)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", spec, err)
	}
	var s struct {
		Info struct {
			XAudience string `yaml:"x-audience"`
		} `yaml:"info"`
		Paths map[string]map[string]yaml.Node `yaml:"paths"`
	}
	err = yaml.Unmarshal(data, &s)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", spec, err)
	}
	def := s.Info.XAudience
	if def == "" {
		def = "cluster"
	}

	out := map[string]bool{}
	for p, methods := range s.Paths {
		seg := strings.Split(strings.TrimPrefix(p, "/"), "/")[0]
		if seg == "" {
			continue
		}
		for method, node := range methods {
			if !httpMethods[method] {
				continue
			}
			var op struct {
				XAudience string `yaml:"x-audience"`
			}
			err = node.Decode(&op)
			if err != nil {
				return nil, fmt.Errorf("parse %s %s %s: %w", spec, method, p, err)
			}
			aud := op.XAudience
			if aud == "" {
				aud = def
			}
			if aud != "cluster" {
				out[seg] = true
			}
		}
	}
	return out, nil
}

func sortedKeys(m map[string][]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
