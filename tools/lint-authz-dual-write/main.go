// Command lint-authz-dual-write checks that authorization tuples are written from a workflow's activities, never from
// a request handler (ADR-0304, ADR-0302).
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
)

// granterMethods are the mutating half of the authz seam (libs/go/authz).
var granterMethods = []string{"Grant", "Revoke"}

// activitiesDir is the one package a tuple write belongs in: an activity is what
// Temporal can retry until it succeeds, which is what makes the pair eventually
// consistent rather than occasionally wrong.
const activitiesDir = "internal/activities"

// exempt lists known violations with the reason each survives. It is empty and stays so the next violation has
// somewhere to be written down.
var exempt = map[string]string{}

type finding struct {
	file string
	line int
	call string
}

func main() {
	var found []finding

	err := filepath.WalkDir(
		"services",
		func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() || filepath.Ext(path) != ".go" || strings.HasSuffix(path, "_test.go") {
				return nil
			}
			clean := filepath.ToSlash(path)
			// The scaffold is built under its own tag and deploys nowhere.
			if strings.HasPrefix(clean, "services/_") {
				return nil
			}
			if strings.Contains(clean, activitiesDir) {
				return nil
			}
			hits, parseErr := grantCalls(clean)
			if parseErr != nil {
				return parseErr
			}
			found = append(found, hits...)
			return nil
		},
	)
	if err != nil {
		failf(err)
	}

	var problems []finding
	for _, f := range found {
		_, exempted := exempt[f.file]
		if exempted {
			continue
		}
		problems = append(problems, f)
	}

	if len(problems) > 0 {
		sort.Slice(problems, func(i, j int) bool { return problems[i].line < problems[j].line })
		for _, p := range problems {
			_, _ = fmt.Fprintf(os.Stderr, "✗ %s:%d: %s writes an authz tuple outside an activity\n", p.file, p.line, p.call)
		}
		_, _ = fmt.Fprintf(os.Stderr, "\n  There is no transaction across Postgres and OpenFGA (ADR-0304). The row\n")
		_, _ = fmt.Fprintf(os.Stderr, "  write and the tuple write belong in one workflow, as two activities it can\n")
		_, _ = fmt.Fprintf(os.Stderr, "  retry — a handler that does both leaves a resource nobody can read.\n")
		os.Exit(1)
	}

	if len(exempt) > 0 {
		_, _ = fmt.Fprintf(os.Stdout, "✓ authz tuples are written from activities (%d exemption(s) recorded)\n", len(exempt))
		return
	}
	_, _ = fmt.Fprintf(os.Stdout, "✓ authz tuples are written from activities, with no exemptions\n")
}

// grantCalls returns every granter mutation called in a file.
func grantCalls(path string) ([]finding, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	var out []finding
	ast.Inspect(
		file,
		func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			sel, ok := call.Fun.(*ast.SelectorExpr)
			if !ok || !slices.Contains(granterMethods, sel.Sel.Name) {
				return true
			}
			// The receiver's type is not resolved: a false positive is a call named Grant on something else, which is a name
			// worth questioning anyway.
			hit := finding{
				file: path,
				line: fset.Position(call.Pos()).Line,
				call: render(sel),
			}
			out = append(out, hit)
			return true
		},
	)
	return out, nil
}

func render(sel *ast.SelectorExpr) string {
	ident, ok := sel.X.(*ast.Ident)
	if ok {
		return ident.Name + "." + sel.Sel.Name
	}
	return sel.Sel.Name
}

func failf(err error) {
	_, _ = fmt.Fprintf(os.Stderr, "✗ %v\n", err)
	os.Exit(1)
}
