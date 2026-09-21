// Command lint-strip-headers is the anti-spoofing gate: a forwardAuth IngressRoute must apply strip-identity-headers
// before it (ADR-0305).
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"slices"

	"gopkg.in/yaml.v3"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
)

type ingressRoute struct {
	Kind     string `yaml:"kind"`
	Metadata struct {
		Name string `yaml:"name"`
	} `yaml:"metadata"`
	Spec struct {
		Routes []struct {
			Middlewares []struct {
				Name string `yaml:"name"`
			} `yaml:"middlewares"`
		} `yaml:"routes"`
	} `yaml:"spec"`
}

func main() {
	lint.Main("anti-spoofing gate failed", run)
}

func run(r *lint.Report) error {
	dec := yaml.NewDecoder(os.Stdin)
	checked := 0
	for {
		var ir ingressRoute
		err := dec.Decode(&ir)
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("parse yaml: %w", err)
		}
		if ir.Kind != "IngressRoute" {
			continue
		}
		for _, route := range ir.Spec.Routes {
			var mws []string
			for _, m := range route.Middlewares {
				mws = append(mws, m.Name)
			}
			fwd := slices.Index(mws, "oathkeeper-forward-auth")
			if fwd < 0 {
				continue
			}
			checked++
			strip := slices.Index(mws, "strip-identity-headers")
			switch {
			case strip < 0:
				r.Addf("%s: forward-auth route without strip-identity-headers", ir.Metadata.Name)
			case strip > fwd:
				r.Addf("%s: strip-identity-headers must come BEFORE forward-auth", ir.Metadata.Name)
			}
		}
	}
	r.Okf("all %d forward-auth routes strip identity headers first", checked)
	return nil
}
