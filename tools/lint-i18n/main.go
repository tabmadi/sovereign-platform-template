// Command lint-i18n checks that the frontend can be localised, per ADR-0400.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

const (
	messagesDir = "apps/frontend/src/messages"
	sourceDir   = "apps/frontend/src"
)

// The physical to logical swaps. Each one matches a whole utility, so `slide-in-from-right-2` and the centring
// offset `left-1/2` stay as they are.
var logicalSwaps = []struct {
	re   *regexp.Regexp
	with string
}{
	{regexp.MustCompile(`^ml-(auto|[0-9.]+)$`), "ms-$1"},
	{regexp.MustCompile(`^mr-(auto|[0-9.]+)$`), "me-$1"},
	{regexp.MustCompile(`^pl-([0-9.]+)$`), "ps-$1"},
	{regexp.MustCompile(`^pr-([0-9.]+)$`), "pe-$1"},
	{regexp.MustCompile(`^border-l-([0-9]+)$`), "border-s-$1"},
	{regexp.MustCompile(`^border-r-([0-9]+)$`), "border-e-$1"},
	{regexp.MustCompile(`^border-l$`), "border-s"},
	{regexp.MustCompile(`^border-r$`), "border-e"},
	{regexp.MustCompile(`^rounded-l-([a-z0-9]+)$`), "rounded-s-$1"},
	{regexp.MustCompile(`^rounded-r-([a-z0-9]+)$`), "rounded-e-$1"},
	{regexp.MustCompile(`^text-left$`), "text-start"},
	{regexp.MustCompile(`^text-right$`), "text-end"},
	{regexp.MustCompile(`^left-([0-9.]+)$`), "start-$1"},
	{regexp.MustCompile(`^right-([0-9.]+)$`), "end-$1"},
}

// A class token: the text between spaces, quotes, and braces.
var tokenRe = regexp.MustCompile("[^\\s\"'`{}]+")

// physicalSideRe is a variant for a physical placement, such as the side that a popover opened on. A class under it
// names that physical side on purpose, and mirroring it points the element the wrong way in a right-to-left layout.
var physicalSideRe = regexp.MustCompile(`side=(left|right)\]`)

// toLogical applies the swaps to every class token.
func toLogical(body string) string {
	return tokenRe.ReplaceAllStringFunc(body, logicalToken)
}

// logicalToken swaps the utility of one token, after its variants and its `-` or `!` modifiers.
func logicalToken(token string) string {
	cut := variantEnd(token)
	variants, utility := token[:cut], token[cut:]
	if physicalSideRe.MatchString(variants) {
		return token
	}
	core := strings.TrimLeft(utility, "-!")
	lead := utility[:len(utility)-len(core)]
	for _, swap := range logicalSwaps {
		if swap.re.MatchString(core) {
			return variants + lead + swap.re.ReplaceAllString(core, swap.with)
		}
	}
	return token
}

// variantEnd is the index after the last variant colon that is outside square brackets.
func variantEnd(token string) int {
	depth, end := 0, 0
	for i, c := range token {
		switch c {
		case '[':
			depth++
		case ']':
			depth--
		case ':':
			if depth == 0 {
				end = i + 1
			}
		}
	}
	return end
}

func main() {
	lint.Main("the frontend is not fully localisable, per ADR-0400", run)
}

func run(r *lint.Report) error {
	fix := flag.Bool("fix", false, "apply the logical-property swaps in place")
	flag.Parse()

	parity, err := checkParity()
	if err != nil {
		return err
	}
	r.Add(parity...)
	logical, err := checkLogicalProperties(*fix)
	if err != nil {
		return err
	}
	r.Add(logical...)
	r.Okf("message catalogues agree and the layout is direction-neutral")
	return nil
}

// checkParity checks that every catalogue holds the same key paths.
func checkParity() ([]string, error) {
	entries, err := os.ReadDir(messagesDir)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", messagesDir, err)
	}

	keysPerLocale := map[string][]string{}
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		locale := strings.TrimSuffix(entry.Name(), ".json")
		parsed, err := repo.ReadJSON[map[string]any](filepath.Join(messagesDir, entry.Name()))
		if err != nil {
			return nil, err
		}
		keys := flatten("", parsed)
		sort.Strings(keys)
		keysPerLocale[locale] = keys
	}

	// An empty message directory is a broken enumeration, not a localised app.
	if len(keysPerLocale) < 2 {
		return nil, fmt.Errorf("%s holds %d catalogue(s), and parity needs at least two", messagesDir, len(keysPerLocale))
	}

	locales := make([]string, 0, len(keysPerLocale))
	for locale := range keysPerLocale {
		locales = append(locales, locale)
	}
	sort.Strings(locales)

	// The first catalogue in alphabetical order is the reference only for the report.
	// The check itself is symmetric, so it finds drift in both directions.
	reference := locales[0]
	var problems []string
	for _, locale := range locales[1:] {
		for _, key := range keysPerLocale[reference] {
			if !slices.Contains(keysPerLocale[locale], key) {
				problems = append(problems, fmt.Sprintf("%s.json is missing %q, which is in %s.json", locale, key, reference))
			}
		}
		for _, key := range keysPerLocale[locale] {
			if !slices.Contains(keysPerLocale[reference], key) {
				problems = append(problems, fmt.Sprintf("%s.json is missing %q, which is in %s.json", reference, key, locale))
			}
		}
	}
	return problems, nil
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

func checkLogicalProperties(fix bool) ([]string, error) {
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
	// A read error fails the gate and does not skip the file: a check that cannot resolve its input must not report
	// success.
	err := filepath.Walk(sourceDir, collect)
	if err != nil {
		return nil, fmt.Errorf("walk %s: %w", sourceDir, err)
	}

	var problems []string
	for _, path := range candidates {
		data, err := repo.Read(path)
		if err != nil {
			return nil, err
		}
		body := string(data)
		patched := toLogical(body)
		if patched == body {
			continue
		}
		if fix {
			// path comes from a walk of this repository's own source tree, and this is a local lint helper, not a server.
			// #nosec G703
			err = os.WriteFile(path, []byte(patched), 0o600)
			if err != nil {
				return nil, fmt.Errorf("write %s: %w", path, err)
			}
			continue
		}
		// Name the lines, not only the file. A message that names only the file costs a grep to act on.
		for i, before := range strings.Split(body, "\n") {
			if toLogical(before) != before {
				const form = "%s:%d: physical property does not mirror. Run `mise run lint:i18n -- -fix`"
				problems = append(problems, fmt.Sprintf(form, path, i+1))
			}
		}
	}
	return problems, nil
}
