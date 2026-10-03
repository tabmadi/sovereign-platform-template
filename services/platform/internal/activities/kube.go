package activities

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

// The service account mount. The token is read again on every call, because the kubelet rotates it.
const (
	// A path, not a credential.
	saTokenPath = "/var/run/secrets/kubernetes.io/serviceaccount/token" // #nosec G101
	saCAPath    = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
)

// kubeClient is the few REST calls that restore verification makes. client-go would add a large dependency tree for
// a create, a get, and a delete.
type kubeClient struct {
	base string
	http *http.Client
}

func inClusterKube() (*kubeClient, error) {
	host, port := os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
	if host == "" || port == "" {
		return nil, errors.New("not in a cluster")
	}
	ca, err := os.ReadFile(saCAPath)
	if err != nil {
		return nil, fmt.Errorf("no service account token mounted: %w", err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		return nil, errors.New("the service account CA is not PEM")
	}
	return &kubeClient{
		base: "https://" + net.JoinHostPort(host, port),
		http: &http.Client{
			Timeout:   time.Minute,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}},
		},
	}, nil
}

// do calls the API and decodes the response into out, when out is not nil. A 404 is returned as a statusError, so a
// caller can treat a missing object as the state that it wanted.
func (k *kubeClient) do(ctx context.Context, method, path string, in, out any, want ...int) error {
	token, err := os.ReadFile(saTokenPath)
	if err != nil {
		return fmt.Errorf("read the service account token: %w", err)
	}
	var body io.Reader
	if in != nil {
		raw, err := json.Marshal(in)
		if err != nil {
			return fmt.Errorf("marshal: %w", err)
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, k.base+path, body)
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Accept", "application/json")
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := k.http.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	ok := false
	for _, w := range want {
		ok = ok || resp.StatusCode == w
	}
	if !ok {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return &statusError{status: resp.StatusCode, detail: string(bytes.TrimSpace(detail))}
	}
	if out == nil {
		return nil
	}
	err = json.NewDecoder(resp.Body).Decode(out)
	if err != nil {
		return fmt.Errorf("decode %s %s: %w", method, path, err)
	}
	return nil
}
