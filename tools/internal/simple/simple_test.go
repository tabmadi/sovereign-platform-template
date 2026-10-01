package simple

import "testing"

func TestCheck(t *testing.T) {
	t.Parallel()
	opts := Options{English: true, WordSlash: true, MaxWords: MaxWords}
	cases := []struct {
		text string
		rule string
	}{
		{"The gate runs in CI; it blocks a merge.", ruleSemicolon},
		{"The gate runs in CI (see the workflow).", "parentheses"},
		{"Is the pod running?", "question mark"},
		{"Keys & secrets live in OpenBao.", "ampersand"},
		{`The value is "true".`, "quote mark"},
		{"The step is slow - it pulls the image.", "dash"},
		{"Use Go/TypeScript for services.", ruleSlash},
		{"Do not use it, e.g. in tests.", "abbreviation"},
		{"The pod doesn't restart.", "contraction"},
		{"The gateway utilizes a cache.", "complex word"},
		{"The step is slow \u2014 it pulls the image.", "banned character"},
		{
			"one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen" +
				" seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five" +
				" twenty-six.",
			"long sentence",
		},
	}
	for _, c := range cases {
		if !has(Check(c.text, opts), c.rule) {
			t.Errorf("%q: no %s finding", c.text, c.rule)
		}
	}
}

func TestCheckPasses(t *testing.T) {
	t.Parallel()
	opts := Options{English: true, WordSlash: true, MaxWords: MaxWords}
	for _, text := range []string{
		"The platform's gate runs in CI. It blocks a merge, per ADR-0102.",
		"Call run() before the check. The value a != b holds.",
		"A read-only replica serves the query: it never takes a write.",
		"CI/CD and I/O are technical names.",
	} {
		got := Check(StripCode(text), opts)
		if len(got) > 0 {
			t.Errorf("%q: unexpected findings %v", text, got)
		}
	}
}

func TestStripMarkdown(t *testing.T) {
	t.Parallel()
	got := StripMarkdown("- The rule holds, per [ADR-0204](0204-resource-management.md). `(CI: lint:x)`")
	want := "The rule holds, per ADR-0204."
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func has(findings []Finding, rule string) bool {
	for _, f := range findings {
		if f.Rule == rule {
			return true
		}
	}
	return false
}
