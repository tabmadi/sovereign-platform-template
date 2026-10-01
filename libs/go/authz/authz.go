// Package authz is the shared OpenFGA client wrapper, per ADR-0304. A depguard rule keeps the SDK in this package.
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

// storeName is the one platform store that the seed Job creates. The library
// discovers its ID by name, so no ConfigMap is needed.
const storeName = "platform"

// Checker is the only authz surface service code uses.
type Checker interface {
	Allowed(ctx context.Context, subject, permission, resource string) (bool, error)
}

type Granter interface {
	Grant(ctx context.Context, subject, relation, resource string) error
	Revoke(ctx context.Context, subject, relation, resource string) error
}

type fga struct {
	c      *client.OpenFgaClient
	envID  string // OPENFGA_STORE_ID when pinned, otherwise discovered on first use
	mu     sync.Mutex
	pinned bool // the store ID is pinned, and discovery retries until it is
	err    error
}

// New connects with OPENFGA_API_URL and the preshared key, per ADR-0202. The store ID comes from OPENFGA_STORE_ID
// when set. Otherwise it is discovered by name on first use, so New never blocks on OpenFGA at startup.
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
	// Fall back to the SOPS secret's own key name, openfga-creds.preshared_key, per ADR-0202.
	// Then a consumer can mount that Secret with envFrom and no changes.
	key := os.Getenv("OPENFGA_PRESHARED_KEY")
	if key == "" {
		key = os.Getenv("preshared_key")
	}
	if key == "" {
		return nil, errors.New("neither OPENFGA_PRESHARED_KEY nor preshared_key is set")
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

// Allowed runs a Check against OpenFGA. Its user and object strings already have the form `type:id`, so the
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

// Grant writes a relationship tuple. OpenFGA rejects a write of an existing tuple. The platform only writes
// fixed-shape tuples, so that error means the grant exists. Grant treats it as idempotent success.
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

// Revoke deletes a relationship tuple. OpenFGA rejects a delete of a tuple that does not exist. That is the state
// the call asks for, so Revoke treats that error as idempotent success, like Grant.
func (f *fga) Revoke(ctx context.Context, subject, relation, resource string) error {
	err := f.ensureStore(ctx)
	if err != nil {
		return err
	}
	_, err = f.c.Write(ctx).Body(
		client.ClientWriteRequest{
			Deletes: []client.ClientTupleKeyWithoutCondition{
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
		return fmt.Errorf("authz: revoke: %w", err)
	}
	return nil
}

// This runs on first use, so startup never blocks on OpenFGA readiness. A failed discovery is not cached, because
// the seed Job can still be creating the store. A pinned store is never discovered again.
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
// exactly one store named `platform`. A check with no model ID uses that store's
// latest model, and the template needs nothing more.
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
	return "", fmt.Errorf("openfga store %q not found: check that the seed Job ran", storeName)
}
