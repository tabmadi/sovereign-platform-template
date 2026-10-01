// Command lint-money enforces the monetary-value rule, per ADR-0100 and ADR-0300.
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

// moneyWords is the vocabulary: a name containing one of these as a whole word is monetary.
const (
	wordAmount = "amount"
	wordPrice  = "price"
)

var moneyWords = []string{
	wordAmount,
	"balance",
	"charge",
	"cost",
	"discount",
	"fee",
	wordPrice,
	"refund",
	"subtotal",
	"total",
}

// countWords end an identifier that counts and does not hold a value. `total_count` and `amount_of_rows` are not money.
var countWords = []string{
	"bytes",
	"count",
	"items",
	"length",
	"quantity",
	"qty",
	"rows",
	"seconds",
	"size",
}

// moneyComponent is the shared OpenAPI schema that every monetary property must point at, in
// tools/codegen/shared-components.yaml.
const moneyComponent = "Money"

// A finding is one violation, rendered as `file:line: message`.
type finding struct {
	file string
	line int
	msg  string
}

func main() {
	lint.Main("a monetary value is not the shared money type", run)
}

func run(r *lint.Report) error {
	specs, err := repo.Glob(filepath.Join("services", "*", "openapi.yaml"))
	if err != nil {
		return err
	}
	var found []finding
	for _, spec := range specs {
		hits, err := checkSpec(spec)
		if err != nil {
			return err
		}
		found = append(found, hits...)
	}
	goHits, err := checkGo()
	if err != nil {
		return err
	}
	found = append(found, goHits...)

	tsHits, err := checkTypeScript()
	if err != nil {
		return err
	}
	found = append(found, tsHits...)

	for _, f := range found {
		r.Addf("%s:%d: %s", f.file, f.line, f.msg)
	}
	r.Hintf("A monetary amount is the shared money type, per ADR-0100:\n" +
		"  numeric in the column, " + moneyComponent + " in the spec, a decimal string on the wire.")
	r.Okf("every monetary value is the shared money type")
	return nil
}

// checkSpec walks every schema's `properties` mapping and reports a monetary property that is not the shared component.
func checkSpec(path string) ([]finding, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var root yaml.Node
	err = yaml.Unmarshal(data, &root)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}

	var found []finding
	walkYAML(
		&root,
		func(key string, value *yaml.Node) {
			if key != "properties" || value.Kind != yaml.MappingNode {
				return
			}
			// The Money component's own members. It defines the shape, so its `amount` is a string by design and not a
			// violation.
			if isMoneyDefinition(value) {
				return
			}
			for i := 0; i+1 < len(value.Content); i += 2 {
				name, schema := value.Content[i], value.Content[i+1]
				if !isMoneyName(name.Value) {
					continue
				}
				var s struct {
					Ref  string `yaml:"$ref"`
					Type string `yaml:"type"`
				}
				_ = schema.Decode(&s)
				if filepath.Base(s.Ref) == moneyComponent {
					continue
				}
				// A monetary property with no type at all is a composed schema such as allOf or oneOf, or a free-form object.
				// This cannot read either as a money shape. The report is right: the author has to say which one it is.
				msg := fmt.Sprintf(
					"%q is a monetary property but is %s, not $ref: %s",
					name.Value,
					describeType(s.Type),
					moneyComponent,
				)
				found = append(found, finding{file: path, line: name.Line, msg: msg})
			}
		},
	)
	return found, nil
}

// isMoneyDefinition reports whether a `properties` mapping is the Money component itself.
// It is recognised by its members, not by the schema's name: a spec can use another name, and amount with currency
// makes it Money.
func isMoneyDefinition(properties *yaml.Node) bool {
	var amount, currency bool
	for i := 0; i < len(properties.Content); i += 2 {
		switch properties.Content[i].Value {
		case wordAmount:
			amount = true
		case "currency":
			currency = true
		}
	}
	return amount && currency
}

func describeType(t string) string {
	if t == "" {
		return "an unrecognised shape"
	}
	return "type: " + t
}

// walkYAML calls fn for every key and value pair in every mapping in the document.
func walkYAML(n *yaml.Node, fn func(key string, value *yaml.Node)) {
	if n == nil {
		return
	}
	if n.Kind == yaml.MappingNode {
		for i := 0; i+1 < len(n.Content); i += 2 {
			fn(n.Content[i].Value, n.Content[i+1])
		}
	}
	for _, c := range n.Content {
		walkYAML(c, fn)
	}
}

// goSkip are trees that this does not cover: the money package implements the type, generated code mirrors a checked
// source,
// and vendored code is not ours.
var goSkip = []string{
	"libs/go/money",
	// This file names what it forbids, in the pattern and in the reason for the pattern.
	"tools/lint-money",
	"libs/go/sdks",
	"internal/store",
	"node_modules",
	"vendor",
	".next",
}

// floatTypes are the two types the rule names outright.
var floatTypes = map[string]bool{"float32": true, "float64": true}

// centsPattern matches an identifier that names minor units, the representation that the shared type replaced.
var centsPattern = regexp.MustCompile(`(?i)cents`)

func checkGo() ([]finding, error) {
	var found []finding
	fset := token.NewFileSet()

	paths, err := sourceFiles([]string{".go"}, goSkip)
	if err != nil {
		return nil, err
	}
	for _, path := range paths {
		file, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", path, err)
		}
		found = append(found, checkGoFile(fset, path, file)...)
	}
	return found, nil
}

