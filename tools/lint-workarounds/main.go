// Command lint-workarounds checks that every workaround names a pin it matches or a recent check date, per ADR-0001.
package main

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

// marker matches a comment line that opens with the marker, in a shell, YAML, TOML, Go, TypeScript, or SQL comment.
var marker = regexp.MustCompile(`^\s*(?:#|//|--|\*)\s*Workaround for\b(.*)$`)

// pinned is the form for a component the repository pins. Backticks around the path are optional.
var pinned = regexp.MustCompile("^ (\\S+) (\\S+) in `?([^\\s`:]+)`?:")

// checked is the form for an external service with no pin.
var checked = regexp.MustCompile(`^ (\S+), checked (\d{4})-(\d{2}):`)

const (
	// pinWindow is how many lines after the component's name its version may sit, as in a Chart.yaml dependency.
	pinWindow = 4
	// retestWindow is how many lines after the marker the `Retest:` may sit, within one three-line comment.
	retestWindow = 2
	maxAgeMonths = 12
)

func main() {
	lint.Main("a workaround does not match its pin or is overdue for a retest, per ADR-0001", run)
}

func run(r *lint.Report) error {
	files, err := repo.Files()
	if err != nil {
		return err
	}
	now, err := commitDate()
	if err != nil {
		return err
	}
	tracked := map[string]bool{}
	for _, f := range files {
		tracked[f] = true
	}
	read := func(path string) (string, bool) {
		if !tracked[path] {
			return "", false
		}
		data, err := repo.Read(path)
		return string(data), err == nil
	}
	count := 0
	for _, f := range files {
		if strings.HasPrefix(f, "docs/") || strings.HasSuffix(f, ".md") {
			continue
		}
		data, err := repo.Read(f)
		if err != nil {
			continue
		}
		n, findings := check(f, string(data), now, read)
		count += n
		r.Add(findings...)
	}
	r.Hintf("Run the retest. Then remove the workaround, or move the marker to the new version or a new check date.")
	r.Okf("every workaround matches its pin or was checked in the last %d months, %d workarounds", maxAgeMonths, count)
	return nil
}

// commitDate is the committer date of HEAD, so one commit gets the same verdict on every machine and on every day.
// A repository with no commit yet, such as a project just generated, has no HEAD, so it uses today.
func commitDate() (time.Time, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if exec.CommandContext(ctx, "git", "rev-parse", "--verify", "--quiet", "HEAD").Run() != nil {
		return time.Now().UTC().Truncate(24 * time.Hour), nil
	}
	out, err := exec.CommandContext(ctx, "git", "log", "-1", "--format=%cs", "HEAD").Output()
	if err != nil {
		return time.Time{}, fmt.Errorf("git log: %w", err)
	}
	date, err := time.Parse(time.DateOnly, strings.TrimSpace(string(out)))
	if err != nil {
		return time.Time{}, fmt.Errorf("commit date: %w", err)
	}
	return date, nil
}

// check returns the number of markers in the file at path, and one finding for each marker that fails.
// read returns a tracked file's content, and false for a path that is not tracked.
func check(path, content string, now time.Time, read func(string) (string, bool)) (int, []string) {
	var findings []string
	count := 0
	lines := strings.Split(content, "\n")
	for i, line := range lines {
		m := marker.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		count++
		at := fmt.Sprintf("%s:%d", path, i+1)
		if !hasRetest(lines, i) {
			findings = append(findings, at+": no `Retest:` in the marker's comment")
		}
		problem := markerProblem(m[1], now, read)
		if problem != "" {
			findings = append(findings, at+": "+problem)
		}
	}
	return count, findings
}

// markerProblem judges the text after `Workaround for`, and is empty for a marker that passes.
func markerProblem(rest string, now time.Time, read func(string) (string, bool)) string {
	p := pinned.FindStringSubmatch(rest)
	if p != nil {
		return pinProblem(p[1], p[2], p[3], read)
	}
	c := checked.FindStringSubmatch(rest)
	if c != nil {
		return ageProblem(c[1], c[2]+"-"+c[3], now)
	}
	return "the marker is neither `Workaround for <name> <version> in <path>:` " +
		"nor `Workaround for <name>, checked <YYYY-MM>:`"
}

func hasRetest(lines []string, at int) bool {
	for j := at; j < len(lines) && j <= at+retestWindow; j++ {
		if strings.Contains(lines[j], "Retest:") {
			return true
		}
	}
	return false
}

func pinProblem(name, version, pinFile string, read func(string) (string, bool)) string {
	content, ok := read(pinFile)
	if !ok {
		return fmt.Sprintf("%s names %s as its pin, and that file is not tracked", name, pinFile)
	}
	lines := strings.Split(content, "\n")
	lower := strings.ToLower(name)
	named := false
	for i, line := range lines {
		if !strings.Contains(strings.ToLower(line), lower) {
			continue
		}
		named = true
		for j := i; j < len(lines) && j <= i+pinWindow; j++ {
			if strings.Contains(lines[j], version) {
				return ""
			}
		}
	}
	if !named {
		return fmt.Sprintf("%s does not appear in %s", name, pinFile)
	}
	return fmt.Sprintf("%s is pinned to another version than %s in %s", name, version, pinFile)
}

func ageProblem(name, month string, now time.Time) string {
	at, err := time.Parse("2006-01", month)
	if err != nil {
		return fmt.Sprintf("%s has a check date that is not a month: %s", name, month)
	}
	if at.AddDate(0, maxAgeMonths, 0).Before(now) {
		return fmt.Sprintf("%s was checked in %s, more than %d months before this commit", name, month, maxAgeMonths)
	}
	return ""
}
