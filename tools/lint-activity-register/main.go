// Command lint-activity-register checks that every activity a workflow names is registered on the worker serving its
// task queue (ADR-0302).
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// executeActivity names the workflow-side calls that take an activity name. Both
// take it as the second argument.
var executeActivity = map[string]bool{
	"ExecuteActivity":      true,
	"ExecuteLocalActivity": true,
}

func main() {
	services, err := filepath.Glob(filepath.Join("services", "*"))
	if err != nil {
		failf("glob services: %v", err)
	}
	sort.Strings(services)

	var problems []string
	checked := 0

	for _, svc := range services {
		// `_template` is behind a `//go:build _template` tag with commented example registrations; lint:template-build
		// checks it under that tag.
		if strings.HasPrefix(filepath.Base(svc), "_") {
			continue
		}
		workflowDir := filepath.Join(svc, "internal", "workflows")
		workerMain := filepath.Join(svc, "cmd", "worker", "main.go")
		if !exists(workflowDir) || !exists(workerMain) {
			continue // not a Temporal service
		}
		checked++

		called, err := calledActivities(workflowDir)
		if err != nil {
			failf("%v", err)
		}
		registered, err := registeredActivities(workerMain)
		if err != nil {
			failf("%v", err)
		}

		for _, name := range sortedKeys(called) {
			if registered[name] {
				continue
			}
			problem := fmt.Sprintf(
				"%s: %q is executed by %s but never registered in %s",
				svc,
				name,
				called[name],
				workerMain,
			)
			problems = append(problems, problem)
		}
	}

	if len(problems) > 0 {
		for _, p := range problems {
			_, _ = fmt.Fprintf(os.Stderr, "✗ %s\n", p)
		}
		_, _ = fmt.Fprintf(os.Stderr, "\n  A workflow names its activities as strings, so the compiler cannot\n")
		_, _ = fmt.Fprintf(os.Stderr, "  see this. The worker answers \"unable to find activityType\" at run time.\n")
		os.Exit(1)
	}

	_, _ = fmt.Fprintf(os.Stdout, "✓ %d workers register every activity their workflows call\n", checked)
}

// calledActivities maps an activity name to the file:line that executes it.
func calledActivities(dir string) (map[string]string, error) {
	out := map[string]string{}
	fset := token.NewFileSet()

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", dir, err)
	}
	for _, entry := range entries {
		name := entry.Name()
		// A _test.go file registers stubs in the Temporal test environment, which is
		// what hides this defect rather than what reveals it.
		if entry.IsDir() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		path := filepath.Join(dir, name)
		file, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", path, err)
		}
		ast.Inspect(
			file,
			func(n ast.Node) bool {
				call, ok := n.(*ast.CallExpr)
				if !ok || len(call.Args) < 2 {
					return true
				}
				sel, ok := call.Fun.(*ast.SelectorExpr)
				if !ok || !executeActivity[sel.Sel.Name] {
					return true
				}
				activity, ok := stringLiteral(call.Args[1])
				if !ok {
					// A non-literal name is a value this cannot follow. It is also not
					// what any workflow here does, so it is left alone rather than
					// guessed at.
					return true
				}
				_, seen := out[activity]
				if !seen {
					out[activity] = fmt.Sprintf("%s:%d", path, fset.Position(call.Pos()).Line)
				}
				return true
			},
		)
	}
	return out, nil
}

// registeredActivities reads the worker's registrations: the method name for a
// bare RegisterActivity, and the explicit Name for RegisterActivityWithOptions.
func registeredActivities(path string) (map[string]bool, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	out := map[string]bool{}
	ast.Inspect(
		file,
		func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok || len(call.Args) == 0 {
				return true
			}
			sel, ok := call.Fun.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			switch sel.Sel.Name {
			case "RegisterActivity":
				// The registered name is the FUNCTION's name, which is what Temporal
				// derives it from.
				arg, ok := call.Args[0].(*ast.SelectorExpr)
				if ok {
					out[arg.Sel.Name] = true
				}
			case "RegisterActivityWithOptions":
				for _, name := range optionNames(call.Args) {
					out[name] = true
				}
			}
			return true
		},
	)
	return out, nil
}

// optionNames pulls `Name: "…"` out of an activity.RegisterOptions literal.
func optionNames(args []ast.Expr) []string {
	var out []string
	for _, arg := range args {
		lit, ok := arg.(*ast.CompositeLit)
		if !ok {
			continue
		}
		for _, elt := range lit.Elts {
			kv, ok := elt.(*ast.KeyValueExpr)
			if !ok {
				continue
			}
			key, ok := kv.Key.(*ast.Ident)
			if !ok || key.Name != "Name" {
				continue
			}
			value, ok := stringLiteral(kv.Value)
			if ok {
				out = append(out, value)
			}
		}
	}
	return out
}

func stringLiteral(e ast.Expr) (string, bool) {
	lit, ok := e.(*ast.BasicLit)
	if !ok || lit.Kind != token.STRING {
		return "", false
	}
	value, err := strconv.Unquote(lit.Value)
	if err != nil {
		return "", false
	}
	return value, true
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func sortedKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func failf(format string, args ...any) {
	_, _ = fmt.Fprintf(os.Stderr, "✗ "+format+"\n", args...)
	os.Exit(1)
}