// checkGoFile reports the two Go-side shapes: a money value typed as a float, and an identifier that names minor units.
func checkGoFile(fset *token.FileSet, path string, file *ast.File) []finding {
	var found []finding

	report := func(pos token.Pos, msg string) {
		found = append(found, finding{file: path, line: fset.Position(pos).Line, msg: msg})
	}

	ast.Inspect(
		file,
		func(n ast.Node) bool {
			switch v := n.(type) {
			case *ast.Field:
				for _, name := range v.Names {
					checkGoName(name.Name, v.Type, name.Pos(), report)
				}
			case *ast.ValueSpec:
				for _, name := range v.Names {
					checkGoName(name.Name, v.Type, name.Pos(), report)
				}
			}
			return true
		},
	)
	return found
}

func checkGoName(name string, typ ast.Expr, pos token.Pos, report func(token.Pos, string)) {
	if centsPattern.MatchString(name) {
		report(pos, fmt.Sprintf("%q names minor units. A monetary value is money.Amount", name))
		return
	}
	if !isMoneyName(name) {
		return
	}
	ident, ok := typ.(*ast.Ident)
	if ok && floatTypes[ident.Name] {
		report(pos, fmt.Sprintf("%q is monetary and %s. Use money.Amount", name, ident.Name))
	}
}

// tsSkip matches goSkip: generated clients repeat a spec that is checked at its source, and build output is not source.
var tsSkip = []string{
	// The counterpart of the money package exclusion: libs/ts/money implements the type, so its own members are the
	// shape and not a violation.
	"libs/ts/money",
	"libs/ts/sdks",
	"node_modules",
	".next",
	"dist",
	"test-results",
	"playwright-report",
}

// tsMoneyField matches an object-type member or literal whose name is monetary and whose value is a number:
// `price: number`, `total_cents: 1299`.
var tsMoneyField = regexp.MustCompile(`(?i)\b([a-z_][a-z0-9_]*)\s*\??\s*:\s*(number\b|-?[0-9])`)

func checkTypeScript() ([]finding, error) {
	var found []finding

	paths, err := sourceFiles([]string{".ts", ".tsx", ".js"}, tsSkip)
	if err != nil {
		return nil, err
	}
	for _, path := range paths {
		data, err := repo.Read(path)
		if err != nil {
			return nil, err
		}
		found = append(found, checkTypeScriptFile(path, string(data))...)
	}
	return found, nil
}

// checkTypeScriptFile is textual, where the Go side is syntactic. TypeScript has no standard-library parser.
// The shape it looks for, a name and a number on the same line, survives the loss of structure.
func checkTypeScriptFile(path, source string) []finding {
	var found []finding

	for i, line := range strings.Split(source, "\n") {
		// A comment is prose about money, not money. The check is textual here, so the exclusion is textual too.
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") || strings.HasPrefix(trimmed, "*") {
			continue
		}
		for _, m := range tsMoneyField.FindAllStringSubmatch(line, -1) {
			name := m[1]
			if !isMoneyName(name) && !centsPattern.MatchString(name) {
				continue
			}
			hit := finding{
				file: path,
				line: i + 1,
				msg:  fmt.Sprintf("%q is a monetary value as a number. Use Money from @libs/money", name),
			}
			found = append(found, hit)
		}
	}
	return found
}

// sourceFiles lists the committed files with one of these extensions, outside the skipped trees.
// It uses repo.Files, not a walk: a gitignored build output is not source, and a gate must not depend on stray files
// in the tree.
func sourceFiles(exts, skip []string) ([]string, error) {
	files, err := repo.Files()
	if err != nil {
		return nil, err
	}
	var out []string
	for _, path := range files {
		if !slices.Contains(exts, filepath.Ext(path)) || skipped(path, skip) {
			continue
		}
		out = append(out, path)
	}
	return out, nil
}

// isMoneyName reports whether an identifier names a monetary value. The match is on words, so `total_amount` and
// `unitPrice` match,
// and `totals` and `pricing` do not. A substring match would make `pricing_enabled` a monetary field.
func isMoneyName(name string) bool {
	words := splitIdentifier(name)
	if len(words) == 0 {
		return false
	}
	// The last word decides what the identifier is, and the earlier words qualify it.
	// `total_count` is a count of something, and `order_total` is a total.
	if slices.Contains(countWords, words[len(words)-1]) {
		return false
	}
	for _, word := range words {
		if slices.Contains(moneyWords, word) {
			return true
		}
	}
	return false
}

// splitIdentifier breaks snake_case, camelCase, and PascalCase into lowercase words.
func splitIdentifier(name string) []string {
	var words []string
	var current strings.Builder
	flush := func() {
		if current.Len() > 0 {
			words = append(words, strings.ToLower(current.String()))
			current.Reset()
		}
	}
	for _, r := range name {
		switch {
		case r == '_' || r == '-' || r == '.':
			flush()
		case r >= 'A' && r <= 'Z':
			flush()
			_, _ = current.WriteRune(r)
		default:
			_, _ = current.WriteRune(r)
		}
	}
	flush()
	return words
}

func skipped(path string, prefixes []string) bool {
	clean := filepath.ToSlash(path)
	for _, p := range prefixes {
		if strings.Contains(clean, p) {
			return true
		}
	}
	return false
}
