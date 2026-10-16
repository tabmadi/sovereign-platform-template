// Command lint-requirements checks the requirements files and their trace to the tests, per ADR-0602.
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

// templatePrefix is the placeholder of services/_template. A copied service keeps it until its author picks one.
const templatePrefix = "TPL"

var (
	prefixLine  = regexp.MustCompile(`^- \*\*Prefix:\*\* (\S+)$`)
	validPrefix = regexp.MustCompile(`^[A-Z]{2,4}$`)
	// A row whose first cell looks like an ID is a requirement. The header and delimiter rows do not match.
	requirementRow = regexp.MustCompile(`^\| ([A-Z]{2,4}-\d{3}) \| (.+) \|$`)
	idShapedRow    = regexp.MustCompile(`^\| [A-Z]+-\d+ \|`)
	// A citation is any ID-shaped word in a test file. Only a declared prefix counts, so `SHA-256` is not a citation.
	citation = regexp.MustCompile(`\b([A-Z]{2,4})-(\d{3})\b`)
	earsOpen = regexp.MustCompile(`^(The|When|While|If|Where) `)
)

func main() {
	lint.Main("requirements do not trace to tests", run)
}

type requirement struct {
	file string
	line int
}

func run(r *lint.Report) error {
	files, err := repo.Files()
	if err != nil {
		return err
	}
	slices.Sort(files)

	prefixes := map[string]string{} // prefix -> file that declares it
	reqs := map[string]requirement{}
	for _, path := range files {
		path = filepath.ToSlash(path)
		if !isRequirementsFile(path) {
			continue
		}
		body, err := repo.Read(path)
		if err != nil {
			return err
		}
		r.Add(parse(path, string(body), prefixes, reqs)...)
	}

	cited := map[string]bool{}
	for _, path := range files {
		path = filepath.ToSlash(path)
		if !isTestFile(path) {
			continue
		}
		body, err := repo.Read(path)
		if err != nil {
			return err
		}
		for _, m := range citation.FindAllStringSubmatch(string(body), -1) {
			if prefixes[m[1]] == "" || m[1] == templatePrefix {
				continue
			}
			id := m[0]
			cited[id] = true
			_, defined := reqs[id]
			if !defined {
				r.Addf("%s: cites %s, which no requirements file defines", path, id)
			}
		}
	}

	for id, req := range reqs {
		if strings.HasPrefix(req.file, "services/_template/") {
			continue
		}
		if !cited[id] {
			r.Addf("%s:%d: %s has no test that cites it", req.file, req.line, id)
		}
	}

	r.Hintf("ADR-0602 holds the rules. A test cites a requirement by its ID in the test name: t.Run(\"ORD-003 ...\").")
	r.Okf("%d requirements in %d files, each cited by a test", len(reqs), len(prefixes))
	return nil
}

// parse reads one requirements file into the shared maps and returns its findings.
func parse(path, body string, prefixes map[string]string, reqs map[string]requirement) []string {
	var problems []string
	at := func(n int, format string, args ...any) {
		problems = append(problems, fmt.Sprintf("%s:%d: ", path, n+1)+fmt.Sprintf(format, args...))
	}
	prefix := ""
	count := 0
	for n, line := range strings.Split(body, "\n") {
		m := prefixLine.FindStringSubmatch(line)
		if m != nil && prefix == "" {
			prefix = m[1]
			problems = append(problems, checkPrefix(path, prefix, prefixes)...)
			continue
		}
		row := requirementRow.FindStringSubmatch(line)
		if row == nil {
			if idShapedRow.MatchString(line) {
				at(n, "a requirement row is | ABC-001 | sentence |")
			}
			continue
		}
		count++
		id, sentence := row[1], strings.TrimSpace(row[2])
		if prefix == "" || !strings.HasPrefix(id, prefix+"-") {
			at(n, "%s does not use the file's prefix %q", id, prefix)
		}
		earlier, duplicate := reqs[id]
		if duplicate {
			at(n, "%s is already defined at %s:%d", id, earlier.file, earlier.line)
			continue
		}
		reqs[id] = requirement{file: path, line: n + 1}
		if !earsOpen.MatchString(sentence) {
			at(n, "%s does not open with an EARS keyword: The, When, While, If, or Where", id)
		}
		if strings.Contains(sentence, "|") {
			at(n, "%s has more than one sentence cell", id)
		}
	}
	if prefix == "" {
		problems = append(problems, path+": no `- **Prefix:**` line in the header")
	}
	if count == 0 {
		problems = append(problems, path+": holds no requirement")
	}
	return problems
}

func checkPrefix(path, prefix string, prefixes map[string]string) []string {
	var problems []string
	if !validPrefix.MatchString(prefix) {
		problems = append(problems, fmt.Sprintf("%s: prefix %q is not two to four capital letters", path, prefix))
	}
	isTemplate := strings.HasPrefix(path, "services/_template/")
	if prefix == templatePrefix && !isTemplate {
		problems = append(problems, fmt.Sprintf("%s: still uses the template prefix %s. Choose its own prefix", path, prefix))
	}
	other, taken := prefixes[prefix]
	if taken {
		problems = append(problems, fmt.Sprintf("%s: prefix %s is already declared by %s", path, prefix, other))
	} else {
		prefixes[prefix] = path
	}
	return problems
}

func isRequirementsFile(path string) bool {
	if strings.HasPrefix(path, "services/") && strings.Count(path, "/") == 2 {
		return filepath.Base(path) == "requirements.md"
	}
	return strings.HasPrefix(path, "docs/requirements/") && strings.HasSuffix(path, ".md") &&
		filepath.Base(path) != "README.md"
}

func isTestFile(path string) bool {
	for _, suffix := range []string{"_test.go", ".spec.ts", ".test.ts", ".test.tsx"} {
		if strings.HasSuffix(path, suffix) {
			return true
		}
	}
	return false
}
