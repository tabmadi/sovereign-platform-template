package main

import (
	"testing"
	"time"
)

func TestCheck(t *testing.T) {
	t.Parallel()
	pins := map[string]string{
		".mise.toml": "[tools]\ncosign = \"2.4.1\"\n",
		"Chart.yaml": "dependencies:\n  - name: traefik\n    version: \"37.1.0\"\n",
	}
	read := func(path string) (string, bool) {
		c, ok := pins[path]
		return c, ok
	}
	now := time.Date(2026, 10, 29, 0, 0, 0, 0, time.UTC)
	cases := []struct {
		name, content     string
		markers, findings int
	}{
		{"no marker", "# A plain comment.\nkey: value\n", 0, 0},
		{"a matching pin", "# Workaround for cosign 2.4.1 in .mise.toml: it drops the tag. Retest: sign once.\n", 1, 0},
		{"a pin in backticks", "# Workaround for cosign 2.4.1 in `.mise.toml`: it drops the tag.\n# Retest: once.\n", 1, 0},
		{"a later line", "// Workaround for traefik 37.1.0 in Chart.yaml: probes time out. Retest: once.\n", 1, 0},
		{"a bumped pin", "# Workaround for cosign 2.3.0 in .mise.toml: it drops the tag. Retest: sign once.\n", 1, 1},
		{"a name the pin file lacks", "# Workaround for zot 2.1.0 in .mise.toml: it stalls. Retest: pull once.\n", 1, 1},
		{"an untracked pin file", "# Workaround for zot 2.1.0 in infra/zot.yaml: it stalls. Retest: pull once.\n", 1, 1},
		{"no retest", "# Workaround for cosign 2.4.1 in .mise.toml: it drops the tag.\nkey: value\n", 1, 1},
		{"a recent check", "# Workaround for mirror.gcr.io, checked 2026-09: it stalls. Retest: pull through it.\n", 1, 0},
		{"an overdue check", "# Workaround for mirror.gcr.io, checked 2025-09: it stalls. Retest: pull through it.\n", 1, 1},
		{"a malformed marker", "# Workaround for zot: it stalls. Retest: pull once.\n", 1, 1},
		{"the word in prose", "# This is not a workaround for zot.\n", 0, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			markers, findings := check("f", c.content, now, read)
			if markers != c.markers {
				t.Errorf("markers: got %d, want %d", markers, c.markers)
			}
			if len(findings) != c.findings {
				t.Errorf("findings: got %d, want %d: %v", len(findings), c.findings, findings)
			}
		})
	}
}
