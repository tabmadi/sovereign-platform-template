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

// kratosAdminURL is where the identity record lives. The same in-cluster address
// services/authz uses; neither reaches Kratos through the edge.
func kratosAdminURL() string {
	v := os.Getenv("KRATOS_ADMIN_URL")
	if v != "" {
		return v
	}
	return "http://ory-kratos-admin.platform.svc.cluster.local"
}

// SetIdentityOrgActivity: This is where X-Org-Id comes from (ADR-0304): the edge templates that header out of
// `metadata_public.org_id`, so an identity without it reaches every service belonging to no org. The org existing in
// the database and in OpenFGA is not enough — the edge reads neither. The value is the wire form (ADR-0003).
func (a *Activities) SetIdentityOrgActivity(ctx context.Context, identityID, orgID string) error {
	metadata, err := a.identityMetadata(ctx, identityID)
	if err != nil {
		return err
	}
	if metadata["org_id"] == orgID {
		return nil
	}
	metadata["org_id"] = orgID

	// One op replacing the whole object: a patch on `/metadata_public/org_id` fails when the identity has no metadata,
	// and a bare `add` would drop `roles`.
	patch := []map[string]any{{"op": "add", "path": "/metadata_public", "value": metadata}}
	err = a.kratosJSON(ctx, http.MethodPatch, a.identityURL(identityID), patch, http.StatusOK, nil)
	if err != nil {
		return fmt.Errorf("set identity org: patch identity: %w", err)
	}
	return nil
}

// identityMetadata reads an identity's public metadata, or an empty map when it has
// none. Only this object is read; the rest of the record is never touched.
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

// kratosJSON performs a JSON request against the Kratos admin API and asserts the
// expected status. A nil body sends none; a nil out skips decoding.
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
