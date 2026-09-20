// Command lint-comments enforces ADR-0001's comment rules across Go, TypeScript, shell, YAML, and TOML.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// maxBlockLines is ADR-0001's length test. One line is the norm; three is the ceiling.
const maxBlockLines = 3

// maxEchoChars bounds the echo check. Past it a doc comment is carrying content.
const maxEchoChars = 90

var budgetPath = filepath.Join("tools", "lint-comments", "budget.txt")

// roots are scanned recursively; a root naming a file is scanned alone.
var roots = []string{"apps", "libs", "services", "tools", "scripts", "infra", "test", ".github/workflows", ".mise.toml"}

type rule struct {
	name    string
	pattern *regexp.Regexp
	reason  string
}

func word(words ...string) *regexp.Regexp {
	return regexp.MustCompile(`(?i)\b(` + strings.Join(words, "|") + `)\b`)
}

var rules = []rule{
	{
		name:    "intensifier",
		pattern: word("very", "really", "quite", "obviously", "of course"),
		reason:  "delete it — a claim needing an intensifier is not established",
	},
	{
		name:    "hedge",
		pattern: word("arguably", "essentially", "basically", "somewhat"),
		reason:  "decide — a hedge is an unfinished decision",
	},
	{
		name:    "meta-commentary",
		pattern: regexp.MustCompile(`(?i)(it is worth (knowing|noting)|it should be noted|note that,)`),
		reason:  "state the thing",
	},
	{
		name:    "changelog comment",
		pattern: regexp.MustCompile(`(?i)(^|\s)(@author|@since|@deprecated\s+\d|author:|created:|last (modified|updated):)`),
		reason:  "git holds authorship and dates",
	},
	{
		name: "chronology",
		pattern: regexp.MustCompile(
			`(?i)\b(used to be|previously (was|did|had)|has since|we then (added|changed)|originally (this|it) )`,
		),
		reason: "state what it is now",
	},
	{
		name:    "decorative banner",
		pattern: regexp.MustCompile(`([=*#_~-]|─|━|═){8,}`),
		reason:  "the file structure is the structure",
	},
	{
		name:    "uncited TODO",
		pattern: regexp.MustCompile(`\bTODO\b`),
		reason:  "cite an ADR (ADR-0123) or an issue (#123), or do not merge it",
	},
	{
		name:    "rhetorical question",
		pattern: regexp.MustCompile(`\?\s*$`),
		reason:  "the answer, as a statement",
	},
}

var citation = regexp.MustCompile(`(ADR-\d{4}|#\d+)`)

// codeish matches a comment whose body is code rather than prose. Conservative on
// purpose: a false positive lands on a comment that is doing its job.
var codeish = regexp.MustCompile(
	`^\s*(if|for|while|switch|return|func|function|const|let|var|import|export|class|type|await|go )\b.*[;{}()]\s*$`,
)

// assignmentish catches the other shape of commented-out code: a bare assignment
// or call. A call admits no space before its paren, which keeps prose closing on a
// parenthetical citation out.
var assignmentish = regexp.MustCompile(`^\s*[\w.\[\]]+(\s*(?::?=|\+=)|\()[^)]*[);]\s*$`)

// directive matches a comment a tool reads. Excluded before any rule runs, and not
// counted against the budget: deleting one changes behaviour.
var directive = regexp.MustCompile(
	`(?i)^\s*(shellcheck\s|renovate:|yaml-language-server:|SPDX-|nolint:|eslint-|biome-ignore|ts-|prettier-|` +
		`sqlc:|go:generate|go:build|\+build|noqa|type:\s|platform/not-deployed)`,
)

// exported matches a Go or TypeScript declaration of an exported identifier, and
// captures its name.
var exported = regexp.MustCompile(
	`^\s*(?:export\s+(?:default\s+)?)?(?:func|type|const|var|let|class|interface|function|enum)\s+` +
		`(\(\w+\s+\*?\w+\)\s+)?([A-Z]\w*)`,
)

