// Command lint-prose enforces ADR-0001's banned-constructs table across every committed Markdown file.
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
)

// A rule is one banned construct: the pattern that finds it, and the reason a reader
// gets back. The reason is the fix, not the label — a linter that only names the
// category leaves the author guessing at the rewrite.
type rule struct {
	name    string
	pattern *regexp.Regexp
	reason  string
	// exempt lists files where this rule does not apply. One entry, and it is
	// structural: the component inventory's subject is live state, so "declared
	// Core, not yet deployed" is the fact rather than a status aside.
	exempt map[string]bool
}

// word builds a case-insensitive whole-word alternation. Word boundaries matter more
// here than anywhere: "just" inside "adjust" is not an intensifier.
func word(words ...string) *regexp.Regexp {
	return regexp.MustCompile(`(?i)\b(` + strings.Join(words, "|") + `)\b`)
}

var rules = []rule{
	{
		name:    "intensifier",
		pattern: word("very", "really", "quite", "actually", "simply", "just", "obviously", "clearly"),
		reason:  "delete it — a claim needing an intensifier is not established",
	},
	{
		name:    "intensifier",
		pattern: regexp.MustCompile(`(?i)\b(of course)\b`),
		reason:  "delete it — a claim needing an intensifier is not established",
	},
	{
		name:    "hedge",
		pattern: word("arguably", "essentially", "basically", "somewhat", "fairly"),
		reason:  "decide — a hedge is an unfinished decision",
	},
	{
		name:    "hedge",
		pattern: regexp.MustCompile(`(?i)\b(more or less|in practice)\b`),
		reason:  "decide — a hedge is an unfinished decision",
	},
	{
		name: "meta-commentary",
		pattern: regexp.MustCompile(
			`(?i)(note that|it should be noted|it is worth|worth noting|` +
				`worth knowing|as mentioned|as noted above)`,
		),
		reason: "state the thing instead of introducing it",
	},
	{
		name: "implementation status",
		pattern: regexp.MustCompile(
			`(?i)\b(not yet|so far|for now|at present|currently|` +
				`the status quo|tracked in|lands in a later)\b`,
		),
		reason: "state the rule unqualified — whether the artefact exists is not an ADR's subject",
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
		reason:  "an ADR is law, not a plan — the gap belongs in a local working file",
	},
	{
		name:    "dated heading",
		pattern: regexp.MustCompile(`^#{1,6}\s.*\b(19|20)\d{2}\b`),
		reason:  "an undated heading — chronology is not the subject",
	},
	{
		name:    "link to an untracked file",
		pattern: regexp.MustCompile(`\]\([^)]*\.local\.md[^)]*\)`),
		reason:  "the file is absent from every other clone",
	},
}

// skipFiles are exempt for structural reasons rather than by concession.
var skipFiles = map[string]bool{
	"docs/adr/0001-documentation-and-output-conventions.md": true, // names the constructs it bans
	"docs/adr/_template.md":                                 true, // carries the checklist verbatim
	"CODE_OF_CONDUCT.md":                                    true, // adopted verbatim from the Contributor Covenant
}

const allowMarker = "<!-- prose:allow -->"

// codeSpan matches an inline code span. Its contents are an artefact — a tool name, a
// flag, a config value — not prose, so `just` the task runner is not the intensifier.
var codeSpan = regexp.MustCompile("`[^`]*`")

func main() {
	lint.Main("prose violates the ADR-0001 banned-constructs table", run)
}

func run(r *lint.Report) error {
	roots := []string{"docs", "README.md", "AGENTS.md", "SECURITY.md", "CODE_OF_CONDUCT.md"}
	for _, root := range roots {
		err := filepath.Walk(
			root,
			func(path string, info os.FileInfo, err error) error {
				if err != nil {
					return err
				}
				if info.IsDir() || !strings.HasSuffix(path, ".md") {
					return nil
				}
				if strings.HasSuffix(path, ".local.md") || skipFiles[filepath.ToSlash(path)] {
					return nil
				}
				findings, err := checkFile(path)
				r.Add(findings...)
				return err
			},
		)
		if err != nil {
			return fmt.Errorf("walk %s: %w", root, err)
		}
	}
	r.Okf("prose conforms to ADR-0001")
	return nil
}

func checkFile(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	defer func() { _ = f.Close() }()

	var findings []string
	inFence := false
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for n := 1; scanner.Scan(); n++ {
		line := scanner.Text()
		if strings.HasPrefix(strings.TrimSpace(line), "```") {
			inFence = !inFence
			continue
		}
		if inFence || strings.Contains(line, allowMarker) {
			continue
		}
		prose := codeSpan.ReplaceAllString(line, " ")
		for _, r := range rules {
			if r.exempt[filepath.ToSlash(path)] {
				continue
			}
			m := r.pattern.FindString(prose)
			if m != "" {
				finding := fmt.Sprintf(
					"%s:%d: %s %q — %s",
					path,
					n,
					r.name,
					strings.TrimSpace(m),
					r.reason,
				)
				findings = append(findings, finding)
			}
		}
	}
	err = scanner.Err()
	if err != nil {
		return findings, fmt.Errorf("read %s: %w", path, err)
	}
	return findings, nil
}
