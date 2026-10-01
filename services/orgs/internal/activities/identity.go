package activities

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
)

// kratosAdminURL is where the identity record lives. services/authz uses the same
// in-cluster address. Neither reaches Kratos through the edge.
func kratosAdminURL() string {
	v := os.Getenv("KRATOS_ADMIN_URL")
	if v != "" {
		return v
	}
	return "http://ory-kratos-admin.platform.svc.cluster.local"
}

// SetIdentityOrgActivity is the source of X-Org-Id, per ADR-0304. The edge builds it from `metadata_public.org_id`,
// so an identity without it reaches every service with no org. The edge reads neither the database nor OpenFGA.
// The value is the wire form, per ADR-0003.
func (a *Activities) SetIdentityOrgActivity(ctx context.Context, identityID, orgID string) error {
	metadata, err := a.identityMetadata(ctx, identityID)
	if err != nil {
		return err
	}
	if metadata["org_id"] == orgID {
		return nil
	}
	metadata["org_id"] = orgID

	// One op replaces the whole object. A patch on `/metadata_public/org_id` fails when the identity has no metadata,
	// and a bare `add` would drop `roles`.
	patch := []map[string]any{{"op": "add", "path": "/metadata_public", "value": metadata}}
	err = a.kratosJSON(ctx, http.MethodPatch, a.identityURL(identityID), patch, http.StatusOK, nil)
	if err != nil {
		return fmt.Errorf("set identity org: patch identity: %w", err)
	}
	return nil
}

// identityMetadata reads an identity's public metadata, or an empty map when it has
// none. It reads only this object and never touches the rest of the record.
func (a *Activities) identityMetadata(ctx context.Context, identityID string) (map[string]any, error) {
	var identity struct {
		MetadataPublic map[string]any `json:"metadata_public"`
	}
	err := a.kratosJSON(ctx, http.MethodGet, a.identityURL(identityID), nil, http.StatusOK, &identity)
	if err != nil {
		return nil, fmt.Errorf("set identity org: read identity: %w", err)
	}
	if identity.MetadataPublic == nil {
		return map[string]any{}, nil
	}
	return identity.MetadataPublic, nil
}

func (a *Activities) identityURL(identityID string) string {
	return a.KratosAdmin + "/admin/identities/" + url.PathEscape(identityID)
}

// kratosJSON sends a JSON request to the Kratos admin API and checks for the
// expected status. A nil body sends no body, and a nil out skips decoding.
func (a *Activities) kratosJSON(ctx context.Context, method, u string, body any, wantStatus int, out any) error {
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, reader)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := a.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("call kratos: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != wantStatus {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("kratos %d: %s", resp.StatusCode, b)
	}
	if out == nil {
		return nil
	}
	err = json.NewDecoder(resp.Body).Decode(out)
	if err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	return nil
}
