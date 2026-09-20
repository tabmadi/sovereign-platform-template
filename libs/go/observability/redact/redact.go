// Package redact turns personal data into something safe to record (ADR-0500).
package redact

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base32"
	"net/netip"
	"os"
	"strings"
	"sync"
	"unicode/utf8"
)

// The pseudonym key, read once from the environment the sops-operator delivers it in (ADR-0202).
// Empty is a working key, not a failure: a token derived under it is still stable within its environment, and
// refusing to start would make an observability helper an availability dependency.
var key = sync.OnceValue(
	func() []byte {
		return []byte(os.Getenv("REDACT_TOKEN_KEY"))
	},
)

// tokenLen is 16 base32 characters — 80 bits. Nothing verifies a token, so the remaining bits only make the line
// harder to scan.
const tokenLen = 16

var enc = base32.StdEncoding.WithPadding(base32.NoPadding)

// Token: The empty string maps to the empty string rather than to a token, so "absent" and "present" stay
// distinguishable.
func Token(v string) string {
	if v == "" {
		return ""
	}
	mac := hmac.New(sha256.New, key())
	// hash.Hash.Write never returns an error; the interface carries one because
	// io.Writer does.
	_, _ = mac.Write([]byte(v))
	return strings.ToLower(enc.EncodeToString(mac.Sum(nil))[:tokenLen])
}

// Email keeps the domain, which identifies an organisation rather than a person, and tokenises the mailbox.
// Anything that does not parse as an address is masked whole: a malformed address often carries something else.
func Email(v string) string {
	at := strings.LastIndex(v, "@")
	if at <= 0 || at == len(v)-1 {
		return Mask(v)
	}
	return Token(strings.ToLower(v[:at])) + "@" + strings.ToLower(v[at+1:])
}

// IP reduces an address to the network an operator can act on: a /24 for IPv4, a /48 for IPv6.
// Raw addresses are stored nowhere on the analytics path (ADR-0700); this is for the operational paths.
func IP(v string) string {
	addr, err := netip.ParseAddr(v)
	if err != nil {
		return Mask(v)
	}
	bits := 24
	if addr.Is6() && !addr.Is4In6() {
		bits = 48
	}
	p, err := addr.Prefix(bits)
	if err != nil {
		return Mask(v)
	}
	return p.String()
}

// Mask replaces a value with its length class, not its length: an exact length is a fingerprint, and for short
// fields it is close to the value.
func Mask(v string) string {
	switch n := utf8.RuneCountInString(v); {
	case n == 0:
		return ""
	case n < 8:
		return "[redacted:short]"
	case n < 64:
		return "[redacted:medium]"
	default:
		return "[redacted:long]"
	}
}