// signal is a fact a signature cannot state. A doc comment on an exported
// identifier carries one, or it restates the declaration and is deleted.
var signal = regexp.MustCompile(
	`(?i)(ADR-\d{4}|\bnil\b|\bmust\b|\bnever\b|\bonly\b|\bpanic|\berror|\bcaller|\bzero\b|\bempty\b|\bnegative\b|` +
		`\binclusive\b|\bexclusive\b|\bat least\b|\bat most\b|\bconcurrent|\bblocks\b|\bcloses\b|\bowns\b|\bmutates\b|` +
		`\bretains\b|\bunsafe\b|\bUTC\b|\bcents\b|\bbytes\b|\bseconds\b|\bdoes not\b|\bcannot\b|\bis not\b|\bare not\b|` +
		`\bno\b|\bnot\b|\$[A-Z_]{3,}|\bdefault|\bRFC \d|\bcolumn\b|\bwire\b|\bimplements\b|\bISO \d)`,
)

type finding struct {
	file   string
	line   int
	rule   string
	reason string
	text   string
}

// block is a run of consecutive own-line comments, or a single trailing comment.
type block struct {
	start    int
	lines    []string // raw source lines
	bodies   []string // comment text
	trailing bool
	next     string // the first code line under the block
}

func main() {
	ratchet := flag.Bool("ratchet", false, "stamp the current comment count as the budget")
	flag.Parse()

	found, total := sweep()

	if *ratchet {
		current, ok := budget()
		if ok && total >= current {
			_, _ = fmt.Fprintf(os.Stdout, "✓ comment budget holds at %d lines (tree carries %d)\n", current, total)
			return
		}
		err := os.WriteFile(budgetPath, []byte(strconv.Itoa(total)+"\n"), 0o600)
		if err != nil {
			failf("write %s: %v", budgetPath, err)
		}
		_, _ = fmt.Fprintf(os.Stdout, "✓ comment budget lowered to %d lines\n", total)
		return
	}

	over := budgetExceeded(total)
	if len(found) == 0 && over == "" {
		_, _ = fmt.Fprintf(os.Stdout, "✓ comments conform to ADR-0001 (%d comment lines)\n", total)
		return
	}
	for _, f := range found {
		_, _ = fmt.Fprintf(os.Stderr, "✗ %s:%d: %s — %s\n", f.file, f.line, f.rule, f.reason)
		_, _ = fmt.Fprintf(os.Stderr, "    %s\n", strings.TrimSpace(f.text))
	}
	if over != "" {
		_, _ = fmt.Fprintf(os.Stderr, "✗ %s\n", over)
	}
	_, _ = fmt.Fprintf(os.Stderr, "\n  ADR-0001's comment rules. A line may opt out with `lint:comments-allow`.\n")
	os.Exit(1)
}

// sweep scans every root and returns the violations and the tree's comment count.
func sweep() ([]finding, int) {
	var found []finding
	total := 0
	collect := func(path string) error {
		hits, n, err := scan(path)
		if err != nil {
			return err
		}
		found = append(found, hits...)
		total += n
		return nil
	}
	for _, root := range roots {
		info, err := os.Stat(root)
		if err != nil {
			continue
		}
		if !info.IsDir() {
			err = collect(root)
			if err != nil {
				failf("scan %s: %v", root, err)
			}
			continue
		}
		walk := func(path string, info os.FileInfo, err error) error {
			switch {
			case err != nil:
				return err
			case info.IsDir() && skipDir(info.Name()):
				return filepath.SkipDir
			case info.IsDir() || !scannable(path):
				return nil
			}
			return collect(path)
		}
		err = filepath.Walk(root, walk)
		if err != nil {
			failf("walk %s: %v", root, err)
		}
	}
	return found, total
}

// budget reads the stamped comment-line ceiling.
func budget() (int, bool) {
	raw, err := os.ReadFile(budgetPath)
	if err != nil {
		return 0, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		return 0, false
	}
	return n, true
}

// budgetExceeded reports the overage when the tree carries more comment lines than
// the stamped ceiling. `mise run gen` lowers that ceiling and never raises it.
func budgetExceeded(total int) string {
	ceiling, ok := budget()
	if !ok || total <= ceiling {
		return ""
	}
	const form = "comment budget: %d lines, %d over the %d in %s — delete, do not raise it"
	return fmt.Sprintf(form, total, total-ceiling, ceiling, budgetPath)
}

func skipDir(name string) bool {
	switch name {
	case "node_modules", ".next", "dist", "build", "_generated", "sdks", "schemas", "secrets", "testdata":
		return true
	default:
		return false
	}
}

// marks are the comment delimiters of one language.
type marks struct {
	line  []string
	open  string
	close string
}

