// Package redact turns personal data into a form that is safe to record, per ADR-0500.
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

// The pseudonym key. It is read once from the environment where the sops-operator puts it, per ADR-0202.
// An empty key works and is not a failure. A token made with it is still stable in its environment. A refusal to
// start would make an observability helper an availability dependency.
var key = sync.OnceValue(
	func() []byte {
		return []byte(os.Getenv("REDACT_TOKEN_KEY"))
	},
)

// tokenLen is 16 base32 characters, which is 80 bits. Nothing verifies a token, so more bits only make the line
// harder to read.
const tokenLen = 16

var enc = base32.StdEncoding.WithPadding(base32.NoPadding)

// Token maps the empty string to the empty string, not to a token. So an absent value and a present value stay
// different.
func Token(v string) string {
	if v == "" {
		return ""
	}
	mac := hmac.New(sha256.New, key())
	// hash.Hash.Write never returns an error. The interface has one because
	// io.Writer does.
	_, _ = mac.Write([]byte(v))
	return strings.ToLower(enc.EncodeToString(mac.Sum(nil))[:tokenLen])
}

// Email keeps the domain, which identifies an organisation and not a person, and tokenises the mailbox.
// A value that does not parse as an address is masked whole, because a malformed address often carries other data.
func Email(v string) string {
	at := strings.LastIndex(v, "@")
	if at <= 0 || at == len(v)-1 {
		return Mask(v)
	}
	return Token(strings.ToLower(v[:at])) + "@" + strings.ToLower(v[at+1:])
}

// IP reduces an address to the network that an operator can act on: a /24 for IPv4, a /48 for IPv6.
// The analytics path stores no raw address, per ADR-0700. IP is for the operational paths.
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

// Mask replaces a value with its length class, not its length. An exact length is a fingerprint, and for a short
// field it is close to the value.
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
