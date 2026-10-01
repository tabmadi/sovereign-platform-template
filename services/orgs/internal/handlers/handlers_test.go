package handlers

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authmw"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	orgs "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/orgs"
	"github.com/tabmadi/sovereign-platform-template/services/orgs/internal/store"
)

// A well-formed wire identifier, per ADR-0003. The cases below then test the
// handler's gates and not its identifier decoding.
const testOrgID = orgs.OrgId("org_01kztn9tsrea7b1597q3yjdeav")

// testUser is the principal of every authenticated case.
const testUser = "alice"

// fakeQ embeds store.Querier, so only the methods that a test uses need stubs.
// Any other call panics on nil, and that is the wanted signal for an unexpected query.
type fakeQ struct {
	store.Querier

	org store.GetOrgRow
}

func (f fakeQ) GetOrg(context.Context, pgtype.UUID) (store.GetOrgRow, error) {
	return f.org, nil
}

// opCtx is an authenticated request context. The read gate needs this principal
// before it calls the Checker.
func opCtx() context.Context {
	return authmw.NewContext(context.Background(), &authmw.Principal{UserID: testUser})
}

// resourceChecker answers per resource, as the read gate needs. A member holds
// `org#read` on their own org and nothing on `group:operator`. An operator is
// the reverse. A single bool cannot express either.
type resourceChecker map[string]bool

func (c resourceChecker) Allowed(_ context.Context, _, _, resource string) (bool, error) {
	return c[resource], nil
}

// orgObject is the OpenFGA object that the read gate checks.
var orgObject = "org:" + string(testOrgID)

func TestGetOrgAuthz(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		ctx     func() context.Context
		checker authz.Checker
		want    int
	}{
		{"holding the identifier is not enough", context.Background, resourceChecker{orgObject: true}, 401},
		{"a non-member is forbidden", opCtx, resourceChecker{}, 403},
		{"a member reads their org", opCtx, resourceChecker{orgObject: true}, 0},
		{"an operator reads any org", opCtx, resourceChecker{"group:operator": true}, 0},
	}
	for _, tc := range tests {
		t.Run(
			tc.name,
			func(t *testing.T) {
				t.Parallel()
				h := &Handlers{q: fakeQ{org: store.GetOrgRow{Name: "Northwind"}}, checker: tc.checker}
				_, err := h.GetOrg(tc.ctx(), orgs.GetOrgParams{ID: testOrgID})
				if tc.want == 0 {
					if err != nil {
						t.Fatalf("unexpected error: %v", err)
					}
					return
				}
				assertStatus(t, err, tc.want)
			},
		)
	}
}

// fakeChecker stands in for the OpenFGA Checker, so a test can run the operator
// gate without a cluster, per ADR-0304.
type fakeChecker struct {
	allowed bool
	err     error
}

func (f fakeChecker) Allowed(context.Context, string, string, string) (bool, error) {
	return f.allowed, f.err
}

// Every org write is operator-gated, per ADR-0304. The gate rejects before any DB
// access, so a nil store works for these cases. There is no create: an org comes
// from the registration flow's dual write, never from an endpoint.
func TestOrgWriteAuthz(t *testing.T) {
	t.Parallel()

	writes := map[string]func(context.Context, *Handlers) error{
		"UpdateOrg": func(ctx context.Context, h *Handlers) error {
			_, err := h.UpdateOrg(ctx, &orgs.OrgInput{Name: "acme"}, orgs.UpdateOrgParams{})
			return err
		},
		"DeleteOrg": func(ctx context.Context, h *Handlers) error {
			return h.DeleteOrg(ctx, orgs.DeleteOrgParams{})
		},
	}
	cases := []struct {
		name    string
		authed  bool
		checker authz.Checker
		want    int
	}{
		{"anonymous is unauthorized", false, fakeChecker{}, 401},
		{"non-operator is forbidden", true, fakeChecker{allowed: false}, 403},
		{"checker failure is internal", true, fakeChecker{err: errors.New("openfga down")}, 500},
	}
	for name, call := range writes {
		for _, tc := range cases {
			t.Run(
				name+"/"+tc.name,
				func(t *testing.T) {
					t.Parallel()
					ctx := context.Background()
					if tc.authed {
						ctx = authmw.NewContext(ctx, &authmw.Principal{UserID: testUser})
					}
					err := call(ctx, &Handlers{checker: tc.checker})
					assertStatus(t, err, tc.want)
				},
			)
		}
	}
}

// UpdateOrg rejects an empty name, per ADR-0302, but only after the operator gate.
// So this tests the validation path with an authenticated operator and a nil
// store.
func TestUpdateOrgValidation(t *testing.T) {
	t.Parallel()
	ctx := authmw.NewContext(context.Background(), &authmw.Principal{UserID: testUser})
	h := &Handlers{checker: fakeChecker{allowed: true}}
	_, err := h.UpdateOrg(ctx, &orgs.OrgInput{Name: ""}, orgs.UpdateOrgParams{})
	assertStatus(t, err, 400)
}

func assertStatus(t *testing.T, err error, want int) {
	t.Helper()
	e, ok := apierr.As(err)
	if !ok {
		t.Fatalf("want *apierr.Error, got %v", err)
	}
	if e.Status != want {
		t.Fatalf("status = %d, want %d", e.Status, want)
	}
}
