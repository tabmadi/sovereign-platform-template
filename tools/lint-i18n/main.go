// Command lint-i18n enforces that the frontend is localisable (ADR-0400).
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
)

const (
	messagesDir = "apps/frontend/src/messages"
	sourceDir   = "apps/frontend/src"
)

// The physical → logical swaps, applied in order.
var logicalSwaps = []struct {
	re   *regexp.Regexp
	with string
}{
	{regexp.MustCompile(`\bml-(auto|[0-9.]+)\b`), "ms-$1"},
	{regexp.MustCompile(`\bmr-(auto|[0-9.]+)\b`), "me-$1"},
	{regexp.MustCompile(`\bpl-([0-9.]+)\b`), "ps-$1"},
	{regexp.MustCompile(`\bpr-([0-9.]+)\b`), "pe-$1"},
	{regexp.MustCompile(`\bborder-l-([0-9]+)\b`), "border-s-$1"},
	{regexp.MustCompile(`\bborder-r-([0-9]+)\b`), "border-e-$1"},
	{regexp.MustCompile(`\bborder-l\b`), "border-s"},
	{regexp.MustCompile(`\bborder-r\b`), "border-e"},
	{regexp.MustCompile(`\brounded-l-([a-z0-9]+)\b`), "rounded-s-$1"},
	{regexp.MustCompile(`\brounded-r-([a-z0-9]+)\b`), "rounded-e-$1"},
	{regexp.MustCompile(`\btext-left\b`), "text-start"},
	{regexp.MustCompile(`\btext-right\b`), "text-end"},
	{regexp.MustCompile(`\bleft-([0-9.]+)\b`), "start-$1"},
	{regexp.MustCompile(`\bright-([0-9.]+)\b`), "end-$1"},
}

// `left-1/2` and `right-1/2` are centring offsets, and mirroring them moves the element. RE2 has no negative
// lookahead, so they are protected by substitution.
var centringRe = regexp.MustCompile(`\b(left|right)-([0-9]+)/([0-9]+)\b`)

const centringSentinel = "\x00centring\x00"

// toLogical applies every swap with the centring offsets held out of reach.
func toLogical(body string) string {
	var held []string
	hold := func(match string) string {
		held = append(held, match)
		return centringSentinel
	}
	protected := centringRe.ReplaceAllStringFunc(body, hold)
	for _, swap := range logicalSwaps {
		protected = swap.re.ReplaceAllString(protected, swap.with)
	}
	for _, match := range held {
		protected = strings.Replace(protected, centringSentinel, match, 1)
	}
	return protected
}

func main() {
	fix := flag.Bool("fix", false, "apply the logical-property swaps in place")
	flag.Parse()

	problems := checkParity()
	problems = append(problems, checkLogicalProperties(*fix)...)

	if len(problems) > 0 {
		_, _ = fmt.Fprintln(os.Stderr, "✗ the frontend is not fully localisable (ADR-0400):")
		for _, p := range problems {
			_, _ = fmt.Fprintln(os.Stderr, "  "+p)
		}
		os.Exit(1)
	}
	_, _ = fmt.Fprintln(os.Stdout, "✓ message catalogues agree and the layout is direction-neutral")
}

// checkParity asserts every catalogue holds the same key paths.
func checkParity() []string {
	entries, err := os.ReadDir(messagesDir)
	if err != nil {
		failf("read %s: %v", messagesDir, err)
	}

	keysPerLocale := map[string][]string{}
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		locale := strings.TrimSuffix(entry.Name(), ".json")
		data, err := os.ReadFile(filepath.Join(messagesDir, entry.Name()))
		if err != nil {
			failf("read %s: %v", entry.Name(), err)
		}
		var parsed map[string]any
		err = json.Unmarshal(data, &parsed)
		if err != nil {
			failf("%s is not valid JSON: %v", entry.Name(), err)
		}
		keys := flatten("", parsed)
		sort.Strings(keys)
		keysPerLocale[locale] = keys
	}

	// An empty message directory is a broken enumeration, not a localised app.
	if len(keysPerLocale) < 2 {
		failf("%s holds %d catalogue(s); parity needs at least two", messagesDir, len(keysPerLocale))
	}

	locales := make([]string, 0, len(keysPerLocale))
	for locale := range keysPerLocale {
		locales = append(locales, locale)
	}
	sort.Strings(locales)

	// The first catalogue alphabetically is the reference only for REPORTING; the
	// check itself is symmetric, so neither direction of drift is missed.
	reference := locales[0]
	var problems []string
	for _, locale := range locales[1:] {
		for _, key := range keysPerLocale[reference] {
			if !slices.Contains(keysPerLocale[locale], key) {
				problems = append(problems, fmt.Sprintf("%s.json is missing %q (present in %s.json)", locale, key, reference))
			}
		}
		for _, key := range keysPerLocale[locale] {
			if !slices.Contains(keysPerLocale[reference], key) {
				problems = append(problems, fmt.Sprintf("%s.json is missing %q (present in %s.json)", reference, key, locale))
			}
		}
	}
	return problems
}

func flatten(prefix string, value map[string]any) []string {
	var keys []string
	for k, v := range value {
		path := k
		if prefix != "" {
			path = prefix + "." + k
		}
		nested, isNested := v.(map[string]any)
		if isNested {
			keys = append(keys, flatten(path, nested)...)
			continue
		}
		keys = append(keys, path)
	}
	return keys
}

func checkLogicalProperties(fix bool) []string {
	var candidates []string
	collect := func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		ext := filepath.Ext(path)
		if ext != ".tsx" && ext != ".ts" {
			return nil
		}
		candidates = append(candidates, path)
		return nil
	}
	// A read error fails the gate rather than skipping the file: a check that cannot
	// resolve its input must not report success.
	err := filepath.Walk(sourceDir, collect)
	if err != nil {
		failf("walk %s: %v", sourceDir, err)
	}

	var problems []string
	for _, path := range candidates {
		data, err := os.ReadFile(path)
		if err != nil {
			failf("read %s: %v", path, err)
		}
		body := string(data)
		patched := toLogical(body)
		if patched == body {
			continue
		}
		if fix {
			// #nosec G703 -- path comes from a walk of this repository's own source
			// tree; this is a local lint helper, not a server.
			err = os.WriteFile(path, []byte(patched), 0o600)
			if err != nil {
				failf("write %s: %v", path, err)
			}
			continue
		}
		// Name the offending lines rather than the file: "this file has a physical
		// property somewhere" is a message that costs a grep to act on.
		for i, before := range strings.Split(body, "\n") {
			if toLogical(before) != before {
				const form = "%s:%d: physical property does not mirror; run `mise run lint:i18n -- -fix`"
				problems = append(problems, fmt.Sprintf(form, path, i+1))
			}
		}
	}
	sort.Strings(problems)
	return problems
}

func failf(format string, args ...any) {
	_, _ = fmt.Fprintf(os.Stderr, "✗ "+format+"\n", args...)
	os.Exit(1)
}
