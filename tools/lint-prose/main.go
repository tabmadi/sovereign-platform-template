// Command lint-prose enforces ADR-0001 on prose: the banned-constructs table and the Simple English profile
// over every Markdown file and UI message, and the banned characters over every tracked text file.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/simple"
)

// A rule is one banned construct: the pattern that finds it, and the reason a reader gets back. The reason
// is the fix, not the label, so the author does not guess at the rewrite.
type rule struct {
	name    string
	pattern *regexp.Regexp
	reason  string
	// exempt lists files where this rule does not apply. The one entry is structural: the component
	// inventory's subject is live state, so `declared Core, not yet deployed` is the fact.
	exempt map[string]bool
}

// word builds a case-insensitive whole-word alternation. The word boundary keeps `just` inside `adjust`
// from matching.
func word(words ...string) *regexp.Regexp {
	return regexp.MustCompile(`(?i)\b(` + strings.Join(words, "|") + `)\b`)
}

var rules = []rule{
	{
		name:    "intensifier",
		pattern: word("very", "really", "quite", "actually", "simply", "just", "obviously", "clearly"),
		reason:  "delete it. A claim that needs an intensifier is not established",
	},
	{
		name:    "intensifier",
		pattern: regexp.MustCompile(`(?i)\b(of course)\b`),
		reason:  "delete it. A claim that needs an intensifier is not established",
	},
	{
		name:    "hedge",
		pattern: word("arguably", "essentially", "basically", "somewhat", "fairly"),
		reason:  "decide. A hedge is an unfinished decision",
	},
	{
		name:    "hedge",
		pattern: regexp.MustCompile(`(?i)\b(more or less|in practice)\b`),
		reason:  "decide. A hedge is an unfinished decision",
	},
	{
		name: "meta-commentary",
		pattern: regexp.MustCompile(
			`(?i)(note that|it should be noted|it is worth|worth noting|` +
				`worth knowing|as mentioned|as noted above)`,
		),
		reason: "state the thing, without an introduction",
	},
	{
		name: "implementation status",
		pattern: regexp.MustCompile(
			`(?i)\b(not yet|so far|for now|at present|currently|` +
				`the status quo|tracked in|lands in a later)\b`,
		),
		reason: "state the rule with no qualifier. Whether the artefact exists is not an ADR's subject",
		exempt: map[string]bool{
			"docs/operational-surface.md": true,
			"README.md":                   true,
		},
	},
	{
		name: "chronology",
		pattern: regexp.MustCompile(
			`(?i)\b(has since|used to be|it turned out|previously,|` +
				`did not previously|in earlier versions)\b`,
		),
		reason: "state the standing fact: what is true now",
	},
	{
		name:    "planned work",
		pattern: regexp.MustCompile(`(^|\s)(TODO|FIXME|Follow-ups?:)`),
		reason:  "an ADR is law, not a plan. The gap belongs in a local working file",
	},
	{
		name:    "dated heading",
		pattern: regexp.MustCompile(`^#{1,6}\s.*\b(19|20)\d{2}\b`),
		reason:  "write a heading with no date. Chronology is not the subject",
	},
	{
		name:    "link to an untracked file",
		pattern: regexp.MustCompile(`\]\([^)]*\.local\.md[^)]*\)`),
		reason:  "the file is absent from every other clone",
	},
}

// constructsExempt skip the banned-constructs table because they name the constructs. The Simple English
// profile still applies to them.
var constructsExempt = map[string]bool{
	"docs/adr/0001-documentation-and-output-conventions.md": true,
	"docs/adr/_template.md":                                 true,
}

// verbatim files are adopted or generated from a source this repository does not write, so no prose rule
// applies. The changelog is generated from commit titles.
var verbatim = map[string]bool{
	"CODE_OF_CONDUCT.md": true,
	"LICENSE":            true,
	"CHANGELOG.md":       true,
}

// lockfiles hold upstream metadata, not text this repository writes.
var lockfiles = map[string]bool{"bun.lock": true, "go.sum": true, "go.work.sum": true, "package-lock.json": true}

const allowMarker = "<!-- prose:allow -->"

const messagesDir = "apps/frontend/src/messages"

func main() {
	lint.Main("prose violates ADR-0001", run)
}

func run(r *lint.Report) error {
	files, err := repo.Files()
	if err != nil {
		return err
	}
	slices.Sort(files)
	for _, path := range files {
		path = filepath.ToSlash(path)
		if verbatim[path] || lockfiles[filepath.Base(path)] || strings.HasSuffix(path, ".local.md") {
			continue
		}
		body, err := os.ReadFile(path)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return fmt.Errorf("read %s: %w", path, err)
		}
		if bytes.IndexByte(body, 0) >= 0 {
			continue
		}
		r.Add(checkChars(path, body)...)
		switch {
		case strings.HasSuffix(path, ".md"):
			r.Add(checkMarkdown(path, body)...)
		case filepath.Dir(path) == messagesDir && strings.HasSuffix(path, ".json"):
			findings, err := checkMessages(path, body)
			if err != nil {
				return err
			}
			r.Add(findings...)
		}
	}
	r.Hintf("ADR-0001 holds the rules. A Markdown line opts out with %s.", allowMarker)
	r.Okf("prose conforms to ADR-0001")
	return nil
}

