// Package authz is the shared OpenFGA client wrapper (ADR-0304); a depguard rule confines the SDK to this package.
package authz

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"

	openfga "github.com/openfga/go-sdk"
	"github.com/openfga/go-sdk/client"
	"github.com/openfga/go-sdk/credentials"
)

// storeName is the single platform store the seed Job creates; the library
// discovers its ID by name (no ConfigMap plumbing required).
const storeName = "platform"

// Checker is the only authz surface service code uses.
type Checker interface {
	Allowed(ctx context.Context, subject, permission, resource string) (bool, error)
}

type Granter interface {
	Grant(ctx context.Context, subject, relation, resource string) error
}

type fga struct {
	c      *client.OpenFgaClient
	envID  string // OPENFGA_STORE_ID if pinned; else discovered lazily
	mu     sync.Mutex
	pinned bool // store ID successfully pinned; discovery is retried until then
	err    error
}

// New: OPENFGA_API_URL and the preshared key drive the connection (ADR-0202). The store ID comes from
// OPENFGA_STORE_ID if set, else is discovered by name on first use, so New never blocks on OpenFGA at startup.
func New() (Checker, error) {
	return dial()
}

func NewGranter() (Granter, error) {
	return dial()
}

func dial() (*fga, error) {
	apiURL := os.Getenv("OPENFGA_API_URL")
	if apiURL == "" {
		apiURL = "http://openfga.platform.svc.cluster.local:8080"
	}
	// Fall back to the SOPS secret's native key name (openfga-creds.preshared_key,
	// ADR-0202) so a consumer can mount that Secret with envFrom unmodified.
	key := os.Getenv("OPENFGA_PRESHARED_KEY")
	if key == "" {
		key = os.Getenv("preshared_key")
	}
	if key == "" {
		return nil, errors.New("OPENFGA_PRESHARED_KEY (or preshared_key) not set")
	}

	c, err := client.NewSdkClient(
		&client.ClientConfiguration{
			ApiUrl: apiURL,
			Credentials: &credentials.Credentials{
				Method: credentials.CredentialsMethodApiToken,
				Config: &credentials.Config{ApiToken: key},
			},
		},
	)
	if err != nil {
		return nil, fmt.Errorf("dial openfga: %w", err)
	}
	return &fga{c: c, envID: os.Getenv("OPENFGA_STORE_ID")}, nil
}

// Allowed runs a Check against OpenFGA. Its user and object strings are already "type:id", so the
// platform's tuple strings pass through with no splitting.
func (f *fga) Allowed(ctx context.Context, subject, permission, resource string) (bool, error) {
	err := f.ensureStore(ctx)
	if err != nil {
		return false, err
	}
	resp, err := f.c.Check(ctx).Body(
		client.ClientCheckRequest{
			User:     subject,
			Relation: permission,
			Object:   resource,
		},
	).Execute()
	if err != nil {
		return false, fmt.Errorf("authz: check: %w", err)
	}
	return resp.GetAllowed(), nil
}

// Grant writes a relationship tuple. OpenFGA rejects a write of an existing tuple, and the platform only writes
// fixed-shape ones, so that error means the grant is already present and is treated as idempotent success.
func (f *fga) Grant(ctx context.Context, subject, relation, resource string) error {
	err := f.ensureStore(ctx)
	if err != nil {
		return err
	}
	_, err = f.c.Write(ctx).Body(
		client.ClientWriteRequest{
			Writes: []client.ClientTupleKey{
				{User: subject, Relation: relation, Object: resource},
			},
		},
	).Execute()
	if err != nil {
		var verr openfga.FgaApiValidationError
		if errors.As(err, &verr) &&
			verr.ResponseCode() == openfga.ERRORCODE_WRITE_FAILED_DUE_TO_INVALID_INPUT {
			return nil
		}
		return fmt.Errorf("authz: grant: %w", err)
	}
	return nil
}

// Deferred to first use so startup never blocks on OpenFGA readiness. A failed discovery is not cached — the seed
// Job may still be creating the store — and a pinned store is never re-discovered.
func (f *fga) ensureStore(ctx context.Context) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.pinned {
		return f.err
	}
	id := f.envID
	if id == "" {
		id, f.err = f.discoverStore(ctx)
		if f.err != nil {
			return f.err
		}
	}
	f.err = f.c.SetStoreId(id)
	if f.err != nil {
		f.err = fmt.Errorf("set openfga store id: %w", f.err)
		return f.err
	}
	f.pinned = true
	return nil
}

// discoverStore finds the platform store's ID by name. The seed Job creates
// exactly one store named `platform`; a check omitting the model ID uses that
// store's latest model, which is all the template needs.
func (f *fga) discoverStore(ctx context.Context) (string, error) {
	resp, err := f.c.ListStores(ctx).Execute()
	if err != nil {
		return "", fmt.Errorf("list openfga stores: %w", err)
	}
	for _, s := range resp.GetStores() {
		if s.GetName() == storeName {
			return s.GetId(), nil
		}
	}
	return "", fmt.Errorf("openfga store %q not found (has the seed Job run?)", storeName)
}
