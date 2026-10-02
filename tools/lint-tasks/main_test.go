package main

import "testing"

func TestCheck(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, config, prefix string
		tasks, findings      int
	}{
		{"a command", "[tasks.build]\nrun = \"go build ./...\"\n", taskPrefix, 1, 0},
		{"a dependency", "[tasks.\"ci:test\"]\ndepends = [\"test\"]\n", taskPrefix, 1, 0},
		{"a description alone", "[tasks.seed]\ndescription = \"Seed\"\n\n[tasks.load]\nrun = \"x\"\n", taskPrefix, 2, 1},
		{"a table that is not a task", "[tools]\ngo = \"1\"\n\n[env]\nA = \"b\"\n", taskPrefix, 0, 0},
		{"an included file", "[acceptance]\ndescription = \"x\"\n\n[\"test:template\"]\nrun = \"y\"\n", "", 2, 1},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			tasks, findings := check("f.toml", c.config, c.prefix)
			if tasks != c.tasks {
				t.Errorf("tasks: got %d, want %d", tasks, c.tasks)
			}
			if len(findings) != c.findings {
				t.Errorf("findings: got %d, want %d: %v", len(findings), c.findings, findings)
			}
		})
	}
}
