// Command lint-fixtures checks that every frontend fixture is typed against a generated SDK, per ADR-0701.
package main

import (
	"fmt"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

const (
	fixtureGlob = "apps/frontend/src/fixtures/*.ts"
	seamDir     = "apps/frontend/src/lib/data/"
	guardCall   = "designOnly("
	sdkGlob     = "libs/ts/sdks/*/index.d.ts"
	sdkPrefix   = "@sdks/"
	satisfies   = " satisfies "
)

var (
	// `// no-spec: GET /members` names the endpoint that no spec has yet.
	markerRe = regexp.MustCompile(`(?m)^//\s*no-spec:(.*)$`) // lint:comments-allow
	// `// external: kratos GET /sessions/whoami` names an endpoint that no OpenAPI spec will ever describe.
	externalRe = regexp.MustCompile( // lint:comments-allow
		`(?m)^//\s*external:\s*\S+\s+(?:GET|PUT|POST|DELETE|PATCH)\s+/\S*\s*$`,
	)
	markerBodyRe = regexp.MustCompile(`^\s*(GET|PUT|POST|DELETE|PATCH)\s+(/\S*)\s*$`)
	importRe     = regexp.MustCompile(
		`^import\s+(?:type\s+)?(?:\{([^}]*)\}|\*\s+as\s+([\w$]+)|([\w$]+))\s+from\s+"([^"]+)"`,
	)
	constRe      = regexp.MustCompile(`^export\s+const\s+([\w$]+)`)
	aliasRe      = regexp.MustCompile(`^(?:export\s+)?type\s+([\w$]+)\s*=\s*([^;]*);?$`)
	identRe      = regexp.MustCompile(`[A-Za-z_$][\w$]*`)
	pathLineRe   = regexp.MustCompile(`^    "(/[^"]*)": \{$`)
	methodLineRe = regexp.MustCompile(`^        (get|put|post|delete|patch): `)
	paramRe      = regexp.MustCompile(`\{[^}]*\}`)
)

// The TypeScript words that a `satisfies` type may use around an SDK type.
var typeWords = []string{
	"Array", "ReadonlyArray", "Readonly", "Partial", "Required", "Pick", "Omit", "Record", "NonNullable",
	"Exclude", "Extract", "string", "number", "boolean", "null", "undefined", "never", "unknown", "readonly", "keyof",
}

func main() {
	lint.Main("a fixture is not typed against a generated SDK, per ADR-0701", run)
}

func run(r *lint.Report) error {
	fixtures, err := repo.Glob(fixtureGlob)
	if err != nil {
		return err
	}
	if len(fixtures) == 0 {
		return fmt.Errorf("%s matches no file, and the check needs at least one", fixtureGlob)
	}
	endpoints, err := loadEndpoints()
	if err != nil {
		return err
	}
	pending := map[string][]string{}
	for _, path := range fixtures {
		data, err := repo.Read(path)
		if err != nil {
			return err
		}
		findings, markers := checkFile(path, string(data), endpoints)
		r.Add(findings...)
		if len(markers) > 0 {
			pending[strings.TrimSuffix(filepath.Base(path), ".ts")] = markers
		}
	}
	seams, err := loadSeams()
	if err != nil {
		return err
	}
	r.Add(checkGuards(pending, seams)...)
	r.Hintf("End each export with `satisfies <T>`, and import `T` from `@sdks/*`. " +
		"A fixture for an endpoint that no spec has yet carries `// no-spec: <METHOD> <path>`, " +
		"and every seam that reads it calls `designOnly()`.")
	if len(pending) == 0 {
		r.Okf("%d fixture files are typed against a generated SDK. No page waits for an endpoint", len(fixtures))
		return nil
	}
	r.Okf("%d fixture files are typed. These pages are design-only and wait for an endpoint:\n%s",
		len(fixtures), pendingList(pending))
	return nil
}

// loadSeams reads every seam under seamDir, without its tests.
func loadSeams() (map[string]string, error) {
	files, err := repo.Files()
	if err != nil {
		return nil, err
	}
	seams := map[string]string{}
	for _, f := range files {
		if !strings.HasPrefix(f, seamDir) || !strings.HasSuffix(f, ".ts") || strings.HasSuffix(f, ".test.ts") {
			continue
		}
		data, err := repo.Read(f)
		if err != nil {
			return nil, err
		}
		seams[f] = string(data)
	}
	return seams, nil
}

// checkGuards fails each seam that reads a fixture with a no-spec marker and does not call designOnly. Outside
// fixture mode such a page has no endpoint to call, so it must not exist there.
func checkGuards(pending map[string][]string, seams map[string]string) []string {
	var findings []string
	for fixture, markers := range pending {
		for path, src := range seams {
			if !strings.Contains(src, `"@/fixtures/`+fixture+`"`) || strings.Contains(src, guardCall) {
				continue
			}
			const form = "%s: reads @/fixtures/%s, which waits for %s. Call `designOnly()` before the real call"
			findings = append(findings, fmt.Sprintf(form, path, fixture, strings.Join(markers, ", ")))
		}
	}
	return findings
}

func pendingList(pending map[string][]string) string {
	lines := make([]string, 0, len(pending))
	for fixture, markers := range pending {
		lines = append(lines, fmt.Sprintf("  @/fixtures/%s waits for %s", fixture, strings.Join(markers, ", ")))
	}
	slices.Sort(lines)
	return strings.Join(lines, "\n")
}

// loadEndpoints maps `METHOD /path` to the SDK that serves it. Path parameters are blanked, so their names do not
// matter.
func loadEndpoints() (map[string]string, error) {
	files, err := repo.Glob(sdkGlob)
	if err != nil {
		return nil, err
	}
	endpoints := map[string]string{}
	for _, file := range files {
		sdk := filepath.Base(filepath.Dir(file))
		// `_template` is the scaffold for a new SDK, not an API.
		if strings.HasPrefix(sdk, "_") {
			continue
		}
		data, err := repo.Read(file)
		if err != nil {
			return nil, err
		}
		for key := range parseEndpoints(string(data)) {
			endpoints[key] = sdkPrefix + sdk
		}
	}
	return endpoints, nil
}

// parseEndpoints reads the `paths` interface that openapi-typescript writes. An operation that the path does not
// have is written as `get?: never`, so only a line without `?` counts.
func parseEndpoints(dts string) map[string]bool {
	endpoints := map[string]bool{}
	path := ""
	for line := range strings.SplitSeq(dts, "\n") {
		m := pathLineRe.FindStringSubmatch(line)
		if m != nil {
			path = m[1]
			continue
		}
		if line == "    };" || strings.HasPrefix(line, "}") {
			path = ""
			continue
		}
		m = methodLineRe.FindStringSubmatch(line)
		if m != nil && path != "" {
			endpoints[endpointKey(m[1], path)] = true
		}
	}
	return endpoints
}

func endpointKey(method, path string) string {
	return strings.ToUpper(method) + " " + paramRe.ReplaceAllString(path, "{}")
}

// checkFile returns the findings for one fixture file and the endpoints its no-spec markers name.
func checkFile(path, src string, endpoints map[string]string) ([]string, []string) {
	findings, markers := checkMarkers(path, src, endpoints)
	local := len(markers) > 0 || externalRe.MatchString(src)
	return append(findings, checkExports(path, src, local)...), markers
}

func checkMarkers(path, src string, endpoints map[string]string) ([]string, []string) {
	var findings, markers []string
	for _, m := range markerRe.FindAllStringSubmatch(src, -1) {
		body := markerBodyRe.FindStringSubmatch(m[1])
		if body == nil {
			const form = "%s: the no-spec marker must name one endpoint, as in `// no-spec: GET /members`"
			findings = append(findings, fmt.Sprintf(form, path))
			continue
		}
		endpoint := body[1] + " " + body[2]
		markers = append(markers, endpoint)
		sdk, ok := endpoints[endpointKey(body[1], body[2])]
		if ok {
			const form = "%s: %s is in %s now. Use its type and remove the no-spec marker"
			findings = append(findings, fmt.Sprintf(form, path, endpoint, sdk))
		}
	}
	return findings, markers
}

// checkExports checks each exported value. A file with a no-spec or external marker may use a local type.
func checkExports(path, src string, unspecced bool) []string {
	var findings []string
	masked := mask(src)
	imports := map[string]string{}
	exported := 0
	for _, st := range statements(masked) {
		// A statement starts at its first code byte, after any comment above it.
		begin := st[1] - len(strings.TrimLeft(masked[st[0]:st[1]], " \t\n"))
		text, code := strings.TrimSpace(src[begin:st[1]]), strings.TrimSpace(masked[begin:st[1]])
		m := importRe.FindStringSubmatch(text)
		if m != nil {
			for _, name := range importedNames(m) {
				imports[name] = m[4]
			}
			continue
		}
		// A local alias of an SDK type, such as `type C = components["schemas"]`, counts as that SDK type.
		alias := aliasRe.FindStringSubmatch(code)
		if alias != nil && fromSDK(alias[2], imports) {
			imports[alias[1]] = sdkPrefix
		}
		if !strings.HasPrefix(code, "export") || isTypeExport(code) {
			continue
		}
		exported++
		where := fmt.Sprintf("%s:%d", path, strings.Count(src[:begin], "\n")+1)
		finding := checkExport(code, text, imports, unspecced)
		if finding != "" {
			findings = append(findings, where+": "+finding)
		}
	}
	if exported == 0 {
		findings = append(findings, path+": exports no fixture")
	}
	return findings
}

func isTypeExport(code string) bool {
	return strings.HasPrefix(code, "export type ") || strings.HasPrefix(code, "export interface ")
}

// checkExport returns the finding for one exported statement, or an empty string.
func checkExport(code, text string, imports map[string]string, unspecced bool) string {
	name := constRe.FindStringSubmatch(code)
	if name == nil {
		return "a fixture exports only `const` values, each with `satisfies <T>`"
	}
	at := lastTopLevel(code, satisfies)
	if at < 0 {
		return fmt.Sprintf("`%s` has no `satisfies <T>`", name[1])
	}
	if unspecced || fromSDK(code[at+len(satisfies):], imports) {
		return ""
	}
	typ := strings.TrimSuffix(strings.TrimSpace(text[at+len(satisfies):]), ";")
	return fmt.Sprintf("`%s` satisfies `%s`, which is not imported from `@sdks/*`", name[1], typ)
}

func importedNames(m []string) []string {
	if m[2] != "" {
		return []string{m[2]}
	}
	if m[3] != "" {
		return []string{m[3]}
	}
	var names []string
	for part := range strings.SplitSeq(m[1], ",") {
		fields := strings.Fields(strings.TrimPrefix(strings.TrimSpace(part), "type "))
		if len(fields) > 0 {
			names = append(names, fields[len(fields)-1])
		}
	}
	return names
}

// fromSDK is true when every name in the type is a TypeScript word or an import from an SDK, and one is an SDK import.
func fromSDK(typ string, imports map[string]string) bool {
	sdk := false
	for _, name := range identRe.FindAllString(typ, -1) {
		if slices.Contains(typeWords, name) {
			continue
		}
		if !strings.HasPrefix(imports[name], sdkPrefix) {
			return false
		}
		sdk = true
	}
	return sdk
}

// mask blanks comments and the inside of strings, and keeps every offset and newline, so the scan sees only code.
func mask(src string) string {
	out := []byte(src)
	blank := func(from, to int) {
		for i := from; i < to; i++ {
			if out[i] != '\n' {
				out[i] = ' '
			}
		}
	}
	for i := 0; i < len(src); i++ {
		end := skipped(src, i)
		if end == i {
			continue
		}
		if strings.IndexByte("\"'`", src[i]) >= 0 {
			// The closing quote stays, so the scan continues after it.
			blank(i+1, end)
			i = end
			continue
		}
		blank(i, end)
		i = end - 1
	}
	return string(out)
}

// skipped is the end of the comment that starts at i, or the offset of the closing quote of the string that starts at
// i. It is i when neither starts there.
func skipped(src string, i int) int {
	switch {
	case strings.HasPrefix(src[i:], "//"):
		end := strings.IndexByte(src[i:], '\n')
		if end < 0 {
			return len(src)
		}
		return i + end
	case strings.HasPrefix(src[i:], "/*"):
		end := strings.Index(src[i+2:], "*/")
		if end < 0 {
			return len(src)
		}
		return i + 2 + end + 2
	case src[i] == '"' || src[i] == '\'' || src[i] == '`':
		j := i + 1
		for j < len(src) && src[j] != src[i] {
			if src[j] == '\\' {
				j++
			}
			j++
		}
		return min(j, len(src))
	}
	return i
}

// statements splits masked source at each `;` and each blank line outside brackets.
func statements(masked string) [][2]int {
	var spans [][2]int
	depth, start := 0, 0
	cut := func(end int) {
		if strings.TrimSpace(masked[start:end]) != "" {
			spans = append(spans, [2]int{start, end})
		}
		start = end
	}
	for i := range len(masked) {
		switch masked[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
		case ';':
			if depth == 0 {
				cut(i + 1)
			}
		case '\n':
			if depth == 0 && strings.HasPrefix(masked[i+1:], "\n") {
				cut(i + 1)
			}
		}
	}
	cut(len(masked))
	return spans
}

// lastTopLevel is the offset of the last match of word outside brackets, or -1.
func lastTopLevel(code, word string) int {
	depth, at := 0, -1
	for i := range len(code) {
		switch code[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			depth--
		default:
			if depth == 0 && strings.HasPrefix(code[i:], word) {
				at = i
			}
		}
	}
	return at
}
