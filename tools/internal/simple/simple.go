// Package simple checks text against the Simple English profile of ADR-0001: the punctuation allow-list,
// the sentence-length limits, and the word lists a machine can read.
package simple

import (
	"fmt"
	"regexp"
	"strings"
)

// Sentence-length limits from ADR-0001. Procedures follow ASD-STE100 rule 5.1.
const (
	MaxWords          = 25
	MaxProcedureWords = 20
)

type Finding struct {
	Rule   string
	Match  string
	Reason string
}

func (f Finding) String() string {
	return fmt.Sprintf("%s %q: %s", f.Rule, f.Match, f.Reason)
}

const curlyQuote = "curly quote"

// BannedChars appear in no tracked text file, code included. They are written as escapes so this file
// does not trip its own check.
var BannedChars = map[rune]string{
	'\u2014': "em dash",
	'\u2013': "en dash",
	'\u2026': "ellipsis",
	'\u201c': curlyQuote,
	'\u201d': curlyQuote,
	'\u2018': curlyQuote,
	'\u2019': curlyQuote,
	'\u00ab': "guillemet",
	'\u00bb': "guillemet",
	'\u201e': "low quote",
	'\u061f': "Arabic question mark",
	'\u061b': "Arabic semicolon",
}

const (
	ruleSemicolon = "semicolon"
	ruleSlash     = "slash"
)

type pattern struct {
	name   string
	re     *regexp.Regexp
	reason string
}

// Punctuation in prose. Each pattern is written so that code a comment mentions does not match: `!=`, `a;b`,
// `&&`, and call syntax such as `run()` pass.
var punctuation = []pattern{
	{ruleSemicolon, regexp.MustCompile(`[\p{L}\p{N})'"*_]; `), "write two sentences, or use a colon"},
	{ruleSemicolon, regexp.MustCompile(`[\p{L}\p{N})'"*_];$`), "write two sentences, or use a colon"},
	{
		"parentheses",
		regexp.MustCompile(`(^|[\s,.:])\([^)]*\)?`),
		"write the aside as its own sentence, or delete it. Cite as `per ADR-0204`",
	},
	{"question mark", regexp.MustCompile(`[\p{L}\p{N})'"*_]\?(\s|$)`), "write the answer as a statement"},
	{"exclamation mark", regexp.MustCompile(`[\p{L}\p{N})'"*_]!(\s|$)`), "delete it"},
	{"ampersand", regexp.MustCompile(`(^|\s)&(\s|$)`), "write `and`"},
	{"quote mark", regexp.MustCompile(`"`), "use backticks for literal text"},
	{"dash", regexp.MustCompile(`\S\s--?\s\S`), "write two sentences, or use a colon or a comma"},
	{ruleSlash, regexp.MustCompile(`(?i)\s/\s|\band/or\b`), "write `or`, `and`, or a list"},
}

// wordSlash is `A/B` between two plain words. Markdown prose checks it. Comments do not, because a comment
// names paths without backticks.
var wordSlash = pattern{
	ruleSlash,
	regexp.MustCompile(`(^|[\s,.:])(\p{L}+)/(\p{L}+)([\s,.:]|$)`),
	"write `or`, `and`, or a list. Put a path in backticks",
}

// slashTerms are technical names that contain a slash.
var slashTerms = map[string]bool{"ci/cd": true, "i/o": true, "tcp/ip": true}

var english = []pattern{
	{
		"contraction",
		regexp.MustCompile(
			`(?i)\b(\p{L}+n't|it's|that's|there's|here's|what's|who's|let's|\p{L}+'re|\p{L}+'ve|\p{L}+'ll|i'm)\b`,
		),
		"write the full form: `do not`, `it is`",
	},
	{
		"abbreviation",
		regexp.MustCompile(`(?i)(\be\.g\.|\bi\.e\.|\betc\.|\bviz\.|\bcf\.|\bvs\.?(\s|$))`),
		"write `for example`, `that is`, a complete list, or `or`",
	},
}

