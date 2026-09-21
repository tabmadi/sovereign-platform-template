// Command shared-components gives every service spec the canonical definition of each shared component it uses
// (ADR-0303).
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

const sourceFile = "tools/codegen/shared-components.yaml"

const (
	beginFmt = "# >>> shared-components: %s — generated from tools/codegen/shared-components.yaml, do not edit"
	endMark  = "# <<< shared-components"
)

// refPattern matches a local component reference. Local is the whole story here:
// a spec has no external refs, which is the property the copying buys.
var refPattern = regexp.MustCompile(`#/components/(schemas|responses)/([A-Za-z0-9_.-]+)`)

// section is one spliced region: a key under `components` and the source mapping
// holding every component that region can carry.
type section struct {
	key  string // "schemas" or "responses"
	node *yaml.Node
}

// loadSource reads the canonical fragment.
func loadSource() ([]section, error) {
	shared, err := repo.ReadYAML[struct {
		Schemas   yaml.Node `yaml:"schemas"`
		Responses yaml.Node `yaml:"responses"`
	}](sourceFile)
	if err != nil {
		return nil, err
	}
	return []section{
		{"schemas", &shared.Schemas},
		{"responses", &shared.Responses},
	}, nil
}

// blocksFor renders the region each section contributes to one spec: the shared
// components that spec reaches, in source order.
func blocksFor(sections []section, spec string) (map[string]string, error) {
	keep, err := reachable(sections, spec)
	if err != nil {
		return nil, err
	}
	blocks := make(map[string]string, len(sections))
	for _, sec := range sections {
		blocks[sec.key], err = renderMap(filterMap(sec.node, sec.key, keep))
		if err != nil {
			return nil, err
		}
	}
	return blocks, nil
}

// reachable is the set of shared components a spec points at, closed over their own references. The seed ignores the
// spliced regions: a component is carried because the spec needs it.
func reachable(sections []section, spec string) (map[string]bool, error) {
	byName := make(map[string]*yaml.Node)
	for _, sec := range sections {
		for name, node := range mapEntries(sec.node) {
			byName[sec.key+"/"+name] = node
		}
	}

	doc, err := readSpec(spec)
	if err != nil {
		return nil, err
	}
	pending := refsIn(stripRegions(doc))
	seen := make(map[string]bool, len(pending))
	for len(pending) > 0 {
		ref := pending[len(pending)-1]
		pending = pending[:len(pending)-1]
		node, shared := byName[ref]
		if seen[ref] || !shared {
			continue
		}
		seen[ref] = true
		rendered, err := renderNode(node)
		if err != nil {
			return nil, err
		}
		pending = append(pending, refsIn(rendered)...)
	}
	return seen, nil
}

// refsIn collects the component references in a chunk of YAML text.
func refsIn(doc string) []string {
	matches := refPattern.FindAllStringSubmatch(doc, -1)
	out := make([]string, 0, len(matches))
	for _, m := range matches {
		out = append(out, m[1]+"/"+m[2])
	}
	return out
}

// stripRegions removes the spliced regions, leaving the spec's own content.
func stripRegions(doc string) string {
	var out []string
	inRegion := false
	for line := range strings.SplitSeq(doc, "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(trimmed, "# >>> shared-components:"):
			inRegion = true
		case inRegion && trimmed == endMark:
			inRegion = false
		case !inRegion:
			out = append(out, line)
		}
	}
	return strings.Join(out, "\n")
}

func main() {
	lint.Main("shared components have drifted from "+sourceFile, run)
}

func run(r *lint.Report) error {
	check := flag.Bool("check", false, "fail on drift instead of rewriting")
	flag.Parse()

	sections, err := loadSource()
	if err != nil {
		return err
	}
	specs, err := repo.Glob(filepath.Join("services", "*", "openapi.yaml"))
	if err != nil {
		return err
	}
	if len(specs) == 0 {
		return errors.New("no service specs found")
	}

	var written []string
	for _, spec := range specs {
		blocks, err := blocksFor(sections, spec)
		if err != nil {
			return fmt.Errorf("%s: %w", spec, err)
		}
		changed, err := apply(spec, sections, blocks, *check)
		if err != nil {
			return fmt.Errorf("%s: %w", spec, err)
		}
		if !changed {
			continue
		}
		if *check {
			r.Addf("%s", spec)
			continue
		}
		written = append(written, spec)
	}

	r.Hintf("Run `mise run gen:shared-components` and commit the result.")
	if *check {
		r.Okf("%d specs carry the canonical form of every shared component they use", len(specs))
		return nil
	}
	r.Okf("shared components written to %d spec(s)", len(written))
	return nil
}

