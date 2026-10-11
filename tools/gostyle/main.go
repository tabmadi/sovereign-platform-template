// Command gostyle runs the layout-based style analyzers that golangci-lint cannot express.
package main

import (
	"go/ast"
	"go/token"
	"strings"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/multichecker"
)

// callArgsAnalyzer checks that a call's arguments are all on one line or one on each line, never a mix.
// gofmt keeps the line breaks the source had, so no upstream tool catches the mixed layout.
var callArgsAnalyzer = &analysis.Analyzer{
	Name: "callargs",
	Doc:  "a call's arguments must be either all on one line or fully exploded one per line",
	Run:  runCallArgs,
}

func main() {
	multichecker.Main(callArgsAnalyzer)
}

func runCallArgs(pass *analysis.Pass) (any, error) {
	for _, file := range pass.Files {
		if isGenerated(file) {
			continue
		}

		ast.Inspect(file, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok || len(call.Args) == 0 {
				return true
			}

			if !isSingleLine(call, pass) && !isFullyExploded(call, pass) {
				pass.Report(
					analysis.Diagnostic{
						Pos:     call.Lparen,
						Message: "call arguments are partially broken across lines; use either a single line or one argument per line",
						SuggestedFixes: []analysis.SuggestedFix{
							{Message: "put one argument on each line", TextEdits: explodeEdits(call, pass)},
						},
					},
				)
			}

			return true
		})
	}
	return nil, nil //nolint:nilnil // Run's (result, error) signature; nil result is normal
}

// explodeEdits breaks the line before each argument that shares a line with the token before it, and after the last
// argument. gofmt then sets the indentation.
func explodeEdits(call *ast.CallExpr, pass *analysis.Pass) []analysis.TextEdit {
	var edits []analysis.TextEdit
	prevEnd := call.Lparen
	for _, arg := range call.Args {
		if pass.Fset.Position(prevEnd).Line == pass.Fset.Position(arg.Pos()).Line {
			edits = append(edits, analysis.TextEdit{Pos: arg.Pos(), End: arg.Pos(), NewText: []byte("\n")})
		}
		prevEnd = arg.End()
	}

	lastEnd := call.Args[len(call.Args)-1].End()
	if call.Ellipsis.IsValid() {
		lastEnd = call.Ellipsis + token.Pos(len("..."))
	}
	if pass.Fset.Position(lastEnd).Line == pass.Fset.Position(call.Rparen).Line {
		edits = append(edits, analysis.TextEdit{Pos: lastEnd, End: lastEnd, NewText: []byte(",\n")})
	}
	return edits
}

// isGenerated reports whether the file has the standard `// Code generated ... DO NOT EDIT.` marker.
// golangci-lint uses the same convention for its own `generated: lax` exclusion.
func isGenerated(file *ast.File) bool {
	for _, c := range file.Comments {
		for _, line := range c.List {
			if strings.Contains(line.Text, "Code generated") && strings.Contains(line.Text, "DO NOT EDIT") {
				return true
			}
		}
	}
	return false
}

// isSingleLine reports whether the call's parens and every argument are on the same source line.
func isSingleLine(call *ast.CallExpr, pass *analysis.Pass) bool {
	lparenLine := pass.Fset.Position(call.Lparen).Line
	rparenLine := pass.Fset.Position(call.Rparen).Line
	return lparenLine == rparenLine
}

// isFullyExploded reports whether the call has a newline right after the opening paren and right before the closing
// one.
// Each argument must also start on its own line.
func isFullyExploded(call *ast.CallExpr, pass *analysis.Pass) bool {
	lparenLine := pass.Fset.Position(call.Lparen).Line
	firstArgLine := pass.Fset.Position(call.Args[0].Pos()).Line
	if lparenLine == firstArgLine {
		return false
	}

	rparenLine := pass.Fset.Position(call.Rparen).Line
	lastArgEndLine := pass.Fset.Position(call.Args[len(call.Args)-1].End()).Line
	if rparenLine == lastArgEndLine {
		return false
	}

	for i := 1; i < len(call.Args); i++ {
		prevEndLine := pass.Fset.Position(call.Args[i-1].End()).Line
		curLine := pass.Fset.Position(call.Args[i].Pos()).Line
		if prevEndLine == curLine {
			return false
		}
	}

	return true
}