// complexWords maps a word above CEFR B1 to its simple form. The key is a regular expression.
var complexWords = []struct{ word, simple string }{
	{`utili[sz](e|es|ed|ing|ation)`, "use"},
	{`leverag(e|es|ed|ing)`, "use"},
	{`facilitat(e|es|ed|ing)`, "help"},
	{`prior to`, "before"},
	{`in order to`, "to"},
	{`subsequently`, "then, or later"},
	{`hence`, "so"},
	{`thus`, "so"},
	{`thereby`, "so"},
	{`whereby`, "by which, or a new sentence"},
	{`wherein`, "where"},
	{`whilst`, "while"},
	{`amongst`, "among"},
	{`albeit`, "although"},
	{`notwithstanding`, "despite"},
	{`aforementioned`, "this, or the name"},
	{`commenc(e|es|ed|ing)`, "start"},
	{`endeavou?r`, "try"},
	{`in lieu of`, "instead of"},
	{`moreover`, "also"},
	{`furthermore`, "also"},
	{`nevertheless`, "but"},
	{`nonetheless`, "still"},
	{`whereas`, "but, or a new sentence"},
	{`henceforth`, "from now"},
	{`insofar as`, "if, or to the degree that"},
	{`inasmuch as`, "because"},
	{`vis-à-vis`, "about, or compared with"},
	{`per se`, "delete it"},
	{`ergo`, "so"},
	{`ascertain(s|ed|ing)?`, "find, or check"},
	{`elucidat(e|es|ed|ing)`, "explain"},
	{`obviat(e|es|ed|ing)`, "remove the need for"},
	{`necessitat(e|es|ed|ing)`, "need"},
	{`pertaining to`, "about"},
	{`in the event that`, "if"},
	{`with (respect|regard) to`, "about"},
	{`the majority of`, "most"},
	{`is able to`, "can"},
	{`via`, "through, by, or with"},
}

var complexPattern, complexExact = func() (*regexp.Regexp, []*regexp.Regexp) {
	parts := make([]string, len(complexWords))
	exact := make([]*regexp.Regexp, len(complexWords))
	for i, w := range complexWords {
		parts[i] = "(" + w.word + ")"
		exact[i] = regexp.MustCompile(`(?i)^(` + w.word + `)$`)
	}
	return regexp.MustCompile(`(?i)\b(` + strings.Join(parts, "|") + `)\b`), exact
}()

func simpleFor(match string) string {
	for i, re := range complexExact {
		if re.MatchString(match) {
			return complexWords[i].simple
		}
	}
	return ""
}

type Options struct {
	// English enables the word checks. A translated UI string gets only the punctuation checks.
	English bool
	// WordSlash enables the `A/B` check, which is exact only where paths are in backticks.
	WordSlash bool
	// MaxWords is the sentence limit. Zero disables the length check.
	MaxWords int
	// SkipChars leaves the banned characters to a caller that checks whole files for them.
	SkipChars bool
}

// Check returns the violations in one prose text. The caller strips what is not prose first: code spans,
// URLs, link targets, and enforcement annotations.
func Check(text string, o Options) []Finding {
	var out []Finding
	if !o.SkipChars {
		out = append(out, chars(text)...)
	}
	out = append(out, first(text, punctuation)...)
	if o.WordSlash {
		out = append(out, slashes(text)...)
	}
	if o.English {
		out = append(out, first(text, english)...)
		m := complexPattern.FindString(text)
		if m != "" {
			out = append(out, Finding{"complex word", m, "write `" + simpleFor(m) + "`"})
		}
	}
	if o.MaxWords > 0 {
		out = append(out, long(text, o.MaxWords)...)
	}
	return out
}

func chars(text string) []Finding {
	var out []Finding
	for _, r := range text {
		name, banned := BannedChars[r]
		if banned {
			out = append(out, Finding{"banned character", string(r), name + ": " + replacementFor(name)})
		}
	}
	return out
}

// first reports the first match of each pattern. One finding per rule and text is enough to locate it.
func first(text string, patterns []pattern) []Finding {
	var out []Finding
	for _, p := range patterns {
		m := p.re.FindString(text)
		if m != "" {
			out = append(out, Finding{p.name, strings.TrimSpace(m), p.reason})
		}
	}
	return out
}

