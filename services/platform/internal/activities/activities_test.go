package activities

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

const (
	subject = "0b6f6f2e-5d3b-4f39-9a5e-3c7a1d1e2f40"
	gone    = "9a1c2b3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
)

// fake is every dependency of the worker in one server. It records each call, so a test can assert what was sent.
type fake struct {
	mu    sync.Mutex
	calls []string
	// writes holds the body of each OpenFGA write.
	writes []string
	// subjects is what each store's subject list returns.
	subjects map[string][]string
	// identities are the Kratos identities that exist.
	identities map[string]bool
}

func (f *fake) record(r *http.Request, body string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, r.Method+" "+r.URL.Path)
	if strings.HasSuffix(r.URL.Path, "/write") {
		f.writes = append(f.writes, body)
	}
}

func (f *fake) called(prefix string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, c := range f.calls {
		if strings.HasPrefix(c, prefix) {
			n++
		}
	}
	return n
}

func newFake(t *testing.T) (*fake, *Activities) {
	t.Helper()
	f := &fake{
		subjects:   map[string][]string{storeOrders: {subject, gone, "admin-console"}, storeOrgs: {gone}},
		identities: map[string]bool{subject: true},
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/admin/identities/", f.kratos)
	mux.HandleFunc("/stores", reply(`{"stores":[{"id":"S1","name":"platform"}]}`))
	model := `{"authorization_models":[{"type_definitions":[{"type":"user"},{"type":"org"},{"type":"group"}]}]}`
	mux.HandleFunc("/stores/S1/authorization-models", reply(model))
	mux.HandleFunc("/stores/S1/read", f.read)
	mux.HandleFunc("/stores/S1/write", reply(`{}`))
	mux.HandleFunc("/analytics/retention", reply(`{"partitions_created":[]}`))
	mux.HandleFunc("/subject-data/", f.store)
	mux.HandleFunc("/api/v1/status/tsdb", reply(`{"data":{"headStats":{"numSeries":12}}}`))
	mux.HandleFunc("/issues", issue)
	recording := func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		f.record(r, string(raw))
		r.Body = io.NopCloser(strings.NewReader(string(raw)))
		w.Header().Set("Content-Type", "application/json")
		mux.ServeHTTP(w, r)
	}
	srv := httptest.NewServer(http.HandlerFunc(recording))
	t.Cleanup(srv.Close)
	cfg := Config{
		ForgeAPI: srv.URL, ForgeToken: "T",
		AnalyticsAPI: srv.URL, OrdersAPI: srv.URL, OrgsAPI: srv.URL,
		KratosAdmin: srv.URL, OpenFGAAPI: srv.URL, OpenFGAKey: "K", OpenFGAStore: "platform",
		PrometheusAPI: srv.URL,
	}
	return f, &Activities{log: slog.New(slog.DiscardHandler), cfg: cfg, http: srv.Client()}
}

func reply(body string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) { _, _ = io.WriteString(w, body) }
}

