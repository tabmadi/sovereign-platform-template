// Package authmw turns the identity headers that the edge injects into a typed Principal on the request context.
// The headers are X-User-Id, X-Org-Id, and X-Roles, per ADR-0305 and ADR-0304.
package authmw

import (
	"context"
	"net/http"
	"slices"
	"strings"
)

// Canonical identity header names. The edge is the only authority that sets them.
// The edge strips any copies from the client before the request arrives.
const (
	HeaderUserID = "X-User-Id"
	HeaderOrgID  = "X-Org-Id"
	HeaderRoles  = "X-Roles"
)

// The edge's anonymous authenticator puts this in X-User-Id for a caller with no session. It uses the same header
// as a real identity, so a check for a non-empty header treats every guest as a signed-in user.
// infra/auth/oathkeeper/values.yaml holds the same value. The two are one decision.
const anonymousSubject = "guest"

type ctxKey int

const principalKey ctxKey = 1

// Principal is the identity of the caller, as forwarded by the edge.
type Principal struct {
	UserID string
	OrgID  string
	Roles  []string
}

func (p *Principal) Authenticated() bool {
	return p != nil && p.UserID != "" && p.UserID != anonymousSubject
}

func (p *Principal) HasRole(role string) bool {
	if p == nil {
		return false
	}
	return slices.Contains(p.Roles, role)
}

// Subject renders the principal as an OpenFGA user string, `user:<id>`, for the
// authz Checker, per ADR-0304. A guest has no subject, so nobody can write a tuple
// for a guest by accident.
func (p *Principal) Subject() string {
	if !p.Authenticated() {
		return ""
	}
	return "user:" + p.UserID
}

// Read parses the trusted identity headers from h into a Principal. An absent
// user id gives an unauthenticated guest principal. The edge admits guests, and
// each service decides per route if it needs a real principal.
func Read(h http.Header) *Principal {
	return &Principal{
		UserID: h.Get(HeaderUserID),
		OrgID:  h.Get(HeaderOrgID),
		Roles:  ParseRoles(h.Get(HeaderRoles)),
	}
}

// FromContext returns the principal attached by Middleware, or nil if absent.
func FromContext(ctx context.Context) (*Principal, bool) {
	p, ok := ctx.Value(principalKey).(*Principal)
	return p, ok
}

// NewContext returns ctx with p attached. It is the inverse of FromContext. Handlers
// get a principal from Middleware, and tests inject one directly with this.
func NewContext(ctx context.Context, p *Principal) context.Context {
	return context.WithValue(ctx, principalKey, p)
}

// Middleware attaches the parsed principal to the request context. It never
// rejects: the edge already validated the request, and the handler does
// authorisation with the authz Checker.
func Middleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(
			func(w http.ResponseWriter, r *http.Request) {
				ctx := context.WithValue(r.Context(), principalKey, Read(r.Header))
				next.ServeHTTP(w, r.WithContext(ctx))
			},
		)
	}
}

// ParseRoles splits the X-Roles header into roles. It accepts the comma-separated
// form and Go's bracketed slice form, `[admin member]`. So it works with either
// way the edge mutator turns the roles claim into a string.
func ParseRoles(raw string) []string {
	raw = strings.TrimSpace(raw)
	raw = strings.TrimPrefix(raw, "[")
	raw = strings.TrimSuffix(raw, "]")
	if raw == "" {
		return nil
	}
	fields := strings.FieldsFunc(raw, func(r rune) bool { return r == ',' || r == ' ' })
	roles := make([]string, 0, len(fields))
	for _, f := range fields {
		f = strings.TrimSpace(f)
		if f != "" {
			roles = append(roles, f)
		}
	}
	if len(roles) == 0 {
		return nil
	}
	return roles
}