// apply splices every section into one spec. It reports whether the file changed.
func apply(spec string, sections []section, blocks map[string]string, dryRun bool) (bool, error) {
	original, err := readSpec(spec)
	if err != nil {
		return false, err
	}
	updated := original
	for _, sec := range sections {
		updated, err = splice(updated, sec.key, blocks[sec.key])
		if err != nil {
			return false, fmt.Errorf("%s: %w", sec.key, err)
		}
	}
	if updated == original {
		return false, nil
	}
	if dryRun {
		return true, nil
	}
	// The write target is rebuilt from a validated service name rather than reusing
	// the globbed path, so the only thing this tool can write is a service spec.
	target, err := specPath(spec)
	if err != nil {
		return false, err
	}
	// 0o600 matches the other generators here (tools/adr-rules, tools/admin-gen);
	// git carries the tracked mode, so the bits set on write do not survive a clone.
	err = os.WriteFile(target, []byte(updated), 0o600)
	if err != nil {
		return false, fmt.Errorf("write: %w", err)
	}
	return true, nil
}

// specPath rebuilds services/<name>/openapi.yaml from the service name in the
// given path, rejecting anything that is not exactly that shape.
func specPath(spec string) (string, error) {
	cleaned := filepath.Clean(spec)
	dir, file := filepath.Split(cleaned)
	if file != "openapi.yaml" {
		return "", fmt.Errorf("not a service spec: %s", spec)
	}
	parent, name := filepath.Split(filepath.Clean(dir))
	if filepath.Clean(parent) != "services" || name == "" || strings.ContainsAny(name, `/\.`) {
		return "", fmt.Errorf("not a service spec: %s", spec)
	}
	return filepath.Join("services", name, "openapi.yaml"), nil
}

// splice replaces the sentinel-delimited region for one section. A spec with no sentinels is an error, not a silent
// skip: it is not wired to the shared source at all.
func splice(doc, key, block string) (string, error) {
	begin := fmt.Sprintf(beginFmt, key)
	lines := strings.Split(doc, "\n")

	startIdx, endIdx, indent := -1, -1, ""
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if startIdx < 0 && trimmed == begin {
			startIdx = i
			indent = line[:len(line)-len(strings.TrimLeft(line, " "))]
			continue
		}
		if startIdx >= 0 && trimmed == endMark {
			endIdx = i
			break
		}
	}
	if startIdx < 0 {
		return "", fmt.Errorf("no %q sentinel — add it under components.%s", begin, key)
	}
	if endIdx < 0 {
		return "", fmt.Errorf("%q sentinel is not closed by %q", begin, endMark)
	}

	var out []string
	out = append(out, lines[:startIdx+1]...)
	for l := range strings.SplitSeq(strings.TrimRight(block, "\n"), "\n") {
		if l == "" {
			out = append(out, "")
			continue
		}
		out = append(out, indent+l)
	}
	out = append(out, lines[endIdx:]...)
	return strings.Join(out, "\n"), nil
}

// renderMap emits a mapping node's entries as YAML, without the wrapping key.
func renderMap(n *yaml.Node) (string, error) {
	if n == nil || n.Kind != yaml.MappingNode || len(n.Content) == 0 {
		return "", nil
	}
	return renderNode(n)
}

func renderNode(n *yaml.Node) (string, error) {
	var b strings.Builder
	enc := yaml.NewEncoder(&b)
	enc.SetIndent(2)
	err := enc.Encode(n)
	if err != nil {
		return "", fmt.Errorf("render: %w", err)
	}
	_ = enc.Close()
	return b.String(), nil
}

// filterMap copies a mapping node down to the kept entries, in source order. The
// key node carries the leading comment, so a kept component keeps its rationale.
func filterMap(n *yaml.Node, key string, keep map[string]bool) *yaml.Node {
	if n.Kind != yaml.MappingNode {
		return nil
	}
	out := *n
	out.Content = nil
	for i := 0; i+1 < len(n.Content); i += 2 {
		if keep[key+"/"+n.Content[i].Value] {
			out.Content = append(out.Content, n.Content[i], n.Content[i+1])
		}
	}
	return &out
}

// mapEntries yields a mapping node's entries by name.
func mapEntries(n *yaml.Node) map[string]*yaml.Node {
	out := make(map[string]*yaml.Node)
	if n.Kind != yaml.MappingNode {
		return out
	}
	for i := 0; i+1 < len(n.Content); i += 2 {
		out[n.Content[i].Value] = n.Content[i+1]
	}
	return out
}

func readSpec(spec string) (string, error) {
	b, err := repo.Read(spec)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
