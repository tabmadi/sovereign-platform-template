// Command lint-authz-dual-write checks that authorization tuples are written from a workflow's activities, never from
// a request handler, per ADR-0304 and ADR-0302.
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"slices"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
)

// granterMethods are the mutating half of the authz seam in libs/go/authz.
var granterMethods = []string{"Grant", "Revoke"}

// activitiesDir is the one package where a tuple write belongs. Temporal can retry an activity until it succeeds,
// so the pair becomes eventually consistent and is not sometimes wrong.
const activitiesDir = "internal/activities"

// exempt lists known violations with the reason each one stays. It is empty, and it stays so that the next violation
// has a place to be recorded.
var exempt = map[string]string{}

type finding struct {
	file string
	line int
	call string
}

func main() {
	lint.Main("an authz tuple is written outside an activity", run)
}

func run(r *lint.Report) error {
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
		return fmt.Errorf("walk services: %w", err)
	}

	for _, f := range found {
		_, exempted := exempt[f.file]
		if exempted {
			continue
		}
		r.Addf("%s:%d: %s writes an authz tuple outside an activity", f.file, f.line, f.call)
	}

	r.Hintf("There is no transaction across Postgres and OpenFGA, per ADR-0304. The row\n" +
		"  write and the tuple write belong in one workflow, as two activities it can\n" +
		"  retry. A handler that does both can leave a resource that nobody can read.")
	if len(exempt) > 0 {
		r.Okf("authz tuples are written from activities, %d exemption(s) recorded", len(exempt))
	} else {
		r.Okf("authz tuples are written from activities, with no exemptions")
	}
	return nil
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
			// The receiver's type is not resolved. A false positive is a call named Grant on something else, and that name
			// deserves a question too.
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