// syntax returns the comment markers for a path, and whether it is scannable.
func syntax(path string) (marks, bool) {
	switch filepath.Ext(path) {
	case ".go", ".ts", ".tsx":
		return marks{line: []string{"//"}, open: "/*", close: "*/"}, true
	case ".sh", ".toml":
		return marks{line: []string{"#"}}, true
	case ".yaml", ".yml":
		return marks{line: []string{"#"}, open: "{{/*", close: "*/}}"}, true
	default:
		return marks{}, false
	}
}

func scannable(path string) bool {
	_, ok := syntax(path)
	if !ok {
		return false
	}
	base := filepath.Base(path)
	if strings.HasSuffix(base, "_gen.go") || strings.HasSuffix(base, ".sql.go") || strings.Contains(base, ".enc.") {
		return false
	}
	// This file names the constructs it bans, the way ADR-0001 does.
	return !strings.HasSuffix(path, filepath.Join("tools", "lint-comments", "main.go"))
}

// scan returns every violation in one file, and its comment-line count.
func scan(path string) ([]finding, int, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, 0, fmt.Errorf("open: %w", err)
	}
	defer func() { _ = file.Close() }()

	m, _ := syntax(path)
	var lines []string
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	err = scanner.Err()
	if err != nil {
		return nil, 0, fmt.Errorf("read: %w", err)
	}

	blocks, count := blocksOf(lines, m, rawStringSpans(path, lines))
	var out []finding
	for _, b := range blocks {
		out = append(out, checkBlock(path, b)...)
	}
	return out, count, nil
}

// blocksOf groups a file's comment lines into blocks, and counts them. A run of
// own-line comments is one block; a comment trailing code is a block of its own.
func blocksOf(lines []string, m marks, raw map[int]bool) ([]block, int) {
	var out []block
	count := 0
	inBlockComment := false
	var run *block
	flush := func(next string) {
		if run != nil {
			run.next = next
			out = append(out, *run)
			run = nil
		}
	}
	for i, line := range lines {
		if raw[i] {
			flush(line)
			continue
		}
		body, own, isComment := commentBody(line, m, &inBlockComment)
		if !isComment {
			flush(line)
			continue
		}
		if strings.Contains(line, "lint:comments-allow") || directive.MatchString(body) {
			flush(line)
			continue
		}
		count++
		if !own {
			flush("")
			out = append(out, block{start: i + 1, lines: []string{line}, bodies: []string{body}, trailing: true})
			continue
		}
		if run == nil {
			run = &block{start: i + 1}
		}
		run.lines = append(run.lines, line)
		run.bodies = append(run.bodies, body)
		// A closing `*/` ends the block it opened: two adjacent doc comments are two
		// comments, not one run.
		if !inBlockComment && m.open != "" && strings.Contains(strings.TrimSpace(line), m.close) {
			flush("")
		}
	}
	flush("")
	return out, count
}

// commentBody returns a line's comment text, whether the comment owns the line, and
// whether the line carries one at all.
func commentBody(line string, m marks, inBlock *bool) (string, bool, bool) {
	trimmed := strings.TrimSpace(line)
	if *inBlock {
		if strings.Contains(trimmed, m.close) {
			*inBlock = false
		}
		return strings.TrimPrefix(strings.TrimPrefix(trimmed, m.close), "*"), true, true
	}
	rest, isOpen := strings.CutPrefix(trimmed, m.open)
	if m.open != "" && isOpen {
		*inBlock = !strings.Contains(trimmed, m.close)
		return rest, true, true
	}
	if strings.HasPrefix(trimmed, "#!") {
		return "", true, false
	}
	for _, mark := range m.line {
		own, isOwn := strings.CutPrefix(trimmed, mark)
		if isOwn {
			return own, true, true
		}
		idx := strings.Index(trimmed, mark)
		if idx < 0 {
			continue
		}
		// A `//` preceded by a colon is a URL scheme; a `#` inside quotes is data.
		if mark == "//" && trimmed[idx-1] == ':' {
			continue
		}
		if strings.Count(trimmed[:idx], `"`)%2 == 1 || strings.Count(trimmed[:idx], `'`)%2 == 1 {
			continue
		}
		return trimmed[idx+len(mark):], false, true
	}
	return "", true, false
}

