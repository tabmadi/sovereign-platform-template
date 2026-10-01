// Package kratos is this service's client for the Kratos admin API.
package kratos

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strconv"

	authzsdk "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/authz"
)

const SchemaUserV1 = "user_v1"

// Admin is the admin-API client. The zero value is not usable, so call New.
type Admin struct {
	baseURL string
	log     *slog.Logger
}

// New reads the admin URL from the environment. Without it, New uses the in-cluster
// Service. The fallback is the deployed case, so a missing variable means a local
// run and not a misconfiguration.
func New(log *slog.Logger) *Admin {
	base := os.Getenv("KRATOS_ADMIN_URL")
	if base == "" {
		base = "http://ory-kratos-admin.platform.svc.cluster.local"
	}
	return NewAt(base, log)
}

// NewAt builds a client for an explicit base URL. A test uses it to point at an
// httptest server without a process-wide environment variable, because parallel
// tests cannot share one.
func NewAt(baseURL string, log *slog.Logger) *Admin {
	if log == nil {
		log = slog.Default()
	}
	return &Admin{baseURL: baseURL, log: log}
}

// operatorKey is the metadata_public key that the ops gate reads, per ADR-0306. It is metadata, not a trait.
// Self-service registration and settings write traits, and only the admin API writes metadata.
const operatorKey = "operator"

// Identity is the subset that this service reads and writes. schema_id, state, and metadata_public pass through
// with no change. Kratos PUT replaces the whole record, and the edge builds X-Org-Id and X-Roles from metadata_public,
// per ADR-0304. A write without them would remove an operator's org.
type Identity struct {
	ID             string          `json:"id,omitempty"`
	SchemaID       string          `json:"schema_id,omitempty"`
	State          string          `json:"state,omitempty"`
	MetadataPublic json.RawMessage `json:"metadata_public,omitempty"`
	Traits         struct {
		Email string `json:"email"`
		Name  string `json:"name,omitempty"`
	} `json:"traits"`
}

// Operator reports the ops-gate flag. Metadata that does not parse means not an operator.
func (k *Identity) Operator() bool {
	var meta map[string]any
	if json.Unmarshal(k.MetadataPublic, &meta) != nil {
		return false
	}
	op, _ := meta[operatorKey].(bool)
	return op
}

// SetOperator writes the ops-gate flag into metadata_public, and keeps every other key that the edge reads.
func (k *Identity) SetOperator(op bool) error {
	meta := map[string]any{}
	if len(k.MetadataPublic) > 0 && string(k.MetadataPublic) != "null" {
		err := json.Unmarshal(k.MetadataPublic, &meta)
		if err != nil {
			return fmt.Errorf("decode metadata_public: %w", err)
		}
	}
	meta[operatorKey] = op
	raw, err := json.Marshal(meta)
	if err != nil {
		return fmt.Errorf("encode metadata_public: %w", err)
	}
	k.MetadataPublic = raw
	return nil
}

func (k *Identity) Flatten() authzsdk.Identity {
	id := authzsdk.Identity{ID: k.ID, Email: k.Traits.Email, Operator: authzsdk.NewOptBool(k.Operator())}
	if k.Traits.Name != "" {
		id.Name = authzsdk.NewOptString(k.Traits.Name)
	}
	return id
}

// ListIdentities forwards only per_page. This Kratos paginates by keyset: `page` is an opaque token, and a numeric
// page returns an empty set.
func (a *Admin) ListIdentities(ctx context.Context, perPage int) ([]authzsdk.Identity, error) {
	u := a.baseURL + "/admin/identities"
	q := url.Values{}
	if perPage > 0 {
		q.Set("per_page", strconv.Itoa(perPage))
	}
	if len(q) > 0 {
		u += "?" + q.Encode()
	}
	var raw []Identity
	err := a.do(ctx, http.MethodGet, u, nil, &raw)
	if err != nil {
		return nil, err
	}
	out := make([]authzsdk.Identity, 0, len(raw))
	for i := range raw {
		out = append(out, raw[i].Flatten())
	}
	return out, nil
}

func (a *Admin) GetIdentity(ctx context.Context, id string) (*Identity, error) {
	var out Identity
	err := a.do(ctx, http.MethodGet, a.identityURL(id), nil, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

func (a *Admin) PutIdentity(ctx context.Context, ident *Identity) (*Identity, error) {
	body := *ident
	body.ID = "" // id is the path, not part of the update body
	var out Identity
	err := a.do(ctx, http.MethodPut, a.identityURL(ident.ID), body, &out)
	if err != nil {
		return nil, err
	}
	return &out, nil
}

// SetOperatorFlag writes metadata_public.operator and nothing else. It patches the one object and does not PUT the
// record, so an edit between the read and the write keeps every other field.
func (a *Admin) SetOperatorFlag(ctx context.Context, id string, op bool) error {
	ident, err := a.GetIdentity(ctx, id)
	if err != nil {
		return err
	}
	err = ident.SetOperator(op)
	if err != nil {
		return err
	}
	patch := []map[string]any{{"op": "add", "path": "/metadata_public", "value": ident.MetadataPublic}}
	return a.do(ctx, http.MethodPatch, a.identityURL(id), patch, nil)
}

func (a *Admin) identityURL(id string) string {
	return a.baseURL + "/admin/identities/" + url.PathEscape(id)
}

// kratosJSON sends a JSON request to the Kratos admin API and decodes a JSON
// response. It requires a 200. A nil reqBody sends no body, and a nil out skips
// decoding.
func (a *Admin) do(ctx context.Context, method, u string, reqBody any, out any) error {
	var reader io.Reader
	if reqBody != nil {
		b, err := json.Marshal(reqBody)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, reader)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	if reqBody != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("call kratos: %w", err)
	}
	defer func() {
		closeErr := resp.Body.Close()
		if closeErr != nil {
			a.log.Error("close kratos response body", "err", closeErr)
		}
	}()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("kratos %d: %s", resp.StatusCode, b)
	}
	if out == nil {
		return nil
	}
	err = json.NewDecoder(resp.Body).Decode(out)
	if err != nil {
		return fmt.Errorf("decode kratos response: %w", err)
	}
	return nil
}
