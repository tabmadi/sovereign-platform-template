// Command lint-adr-xref checks the ADR set's internal wiring: references, Related headers, index rows, and genre
// paths (ADR-0001).
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const (
	adrDir      = "docs/adr"
	docsDir     = "docs"
	surfacePath = "docs/operational-surface.md"
	deferPath   = "docs/reference/deferral-register.md"
	pathPath    = "docs/adoption-path.md"
	indexPath   = "docs/adr/README.md"
)

var (
	adrRef     = regexp.MustCompile(`ADR-(\d{4})`)
	adrFile    = regexp.MustCompile(`^(\d{4})-[a-z0-9-]+\.md$`)
	relatedRow = regexp.MustCompile(`^- \*\*Related:\*\* (.+)$`)
	decidesRow = regexp.MustCompile(`^- \*\*Decides:\*\* \S`)
	indexRow   = regexp.MustCompile(`^\| \[(\d{4})\]\(([^)]+)\)`)
	reservedNo = regexp.MustCompile(`^\| (\d{4}) \| `)
	// A bold leading table cell is how both inventory documents name a component.
	boldCell = regexp.MustCompile(`^\| \*\*([^*|]+)\*\*`)
	readme   = regexp.MustCompile(`\]\((\.\./)+README\.md`)
)

func main() {
	set, err := loadSet()
	if err != nil {
		failf("%v", err)
	}
	problems := make([]string, 0, len(set.files))
	problems = append(problems, checkReferences(set)...)
	problems = append(problems, checkRelatedExists(set)...)
	problems = append(problems, checkDecidesAndIndex(set)...)
	problems = append(problems, checkComponentAgreement()...)
	problems = append(problems, checkDeferralCoverage(set)...)
	problems = append(problems, checkReadmeBoundary()...)

	if len(problems) > 0 {
		_, _ = fmt.Fprintln(os.Stderr, "✗ ADR cross-references do not hold:")
		sort.Strings(problems)
		for _, p := range problems {
			_, _ = fmt.Fprintln(os.Stderr, "  "+p)
		}
		os.Exit(1)
	}
	_, _ = fmt.Fprintf(os.Stdout, "✓ ADR cross-references hold across %d ADRs\n", len(set.files))
}

// adrSet is the allocated numbering: files that exist, and numbers held in reserve.
type adrSet struct {
	files    map[string]string   // number -> path
	reserved map[string]bool     // number -> held
	related  map[string][]string // number -> numbers named in its Related header
}

func loadSet() (*adrSet, error) {
	set := &adrSet{
		files:    map[string]string{},
		reserved: map[string]bool{},
		related:  map[string][]string{},
	}
	entries, err := os.ReadDir(adrDir)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", adrDir, err)
	}
	for _, e := range entries {
		m := adrFile.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		path := filepath.Join(adrDir, e.Name())
		set.files[m[1]] = path
		body, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", path, err)
		}
		for line := range strings.SplitSeq(string(body), "\n") {
			r := relatedRow.FindStringSubmatch(line)
			if r != nil {
				for _, ref := range adrRef.FindAllStringSubmatch(r[1], -1) {
					set.related[m[1]] = append(set.related[m[1]], ref[1])
				}
				break
			}
		}
	}
	index, err := os.ReadFile(indexPath)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", indexPath, err)
	}
	inReserved := false
	for line := range strings.SplitSeq(string(index), "\n") {
		if strings.HasPrefix(line, "## Reserved") {
			inReserved = true
			continue
		}
		if inReserved && strings.HasPrefix(line, "## ") {
			inReserved = false
		}
		if inReserved {
			m := reservedNo.FindStringSubmatch(line)
			if m != nil {
				set.reserved[m[1]] = true
			}
		}
	}
	return set, nil
}

// checkReferences resolves every ADR-XXXX mention under docs/ and in the root files a
// reader starts from.
func checkReferences(set *adrSet) []string {
	var problems []string
	for _, path := range markdownFiles() {
		body, err := os.ReadFile(path)
		if err != nil {
			return []string{fmt.Sprintf("%s: %v", path, err)}
		}
		seen := map[string]bool{}
		for _, m := range adrRef.FindAllStringSubmatch(string(body), -1) {
			num := m[1]
			if seen[num] {
				continue
			}
			seen[num] = true
			if set.files[num] == "" && !set.reserved[num] {
				problems = append(problems, fmt.Sprintf("%s: references ADR-%s, which is neither a file nor reserved", path, num))
			}
			if set.files[num] != "" && set.reserved[num] {
				problems = append(problems, fmt.Sprintf("%s: ADR-%s is both a file and reserved in the index", indexPath, num))
			}
		}
	}
	return problems
}

func checkRelatedExists(set *adrSet) []string {
	var problems []string
	for num, refs := range set.related {
		for _, ref := range refs {
			if set.files[ref] == "" {
				problems = append(problems, fmt.Sprintf("%s: Related names ADR-%s, which has no file", set.files[num], ref))
			}
		}
	}
	return problems
}