func checkBlock(path string, b block) []finding {
	var out []finding
	add := func(line int, name, reason, text string) {
		out = append(out, finding{file: path, line: line, rule: name, reason: reason, text: text})
	}
	out = append(out, checkLines(path, b)...)
	if b.trailing {
		return out
	}
	if paragraphs(b.bodies) > 1 {
		add(b.start, "multi-paragraph comment", "a second paragraph is a document — move it to docs/ and cite it", b.lines[0])
	}
	n := contentLines(b.bodies)
	if n > maxBlockLines {
		reason := fmt.Sprintf("%d lines, max %d — one line is the norm", n, maxBlockLines)
		add(b.start, "over-length comment", reason, b.lines[0])
	}
	// An echo of the declaration is short and fits on one line. A doc that runs
	// longer is carrying content the word test cannot recognise.
	name, isExported := exportedName(b.next)
	if isExported && len(b.bodies) == 1 && len(strings.TrimSpace(b.bodies[0])) < maxEchoChars &&
		!signal.MatchString(b.bodies[0]) {
		reason := "state a fact `" + name + "`'s signature cannot — units, nil-ness, bounds, side effects — or delete it"
		add(b.start, "echo doc comment", reason, b.lines[0])
	}
	return out
}

// checkLines applies the per-line rules to every line of one block.
func checkLines(path string, b block) []finding {
	var out []finding
	for i, body := range b.bodies {
		for _, r := range rules {
			if !r.pattern.MatchString(body) {
				continue
			}
			if r.name == "uncited TODO" && citation.MatchString(body) {
				continue
			}
			out = append(out, finding{path, b.start + i, r.name, r.reason, b.lines[i]})
		}
		// A tab-indented line inside a doc comment is a rendered code block, not a
		// call someone commented out.
		if !strings.HasPrefix(body, "\t") && !citation.MatchString(body) &&
			(codeish.MatchString(body) || assignmentish.MatchString(body)) {
			out = append(out, finding{path, b.start + i, "commented-out code", "git holds it", b.lines[i]})
		}
	}
	return out
}

// paragraphs counts the blank comment lines that separate a block's paragraphs. A
// trailing blank separates the prose from a directive below it, not one paragraph
// from another.
func paragraphs(bodies []string) int {
	for len(bodies) > 0 && blankComment(bodies[len(bodies)-1]) {
		bodies = bodies[:len(bodies)-1]
	}
	for len(bodies) > 0 && blankComment(bodies[0]) {
		bodies = bodies[1:]
	}
	n := 1
	for _, body := range bodies {
		if blankComment(body) {
			n++
		}
	}
	return n
}

// contentLines counts a block's lines of prose. A bare `/**` or `*/` is syntax.
func contentLines(bodies []string) int {
	n := 0
	for _, body := range bodies {
		if !blankComment(body) {
			n++
		}
	}
	return n
}

func blankComment(body string) bool {
	return strings.TrimSpace(strings.Trim(body, "*/")) == ""
}

func exportedName(next string) (string, bool) {
	m := exported.FindStringSubmatch(next)
	if m == nil {
		return "", false
	}
	return m[2], true
}

func failf(format string, args ...any) {
	_, _ = fmt.Fprintf(os.Stderr, "✗ "+format+"\n", args...)
	os.Exit(1)
}

var heredocStart = regexp.MustCompile(`<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?`)

// splicedYAML marks a spec's generated shared-components region, which
// tools/shared-components writes from tools/codegen/shared-components.yaml.
func splicedYAML(lines []string) map[int]bool {
	out := map[int]bool{}
	inSplice := false
	for i, line := range lines {
		switch {
		case strings.Contains(line, ">>> shared-components:"):
			inSplice = true
		case strings.Contains(line, "<<< shared-components"):
			inSplice = false
		}
		if inSplice {
			out[i] = true
		}
	}
	return out
}

// rawStringSpans marks the lines a generator writes as data rather than as
// comments — a Go raw-string literal or a shell heredoc. Deleting a comment marker
// inside one changes what the generator emits.
func rawStringSpans(path string, lines []string) map[int]bool {
	out := map[int]bool{}
	ext := filepath.Ext(path)
	if ext == ".yaml" || ext == ".yml" {
		return splicedYAML(lines)
	}
	if ext == ".sh" {
		term := ""
		for i, line := range lines {
			if term != "" {
				out[i] = true
				if strings.TrimSpace(line) == term {
					term = ""
				}
				continue
			}
			m := heredocStart.FindStringSubmatch(line)
			if m != nil {
				term = m[1]
			}
		}
		return out
	}
	if ext != ".go" {
		return out
	}
	inRaw := false
	for i, line := range lines {
		ticks := strings.Count(line, "`")
		if inRaw {
			out[i] = true
		}
		if ticks%2 == 1 {
			inRaw = !inRaw
		}
	}
	return out
}