func (f *fake) kratos(w http.ResponseWriter, r *http.Request) {
	if !f.identities[strings.TrimPrefix(r.URL.Path, "/admin/identities/")] {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	if r.Method == http.MethodDelete {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	_, _ = io.WriteString(w, `{"id":"`+subject+`","traits":{"email":"a@b.example"}}`)
}

// read answers two pages for `org` and one for `group`, so a test sees that every type and page is read.
func (f *fake) read(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Key   map[string]string `json:"tuple_key"`
		Token string            `json:"continuation_token"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	key := func(relation, object string) string {
		return `{"key":{"user":"user:` + subject + `","relation":"` + relation + `","object":"` + object + `"}}`
	}
	switch {
	case req.Key["object"] == "org:" && req.Token == "":
		_, _ = io.WriteString(w, `{"tuples":[`+key("admin", "org:o1")+`],"continuation_token":"next"}`)
	case req.Key["object"] == "org:":
		_, _ = io.WriteString(w, `{"tuples":[`+key("member", "org:o2")+`]}`)
	case req.Key["object"] == "group:":
		_, _ = io.WriteString(w, `{"tuples":[`+key("member", "group:operator")+`]}`)
	default:
		_, _ = io.WriteString(w, `{"tuples":[]}`)
	}
}

func (f *fake) store(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/subject-data/"), "/")
	switch {
	case len(parts) == 1:
		ids, err := json.Marshal(append([]string{}, f.subjects[parts[0]]...))
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		_, _ = w.Write(append(append([]byte(`{"subjects":`), ids...), '}'))
	case parts[len(parts)-1] == "erase":
		_, _ = io.WriteString(w, `{"rows":1}`)
	default:
		_, _ = io.WriteString(w, `{"data":[]}`)
	}
}

func issue(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Authorization") != "token T" {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	w.WriteHeader(http.StatusCreated)
	_, _ = io.WriteString(w, `{"number":7}`)
}

func TestEraseServiceData(t *testing.T) {
	t.Parallel()
	f, a := newFake(t)
	ctx := context.Background()
	for _, svc := range []string{storeOrders, "payment", "catalog"} {
		err := a.EraseServiceDataActivity(ctx, svc, subject, "erased-x")
		if err != nil {
			t.Fatalf("%s: %v", svc, err)
		}
	}
	if n := f.called("POST /subject-data/orders/" + subject + "/erase"); n != 1 {
		t.Errorf("orders erase calls = %d, want 1", n)
	}
	if n := f.called("POST /subject-data/payment"); n != 0 {
		t.Errorf("payment holds no personal data, and got %d calls", n)
	}

	a.cfg.OrdersAPI = ""
	err := a.EraseServiceDataActivity(ctx, storeOrders, subject, "erased-x")
	if err == nil || !strings.Contains(err.Error(), "not set") {
		t.Errorf("a missing URL must fail, got %v", err)
	}
}

func TestEraseIdentityAcceptsAMissingIdentity(t *testing.T) {
	t.Parallel()
	f, a := newFake(t)
	for _, id := range []string{subject, gone} {
		err := a.EraseIdentityActivity(context.Background(), id)
		if err != nil {
			t.Fatalf("%s: %v", id, err)
		}
	}
	if n := f.called("DELETE /admin/identities/"); n != 2 {
		t.Errorf("deletes = %d, want 2", n)
	}
}

func TestEraseAuthzTuplesReadsEveryTypeAndPage(t *testing.T) {
	t.Parallel()
	f, a := newFake(t)
	err := a.EraseAuthzTuplesActivity(context.Background(), subject)
	if err != nil {
		t.Fatal(err)
	}
	// user, two pages of org, and group.
	if n := f.called("POST /stores/S1/read"); n != 4 {
		t.Errorf("reads = %d, want 4", n)
	}
	if len(f.writes) != 1 {
		t.Fatalf("writes = %d, want 1", len(f.writes))
	}
	for _, want := range []string{"org:o1", "org:o2", "group:operator", `"user:` + subject} {
		if !strings.Contains(f.writes[0], want) {
			t.Errorf("the delete misses %s: %s", want, f.writes[0])
		}
	}
}

func TestExportSubjectData(t *testing.T) {
	t.Parallel()
	_, a := newFake(t)
	out, err := a.ExportSubjectDataActivity(context.Background(), subject)
	if err != nil {
		t.Fatal(err)
	}
	var doc subjectExport
	err = json.Unmarshal([]byte(out), &doc)
	if err != nil {
		t.Fatal(err)
	}
	if string(doc.Identity) == "null" || len(doc.Stores) != 3 || len(doc.Tuples) != 3 {
		t.Errorf("export = %s", out)
	}

	out, err = a.ExportSubjectDataActivity(context.Background(), gone)
	if err != nil || !strings.Contains(out, `"identity":null`) {
		t.Errorf("an identity that is gone exports as null: %v %s", err, out)
	}
}

// The sweep erases only the identity that Kratos no longer has. A service account and a live identity stay.
func TestRetentionErasesOnlyOrphans(t *testing.T) {
	t.Parallel()
	f, a := newFake(t)
	err := a.ApplyRetentionActivity(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if n := f.called("POST /analytics/retention"); n != 1 {
		t.Errorf("analytics retention calls = %d, want 1", n)
	}
	for _, svc := range []string{storeOrders, storeOrgs, storeAnalytics} {
		if n := f.called("POST /subject-data/" + svc + "/" + gone + "/erase"); n != 1 {
			t.Errorf("%s erase of the orphan = %d, want 1", svc, n)
		}
	}
	if n := f.called("POST /subject-data/orders/" + subject + "/erase"); n != 0 {
		t.Errorf("a live identity was erased")
	}
	if n := f.called("POST /subject-data/orders/admin-console/erase"); n != 0 {
		t.Errorf("a service account was erased")
	}
}

func TestCardinalityAndIssue(t *testing.T) {
	t.Parallel()
	_, a := newFake(t)
	err := a.AuditCardinalityActivity(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	err = a.OpenTrackingIssueActivity(context.Background(), "t", "b")
	if err != nil {
		t.Fatal(err)
	}
	a.cfg.ForgeToken = "wrong"
	err = a.OpenTrackingIssueActivity(context.Background(), "t", "b")
	if err == nil {
		t.Error("a refused issue must fail")
	}
}

func TestRestoreManifest(t *testing.T) {
	t.Parallel()
	var source cnpgCluster
	raw := `{"spec":{"imageName":"pg:17","storage":{"size":"5Gi"},"backup":{"barmanObjectStore":` +
		`{"destinationPath":"s3://b/","data":{"compression":"gzip"},"wal":{"compression":"gzip"}}}}}`
	err := json.Unmarshal([]byte(raw), &source)
	if err != nil {
		t.Fatal(err)
	}
	manifest, err := json.Marshal(restoreManifest(source, "postgres"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(manifest)
	wants := []string{
		`"serverName":"postgres"`, `"source":"archive"`, `"name":"restore-backup-creds"`, `"imageName":"pg:17"`,
		`"size":"5Gi"`,
	}
	for _, want := range wants {
		if !strings.Contains(got, want) {
			t.Errorf("manifest misses %s: %s", want, got)
		}
	}
	if strings.Contains(got, `"data"`) {
		t.Errorf("a recovery must not carry the backup's data settings: %s", got)
	}
}

func TestCompareCounts(t *testing.T) {
	t.Parallel()
	live := map[string]int64{"items": 3, "empty": 0, "lost": 2, "drained": 5}
	restored := map[string]int64{"items": 2, "empty": 0, "drained": 0}
	got := strings.Join(compareCounts("shop", live, restored), "; ")
	want := "shop.drained is empty, and the source has 5 rows; shop.lost is missing"
	if got != want {
		t.Errorf("compareCounts = %q, want %q", got, want)
	}
}