func slashes(text string) []Finding {
	for _, m := range wordSlash.re.FindAllStringSubmatch(text, -1) {
		if !slashTerms[strings.ToLower(m[2]+"/"+m[3])] {
			return []Finding{{wordSlash.name, m[2] + "/" + m[3], wordSlash.reason}}
		}
	}
	return nil
}

func long(text string, limit int) []Finding {
	var out []Finding
	for _, s := range Sentences(text) {
		n := Words(s)
		if n > limit {
			reason := fmt.Sprintf("%d words, max %d: split it into shorter sentences", n, limit)
			out = append(out, Finding{"long sentence", clip(s), reason})
		}
	}
	return out
}

func replacementFor(name string) string {
	switch name {
	case "em dash":
		return "write two sentences, or use a colon or a comma"
	case "en dash":
		return "write `1 to 5` for a range"
	case "ellipsis":
		return "complete the list, or delete it"
	default:
		return "use backticks for literal text"
	}
}

// sentenceEnd is a period, colon, or question or exclamation mark before a space or the end. A period
// inside `3.1` or a file name is not an end.
var sentenceEnd = regexp.MustCompile(`[.:?!][*_]*(\s+|$)`)

// Sentences splits prose at sentence ends. A colon ends a unit too: it introduces a list or an explanation.
func Sentences(text string) []string {
	var out []string
	for _, s := range sentenceEnd.Split(text, -1) {
		if strings.TrimSpace(s) != "" {
			out = append(out, s)
		}
	}
	return out
}

var word = regexp.MustCompile(`[\p{L}\p{N}]`)

// Words counts only the tokens that contain a letter or a digit.
func Words(s string) int {
	n := 0
	for tok := range strings.FieldsSeq(s) {
		if word.MatchString(tok) {
			n++
		}
	}
	return n
}

func clip(s string) string {
	s = strings.TrimSpace(s)
	fields := strings.Fields(s)
	if len(fields) > 8 {
		return strings.Join(fields[:8], " ") + " ..."
	}
	return s
}

var (
	codeSpan   = regexp.MustCompile("`[^`]*`")
	url        = regexp.MustCompile(`<?https?://[^\s)>]+>?`)
	annotation = regexp.MustCompile("`?\\((CI|enforced|ref): [^)]*\\)`?")
	image      = regexp.MustCompile(`!\[([^\]]*)\]\([^)]*\)`)
	link       = regexp.MustCompile(`\[([^\]]*)\]\([^)]*\)`)
	refLink    = regexp.MustCompile(`\[([^\]]*)\]\[[^\]]*\]`)
	htmlTag    = regexp.MustCompile(`<!--.*?-->|</?[A-Za-z][^>]*>`)
	callSyntax = regexp.MustCompile(`[\p{L}\p{N}_]\([^)\s]*\)`)
)

// StripCode replaces code spans, URLs, and enforcement annotations with a single word, so the length check
// counts each as one word and the punctuation checks do not see inside them.
func StripCode(s string) string {
	s = annotation.ReplaceAllString(s, "")
	s = codeSpan.ReplaceAllString(s, "x")
	s = url.ReplaceAllString(s, "x")
	s = callSyntax.ReplaceAllStringFunc(s, func(m string) string { return m[:1] })
	return s
}

// StripMarkdown reduces one Markdown line to its prose: links become their text, and HTML, emphasis
// markers, heading and list markers, and quote markers go.
func StripMarkdown(line string) string {
	s := StripCode(line)
	s = htmlTag.ReplaceAllString(s, "")
	s = image.ReplaceAllString(s, "$1")
	for link.MatchString(s) {
		s = link.ReplaceAllStringFunc(s, linkText)
	}
	s = refLink.ReplaceAllString(s, "$1")
	s = strings.TrimSpace(s)
	s = strings.TrimLeft(s, "#> ")
	s = listMarker.ReplaceAllString(s, "")
	return s
}

// linkText is a link's visible text. A text that is a path or a file name is code, and counts as one word.
func linkText(m string) string {
	text := link.FindStringSubmatch(m)[1]
	if !strings.Contains(text, " ") && strings.ContainsAny(text, "/.") {
		return "x"
	}
	return text
}

var listMarker = regexp.MustCompile(`^([-*+]|\d+\.)\s+(\[[ xX]\]\s+)?`)
