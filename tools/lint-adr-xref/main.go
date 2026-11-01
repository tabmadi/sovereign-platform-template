// Command lint-adr-xref checks the two cross-references of this template that tablint has no rule for: the
// adoption documents name the same components, and every deferral has a register row.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
)

const (
	adrDir      = "docs/adr"
	surfacePath = "docs/operational-surface.md"
	deferPath   = "docs/reference/deferral-register.md"
	pathPath    = "docs/adoption-path.md"
)

var (
	adrRef  = regexp.MustCompile(`ADR-(\d{4})`)
	adrFile = regexp.MustCompile(`^(\d{4})-[a-z0-9-]+\.md$`)
	// Both inventory documents name a component with a bold first table cell.
	boldCell = regexp.MustCompile(`^\| \*\*([^*|]+)\*\*`)
)

func main() {
	lint.Main("ADR cross-references do not hold", run)
}

func run(r *lint.Report) error {
	files, err := adrFiles()
	if err != nil {
		return err
	}
	r.Add(checkComponentAgreement()...)
	r.Add(checkDeferralCoverage(files)...)
	r.Okf("the adoption documents and the deferral register agree with %d ADRs", len(files))
	return nil
}

// adrFiles maps each ADR number to its path.
func adrFiles() (map[string]string, error) {
	entries, err := os.ReadDir(adrDir)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", adrDir, err)
	}
	files := map[string]string{}
	for _, e := range entries {
		m := adrFile.FindStringSubmatch(e.Name())
		if m != nil {
			files[m[1]] = filepath.Join(adrDir, e.Name())
		}
	}
	return files, nil
}

// checkComponentAgreement keeps the two adoption documents from drifting apart.
// Every component that adoption-path.md offers to remove must be one that the inventory lists.
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
		// A row can name a component or a posture, such as `Cilium's default-deny and WireGuard posture`.
		// In both cases the first word is the component.
		head := strings.SplitN(name, "'", 2)[0]
		head = strings.SplitN(head, " + ", 2)[0]
		if !strings.Contains(inventory, strings.ToLower(head)) {
			problems = append(problems, fmt.Sprintf("%s: names %q, which %s does not list", pathPath, head, surfacePath))
		}
	}
	return problems
}

func checkDeferralCoverage(files map[string]string) []string {
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
	for num, path := range files {
		adrBody, err := os.ReadFile(path)
		if err != nil {
			return []string{fmt.Sprintf("%s: %v", path, err)}
		}
		// ADR-0000 defines the Trigger field and does not defer. A deferral stated in prose means that a registered ADR
		// with no Trigger row is not a defect.
		if num == "0000" || registered[num] {
			continue
		}
		if strings.Contains(string(adrBody), "| **Trigger** |") {
			problems = append(problems, fmt.Sprintf("%s: states a deferral with no row in %s", path, deferPath))
		}
	}
	return problems
}
