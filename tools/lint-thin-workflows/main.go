// Command lint-thin-workflows enforces that workflow YAML checks out, sets up the toolchain, and calls `mise run
// ci:*` (ADR-0102).
package main

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

// A finding is one offending line inside one run: block.
type finding struct {
	file string
	line int
	text string
}

func main() {
	lint.Main("workflow steps carry pipeline logic (ADR-0102)", run)
}

func run(r *lint.Report) error {
	files, err := workflowFiles()
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return errors.New("no workflow files found under .github/")
	}
	for _, f := range files {
		findings, err := check(f)
		if err != nil {
			return fmt.Errorf("%s: %w", f, err)
		}
		for _, finding := range findings {
			r.Addf("%s:%d: %s", finding.file, finding.line, finding.text)
		}
	}
	r.Hintf("Move the logic into a mise task and call it from the step.")
	r.Okf("workflow steps call mise tasks (%d files)", len(files))
	return nil
}

func workflowFiles() ([]string, error) {
	var out []string
	for _, pattern := range []string{
		filepath.Join(".github", "workflows", "*.yml"),
		filepath.Join(".github", "workflows", "*.yaml"),
		filepath.Join(".github", "actions", "*", "action.yml"),
		filepath.Join(".github", "actions", "*", "action.yaml"),
	} {
		m, err := repo.Glob(pattern)
		if err != nil {
			return nil, err
		}
		out = append(out, m...)
	}
	return out, nil
}

func check(path string) ([]finding, error) {
	root, err := repo.ReadYAML[yaml.Node](path)
	if err != nil {
		return nil, err
	}

	var findings []finding
	// script.Line is the line of the scalar's first content line for a block
	// scalar, which is what makes the offsets below point at the real source.
	collect := func(script *yaml.Node) {
		for i, line := range strings.Split(script.Value, "\n") {
			bad := offending(line)
			if bad != "" {
				findings = append(findings, finding{path, script.Line + i, bad})
			}
		}
	}
	walk(&root, collect)
	return findings, nil
}

// walk calls fn with the script of every step under a `steps:` sequence. Scoping
// to steps matters: a reusable workflow may declare an output literally named
// `run`, which is a value rather than a script.
func walk(n *yaml.Node, fn func(*yaml.Node)) {
	if n.Kind == yaml.MappingNode {
		for i := 0; i+1 < len(n.Content); i += 2 {
			if n.Content[i].Value != "steps" || n.Content[i+1].Kind != yaml.SequenceNode {
				continue
			}
			for _, step := range n.Content[i+1].Content {
				if step.Kind != yaml.MappingNode {
					continue
				}
				for j := 0; j+1 < len(step.Content); j += 2 {
					if step.Content[j].Value == "run" && step.Content[j+1].Kind == yaml.ScalarNode {
						fn(step.Content[j+1])
					}
				}
			}
		}
	}
	for _, c := range n.Content {
		walk(c, fn)
	}
}

// offending returns the trimmed line if it is logic, or "" if it is permitted.
func offending(line string) string {
	s := strings.TrimSpace(line)
	if s == "" || strings.HasPrefix(s, "#") || s == "set -euo pipefail" {
		return ""
	}
	// A forge step-output redirect is plumbing; strip it before judging the command.
	for _, sink := range []string{`>> "$GITHUB_OUTPUT"`, `>> "$GITHUB_ENV"`} {
		cut, found := strings.CutSuffix(s, sink)
		if found {
			s = strings.TrimSpace(cut)
			break
		}
	}
	if strings.HasPrefix(s, "mise run ") {
		return ""
	}
	return strings.TrimSpace(line)
}