// checkDecidesAndIndex holds the header line and the index in step. The Decides line is
// the set's skim surface, so an ADR without one is unreadable at index speed.
func checkDecidesAndIndex(set *adrSet) []string {
	var problems []string
	index, err := os.ReadFile(indexPath)
	if err != nil {
		return []string{fmt.Sprintf("%s: %v", indexPath, err)}
	}
	indexed := map[string]bool{}
	for line := range strings.SplitSeq(string(index), "\n") {
		m := indexRow.FindStringSubmatch(line)
		if m != nil {
			indexed[m[1]] = true
			if set.files[m[1]] == "" {
				problems = append(problems, fmt.Sprintf("%s: indexes ADR-%s, which has no file", indexPath, m[1]))
			}
		}
	}
	for num, path := range set.files {
		body, err := os.ReadFile(path)
		if err != nil {
			return []string{fmt.Sprintf("%s: %v", path, err)}
		}
		hasDecides := false
		for line := range strings.SplitSeq(string(body), "\n") {
			if decidesRow.MatchString(line) {
				hasDecides = true
				break
			}
		}
		if !hasDecides {
			problems = append(problems, path+": no Decides line in the header")
		}
		if !indexed[num] {
			problems = append(problems, fmt.Sprintf("%s: ADR-%s is not in the index", indexPath, num))
		}
	}
	return problems
}

// checkComponentAgreement keeps the two adoption documents from drifting: every
// component adoption-path.md offers to remove has to be one the inventory lists.
func checkComponentAgreement() []string {
	surface, err := os.ReadFile(surfacePath)
	if err != nil {
		return []string{fmt.Sprintf("%s: %v", surfacePath, err)}
	}
	path, err := os.ReadFile(pathPath)
	if err != nil {
		return []string{fmt.Sprintf("%s: %v", pathPath, err)}
	}
	inventory := strings.ToLower(string(surface))
	var problems []string
	inBand := false
	for line := range strings.SplitSeq(string(path), "\n") {
		if strings.HasPrefix(line, "## ") {
			inBand = strings.HasPrefix(line, "## Band")
		}
		if !inBand {
			continue
		}
		m := boldCell.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		name := strings.TrimSpace(m[1])
		// A row may name a component or a posture ("Cilium's default-deny and
		// WireGuard posture"); the first word is the component either way.
		head := strings.SplitN(name, "'", 2)[0]
		head = strings.SplitN(head, " + ", 2)[0]
		if !strings.Contains(inventory, strings.ToLower(head)) {
			problems = append(problems, fmt.Sprintf("%s: names %q, which %s does not list", pathPath, head, surfacePath))
		}
	}
	return problems
}

func checkDeferralCoverage(set *adrSet) []string {
	body, err := os.ReadFile(deferPath)
	if err != nil {
		return []string{fmt.Sprintf("%s: %v", deferPath, err)}
	}
	registered := map[string]bool{}
	for line := range strings.SplitSeq(string(body), "\n") {
		if !strings.HasPrefix(line, "| ") {
			continue
		}
		for _, m := range adrRef.FindAllStringSubmatch(line, -1) {
			registered[m[1]] = true
		}
	}
	var problems []string
	for num, path := range set.files {
		adrBody, err := os.ReadFile(path)
		if err != nil {
			return []string{fmt.Sprintf("%s: %v", path, err)}
		}
		// ADR-0000 defines the Trigger field rather than deferring, and a deferral stated in prose means a registered ADR
		// without a Trigger row is not a defect.
		if num == "0000" || registered[num] {
			continue
		}
		if strings.Contains(string(adrBody), "| **Trigger** |") {
			problems = append(problems, fmt.Sprintf("%s: states a deferral with no row in %s", path, deferPath))
		}
	}
	return problems
}

// checkReadmeBoundary asserts ADR-0001's rule that nothing under docs/ links to the root
// README: a generated project rewrites that file, so the link would point at someone
// else's selection guidance.
func checkReadmeBoundary() []string {
	var problems []string
	for _, path := range markdownFiles() {
		if !strings.HasPrefix(filepath.ToSlash(path), docsDir+"/") {
			continue
		}
		body, err := os.ReadFile(path)
		if err != nil {
			return []string{fmt.Sprintf("%s: %v", path, err)}
		}
		if readme.Match(body) {
			problems = append(problems, path+": links to the root README, which a generated project rewrites")
		}
	}
	return problems
}

func markdownFiles() []string {
	var out []string
	_ = filepath.Walk(
		docsDir,
		func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() || !strings.HasSuffix(path, ".md") {
				return nil
			}
			if strings.HasSuffix(path, ".local.md") {
				return nil
			}
			out = append(out, path)
			return nil
		},
	)
	for _, root := range []string{"README.md", "AGENTS.md"} {
		_, err := os.Stat(root)
		if err == nil {
			out = append(out, root)
		}
	}
	return out
}

func failf(format string, args ...any) {
	_, _ = fmt.Fprintf(os.Stderr, "✗ "+format+"\n", args...)
	os.Exit(1)
}
