package authmw_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tabmadi/sovereign-platform-template/libs/go/authmw"
)

// The edge admits guests with a real value in X-User-Id. The test pins both halves, because the value is in
// infra/auth/oathkeeper/values.yaml and nothing else connects the two.
func TestGuestIsNotAuthenticated(t *testing.T) {
	t.Parallel()

	tests := map[string]struct {
		userID string
		want   bool
	}{
		"a real identity":  {"30b478e3-24c9-48b6-911b-3520bfdeeced", true},
		"the edge's guest": {"guest", false},
		"no header at all": {"", false},
	}
	for name, tc := range tests {
		t.Run(
			name,
			func(t *testing.T) {
				t.Parallel()
				h := http.Header{}
				if tc.userID != "" {
					h.Set(authmw.HeaderUserID, tc.userID)
				}
				p := authmw.Read(h)
				if got := p.Authenticated(); got != tc.want {
					t.Errorf("Authenticated() = %v, want %v", got, tc.want)
				}
				if !tc.want && p.Subject() != "" {
					t.Errorf("Subject() = %q, want empty for a caller who is not signed in", p.Subject())
				}
			},
		)
	}
}

// A handler holds the zero Principal when the middleware did not run.
func TestNilPrincipal(t *testing.T) {
	t.Parallel()

	var p *authmw.Principal
	if p.Authenticated() {
		t.Error("a nil principal reports as authenticated")
	}
	if p.HasRole("operator") {
		t.Error("a nil principal reports a role")
	}
}

func TestTransportForwardsIdentity(t *testing.T) {
	t.Parallel()

	client := &http.Client{Transport: authmw.Transport(nil)}

	tests := map[string]struct {
		principal *authmw.Principal
		want      authmw.Principal
	}{
		"a caller": {
			&authmw.Principal{UserID: "u1", OrgID: "o1", Roles: []string{"admin", "member"}},
			authmw.Principal{UserID: "u1", OrgID: "o1", Roles: []string{"admin", "member"}},
		},
		"no principal": {nil, authmw.Principal{}},
	}
	for name, tc := range tests {
		t.Run(
			name,
			func(t *testing.T) {
				t.Parallel()
				var got http.Header
				srv := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) { got = r.Header.Clone() }))
				t.Cleanup(srv.Close)
				ctx := t.Context()
				if tc.principal != nil {
					ctx = authmw.NewContext(ctx, tc.principal)
				}
				req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL, nil)
				if err != nil {
					t.Fatal(err)
				}
				resp, err := client.Do(req)
				if err != nil {
					t.Fatal(err)
				}
				_ = resp.Body.Close()
				p := authmw.Read(got)
				if p.UserID != tc.want.UserID || p.OrgID != tc.want.OrgID || len(p.Roles) != len(tc.want.Roles) {
					t.Errorf("callee saw %+v, want %+v", p, tc.want)
				}
			},
		)
	}
}
