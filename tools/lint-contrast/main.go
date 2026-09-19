// Command lint-contrast checks colour contrast against the design-token file
// rather than per component (ADR-0400).
//
// The reason it is not a per-component check: a token change moves every surface
// at once, so the token file is where a contrast regression is introduced and where
// it is cheapest to catch. axe still scans the rendered pages (test/e2e), and that
// catches composition mistakes this cannot see — a foreground applied over a
// background the naming convention does not pair it with.
//
// The pairing comes from the token names, which is what makes this mechanical
// rather than a hand-maintained list. shadcn/ui names every role as a couple:
//
//	--<role>-foreground   over  --<role>
//	--foreground          over  --background
//
// Three roles are also checked against surfaces their name does not state, because
// that is where they are actually used: page text and secondary text both appear on
// the card surface, and `text-destructive` is applied over the page rather than over
// `--destructive`, which is a fill. Those pairs are listed in extraPairs.
//
// Thresholds follow the success criteria rather than the visual hierarchy. SC 1.4.3
// applies to ALL text at 4.5:1 — low prominence is not an exception the criterion
// grants. Borders and focus rings are non-text and take SC 1.4.11's 3:1. Disabled
// states are the one genuine exemption 1.4.3 names: an inactive user-interface
// component is incidental.
//
// Both the light palette and the .dark block are checked. A theme that only
// conforms in one mode conforms in neither, since the user picks.
//
// A pair that cannot be resolved to two concrete colours is a hard failure, never a
// skip. An earlier version skipped them, and silently checked three pairs out of
// forty-five — a gate that reports success while measuring nothing is worse than no
// gate. For the same reason a mode whose palette parses empty fails outright.
package main