// checkChars finds the characters ADR-0001 bans from every tracked text file.
func checkChars(path string, body []byte) []string {
	var out []string
	for n, line := range strings.Split(string(body), "\n") {
		for _, c := range line {
			name, banned := simple.BannedChars[c]
			if banned {
				out = append(out, fmt.Sprintf("%s:%d: %s %q: not used in any file. Rewrite the text", path, n+1, name, c))
				break
			}
		}
	}
	return out
}

var (
	fence          = regexp.MustCompile("^\\s*(```|~~~)")
	tableDelimiter = regexp.MustCompile(`^\|?[\s:|-]+\|?$`)
	refDefinition  = regexp.MustCompile(`^\s*\[[^\]]+\]:\s`)
)

func checkMarkdown(path string, body []byte) []string {
	limit := simple.MaxWords
	if strings.HasPrefix(path, "docs/guide/") {
		limit = simple.MaxProcedureWords
	}
	opts := simple.Options{English: true, WordSlash: true, MaxWords: limit, SkipChars: true}

	var findings []string
	var skip skipper
	for n, line := range strings.Split(string(body), "\n") {
		n++
		if skip.skips(line) {
			continue
		}
		if !constructsExempt[path] {
			prose := simple.StripCode(line)
			for _, r := range rules {
				if r.exempt[path] {
					continue
				}
				m := r.pattern.FindString(prose)
				if m != "" {
					findings = append(findings, fmt.Sprintf("%s:%d: %s %q: %s", path, n, r.name, strings.TrimSpace(m), r.reason))
				}
			}
		}
		for _, text := range proseUnits(line) {
			for _, f := range simple.Check(text, opts) {
				findings = append(findings, fmt.Sprintf("%s:%d: %s", path, n, f))
			}
		}
	}
	return findings
}

// skipper tracks the Markdown that is not prose: fenced code, multi-line HTML comments, allow-marked lines,
// and link reference definitions.
type skipper struct {
	inFence, inComment bool
}

func (k *skipper) skips(line string) bool {
	if fence.MatchString(line) {
		k.inFence = !k.inFence
		return true
	}
	if k.inComment {
		k.inComment = !strings.Contains(line, "-->")
		return true
	}
	trimmed := strings.TrimSpace(line)
	if strings.HasPrefix(trimmed, "<!--") && !strings.Contains(trimmed, "-->") {
		k.inComment = true
		return true
	}
	return k.inFence || strings.Contains(line, allowMarker) || refDefinition.MatchString(line)
}

// proseUnits splits a Markdown line into the texts ADR-0001 counts separately: each table cell, or the
// whole line.
func proseUnits(line string) []string {
	trimmed := strings.TrimSpace(line)
	if strings.HasPrefix(trimmed, "|") {
		if tableDelimiter.MatchString(trimmed) {
			return nil
		}
		stripped := simple.StripMarkdown(trimmed)
		var cells []string
		for cell := range strings.SplitSeq(strings.Trim(stripped, "|"), "|") {
			cell = strings.TrimSpace(strings.Trim(cell, "*_"))
			if cell != "" {
				cells = append(cells, cell)
			}
		}
		return cells
	}
	return []string{simple.StripMarkdown(line)}
}

// checkMessages applies the profile to every UI string. English gets the word checks, and every locale gets
// the punctuation checks.
func checkMessages(path string, body []byte) ([]string, error) {
	var tree any
	err := json.Unmarshal(body, &tree)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	opts := simple.Options{
		English:   strings.TrimSuffix(filepath.Base(path), ".json") == "en",
		MaxWords:  simple.MaxWords,
		SkipChars: true,
	}
	var findings []string
	var walk func(key string, v any)
	walk = func(key string, v any) {
		switch v := v.(type) {
		case map[string]any:
			for k, child := range v {
				walk(strings.TrimPrefix(key+"."+k, "."), child)
			}
		case string:
			text := icuArgument.ReplaceAllString(v, "x")
			for _, f := range simple.Check(text, opts) {
				findings = append(findings, fmt.Sprintf("%s: %s: %s", path, key, f))
			}
		}
	}
	walk("", tree)
	return findings, nil
}

// icuArgument is an ICU placeholder or plural block. Its syntax is not prose.
var icuArgument = regexp.MustCompile(`\{[^{}]*\}`)