import (
	"fmt"
	"math"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

const themeFile = "apps/frontend/src/styles/theme.css"

const (
	thresholdText = 4.5 // WCAG 2.2 SC 1.4.3, normal text
	thresholdUI   = 3.0 // WCAG 2.2 SC 1.4.11, non-text contrast
)

// The two surfaces a role can be rendered on regardless of its own name: the page
// and anything raised off it.
const (
	surfacePage = "--background"
	surfaceCard = "--card"
)

// The pairs whose foreground is not named for the surface it sits on. Each is a
// place the design system puts a role that its name does not predict.
var extraPairs = []pair{
	{fg: "--foreground", bg: surfaceCard},
	{fg: "--muted-foreground", bg: surfacePage},
	{fg: "--muted-foreground", bg: surfaceCard},
	{fg: "--destructive", bg: surfacePage},
	{fg: "--destructive", bg: surfaceCard},
}

// Non-text roles, at SC 1.4.11's 3:1 against the page.
//
// `--input` and `--ring` are here because each is the ONLY visual information
// identifying something: the boundary of a form control, and which control has
// focus. 1.4.11 is about exactly that.
//
// `--border` is deliberately NOT here. It draws card edges, table rules and
// separators — decoration, and never the sole indicator of a component or a state,
// which is the boundary 1.4.11 draws. Scoring it would force every divider in the
// product to near-3:1 and the surfaces would read as a wireframe.
var nonTextPairs = []pair{
	{fg: "--ring", bg: surfacePage},
	{fg: "--input", bg: surfacePage},
}

// Disabled states are incidental under SC 1.4.3's own exception for an inactive
// user-interface component, so they are not scored at all.
var exemptMarkers = []string{"disabled"}

type rgb struct{ r, g, b float64 }

// pair is a foreground token and the surface token it is rendered on.
type pair struct{ fg, bg string }

// CSS keywords a token may be declared as rather than a value.
var baseColors = map[string]rgb{
	"--white": {1, 1, 1},
	"--black": {0, 0, 0},
}

var (
	declRe  = regexp.MustCompile(`(?m)^\s*(--[a-z0-9-_]+)\s*:\s*([^;]+);`)
	varRe   = regexp.MustCompile(`var\(\s*(--[a-z0-9-_]+)\s*\)`)
	rgbRe   = regexp.MustCompile(`rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)`)
	oklchRe = regexp.MustCompile(`oklch\(\s*([0-9.]+)%?\s+([0-9.]+)\s+([0-9.]+)`)
	hexRe   = regexp.MustCompile(`^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$`)
	// The dark palette's selector, as next-themes writes it onto <html>.
	darkSelectorRe = regexp.MustCompile(`(?m)^\.dark\b`)
)

func main() {
	data, err := os.ReadFile(themeFile)
	if err != nil {
		failf("read %s: %v", themeFile, err)
	}
	light, dark := split(string(data))

	var problems []string
	checked := 0
	for _, mode := range []struct {
		name   string
		tokens map[string]string
	}{
		{"light", parse(light)},
		{"dark", parse(dark)},
	} {
		if len(mode.tokens) == 0 {
			failf("%s: no colour tokens found in the %s palette", themeFile, mode.name)
		}
		found, probs := checkMode(mode.name, mode.tokens)
		checked += found
		problems = append(problems, probs...)
	}

	if len(problems) > 0 {
		_, _ = fmt.Fprintf(os.Stderr, "✗ design tokens fail WCAG 2.2 AA contrast (ADR-0400):\n")
		for _, p := range problems {
			_, _ = fmt.Fprintln(os.Stderr, "  "+p)
		}
		os.Exit(1)
	}
	_, _ = fmt.Fprintf(os.Stdout, "✓ %d token pairs meet WCAG 2.2 AA contrast\n", checked)
}

// checkMode derives the pairs from the token names and returns the failures.
func checkMode(mode string, tokens map[string]string) (int, []string) {
	var problems []string
	checked := 0

	for _, p := range pairsFor(tokens) {
		if isExempt(p.fg) || isExempt(p.bg) {
			continue
		}
		fg, okFG := resolve(tokens, p.fg)
		if !okFG {
			problems = append(problems, fmt.Sprintf("%s: %s does not resolve to a colour", mode, p.fg))
			continue
		}
		bg, okBG := resolve(tokens, p.bg)
		if !okBG {
			problems = append(problems, fmt.Sprintf("%s: %s does not resolve to a colour", mode, p.bg))
			continue
		}

		want := thresholdText
		criterion := "1.4.3 normal text"
		if slices.Contains(nonTextPairs, p) {
			want = thresholdUI
			criterion = "1.4.11 non-text"
		}

		checked++
		got := contrast(fg, bg)
		if got < want {
			const form = "%s: %s on %s is %.2f:1, below %.1f:1 (SC %s)"
			problems = append(problems, fmt.Sprintf(form, mode, p.fg, p.bg, got, want, criterion))
		}
	}
	return checked, problems
}

// pairsFor lists every pair to score: one per declared `--<role>-foreground`
// couple, plus the two fixed tables. A role declared without its surface (or the
// reverse) yields no pair here and is caught by the couple check below.
func pairsFor(tokens map[string]string) []pair {
	pairs := []pair{{fg: "--foreground", bg: surfacePage}}
	for name := range tokens {
		// `--color-*` are the @theme aliases that map Tailwind's utility namespace
		// onto the roles below them. They hold a var() reference, not a value, and
		// scoring them would score every role twice under a second name.
		if strings.HasPrefix(name, "--color-") {
			continue
		}
		surface, isCouple := strings.CutSuffix(name, "-foreground")
		if !isCouple || surface == "-" || surface == "" {
			continue
		}
		pairs = append(pairs, pair{fg: name, bg: surface})
	}
	pairs = append(pairs, extraPairs...)
	pairs = append(pairs, nonTextPairs...)

	// Deterministic order, so the failure list reads the same on every run.
	byPair := func(a, b pair) int {
		if a.fg != b.fg {
			return strings.Compare(a.fg, b.fg)
		}
		return strings.Compare(a.bg, b.bg)
	}
	slices.SortFunc(pairs, byPair)
	return slices.Compact(pairs)
}

func isExempt(name string) bool {
	for _, m := range exemptMarkers {
		if strings.Contains(name, m) {
			return true
		}
	}
	return false
}

// split separates the light palette from the .dark override block. The dark palette
// is the light one with the overrides applied, because .dark only restates what
// changes — a role it forgets keeps its light value, and the pair it then forms is
// what fails here.
func split(css string) (string, string) {
	// The SELECTOR, anchored to the start of a line: the string ".dark" also appears
	// in prose in this file, and matching that silently truncates the light palette
	// to nothing.
	loc := darkSelectorRe.FindStringIndex(css)
	if loc == nil {
		return css, css
	}
	light := css[:loc[0]]
	return light, light + css[loc[0]:]
}

// parse collects every custom-property declaration. A later declaration wins, which
// is what makes the dark block override the light one. Non-colour properties come
// along (--radius, --font-sans); nothing asks them for a colour, and filtering by
// value would be a second guess at which of them is a colour.
func parse(css string) map[string]string {
	out := map[string]string{}
	for _, m := range declRe.FindAllStringSubmatch(css, -1) {
		out[m[1]] = strings.TrimSpace(m[2])
	}
	return out
}

// resolve follows var() indirection to a concrete colour. The depth cap is a cycle
// guard: a token file with a reference loop should fail the lint, not hang it.
func resolve(tokens map[string]string, name string) (rgb, bool) {
	c, ok := baseColors[name]
	if ok {
		return c, true
	}
	value, declared := tokens[name]
	if !declared {
		return rgb{}, false
	}
	for range 16 {
		m := varRe.FindStringSubmatch(value)
		if m == nil {
			return parseColor(value)
		}
		base, isBase := baseColors[m[1]]
		if isBase {
			return base, true
		}
		next, found := tokens[m[1]]
		if !found {
			return rgb{}, false
		}
		value = strings.TrimSpace(next)
	}
	return rgb{}, false
}

func parseColor(value string) (rgb, bool) {
	value = strings.TrimSpace(value)
	m := rgbRe.FindStringSubmatch(value)
	if m != nil {
		r, _ := strconv.ParseFloat(m[1], 64)
		g, _ := strconv.ParseFloat(m[2], 64)
		b, _ := strconv.ParseFloat(m[3], 64)
		return rgb{r / 255, g / 255, b / 255}, true
	}
	m = oklchRe.FindStringSubmatch(value)
	if m != nil {
		l, _ := strconv.ParseFloat(m[1], 64)
		c, _ := strconv.ParseFloat(m[2], 64)
		h, _ := strconv.ParseFloat(m[3], 64)
		if strings.Contains(value, "%") {
			l /= 100
		}
		return oklchToSRGB(l, c, h), true
	}
	if hexRe.MatchString(value) {
		h := strings.TrimPrefix(value, "#")
		if len(h) == 3 {
			h = string([]byte{h[0], h[0], h[1], h[1], h[2], h[2]})
		}
		n, err := strconv.ParseUint(h, 16, 32)
		if err != nil {
			return rgb{}, false
		}
		return rgb{
			float64((n>>16)&0xff) / 255,
			float64((n>>8)&0xff) / 255,
			float64(n&0xff) / 255,
		}, true
	}
	return rgb{}, false
}

// oklchToSRGB converts OKLCH to gamma-encoded sRGB. Tailwind publishes its palette
// in OKLCH, and WCAG's contrast formula is defined on sRGB, so the conversion is
// unavoidable rather than a preference.
func oklchToSRGB(lightness, chroma, hue float64) rgb {
	rad := hue * math.Pi / 180
	a := chroma * math.Cos(rad)
	b := chroma * math.Sin(rad)

	lp := lightness + 0.3963377774*a + 0.2158037573*b
	mp := lightness - 0.1055613458*a - 0.0638541728*b
	sp := lightness - 0.0894841775*a - 1.2914855480*b
	l, m, sc := lp*lp*lp, mp*mp*mp, sp*sp*sp

	lr := 4.0767416621*l - 3.3077115913*m + 0.2309699292*sc
	lg := -1.2684380046*l + 2.6097574011*m - 0.3413193965*sc
	lb := -0.0041960863*l - 0.7034186147*m + 1.7076147010*sc
	return rgb{gamma(lr), gamma(lg), gamma(lb)}
}

// gamma encodes a linear sRGB channel and clamps out-of-gamut results, which OKLCH
// can produce for saturated colours.
func gamma(v float64) float64 {
	if v <= 0.0031308 {
		v *= 12.92
	} else {
		v = 1.055*math.Pow(v, 1/2.4) - 0.055
	}
	return math.Min(1, math.Max(0, v))
}

// relativeLuminance is WCAG 2.x's definition, not perceptual lightness.
func relativeLuminance(c rgb) float64 {
	lin := func(v float64) float64 {
		if v <= 0.04045 {
			return v / 12.92
		}
		return math.Pow((v+0.055)/1.055, 2.4)
	}
	return 0.2126*lin(c.r) + 0.7152*lin(c.g) + 0.0722*lin(c.b)
}

func contrast(fg, bg rgb) float64 {
	l1, l2 := relativeLuminance(fg), relativeLuminance(bg)
	if l1 < l2 {
		l1, l2 = l2, l1
	}
	return (l1 + 0.05) / (l2 + 0.05)
}

func failf(format string, args ...any) {
	_, _ = fmt.Fprintf(os.Stderr, "✗ "+format+"\n", args...)
	os.Exit(1)
}
