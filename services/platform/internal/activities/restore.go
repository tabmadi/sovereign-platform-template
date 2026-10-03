package activities

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// The scratch cluster's fixed names. One verification runs at a time, because the Schedule runs one workflow.
const (
	restoreCluster = "restore"
	restoreCreds   = "restore-backup-creds"
	// restoreReadyWait is how long one attempt waits for the restore. A large restore outlasts it, and the retry of
	// the activity continues the wait on the same cluster.
	restoreReadyWait = 9 * time.Minute
	restorePoll      = 10 * time.Second
	// fieldName is the `name` key of the manifests below.
	fieldName = "name"
)

type RestoreConfig struct {
	// Namespace holds the scratch cluster, and nothing else.
	Namespace string
	// SourceNamespace and SourceCluster are the cluster whose backups are checked.
	SourceNamespace string
	SourceCluster   string
	BackupSecret    string
	// ReadonlySecret logs in to the source to read its row counts. The worker writes nothing there.
	ReadonlySecret string
	// Databases are the ones compared, one per service that owns a schema.
	Databases []string
}

func restoreConfigFromEnv() RestoreConfig {
	return RestoreConfig{
		Namespace:       envOr("RESTORE_NAMESPACE", "restore-verification"),
		SourceNamespace: envOr("RESTORE_SOURCE_NAMESPACE", "platform"),
		SourceCluster:   envOr("RESTORE_SOURCE_CLUSTER", "postgres"),
		BackupSecret:    envOr("RESTORE_BACKUP_SECRET", "postgres-backup-creds"),
		ReadonlySecret:  envOr("RESTORE_READONLY_SECRET", "postgres-readonly"),
		Databases:       strings.Split(envOr("RESTORE_DATABASES", "analytics,catalog,orders,orgs,payment"), ","),
	}
}

type cnpgCluster struct {
	Spec struct {
		ImageName string `json:"imageName"`
		Storage   struct {
			Size string `json:"size"`
		} `json:"storage"`
		Backup *struct {
			Store map[string]any `json:"barmanObjectStore"`
		} `json:"backup"`
	} `json:"spec"`
	Status struct {
		Phase          string `json:"phase"`
		ReadyInstances int    `json:"readyInstances"`
	} `json:"status"`
}

type kubeSecret struct {
	Data map[string]string `json:"data"`
}

func (a *Activities) needKube() error {
	if a.kube == nil {
		return errors.New("no Kubernetes API in this process: restore verification runs only in a cluster")
	}
	return nil
}

func clusterPath(ns, name string) string {
	return "/apis/postgresql.cnpg.io/v1/namespaces/" + url.PathEscape(ns) + "/clusters/" + url.PathEscape(name)
}

func secretPath(ns, name string) string {
	return "/api/v1/namespaces/" + url.PathEscape(ns) + "/secrets/" + url.PathEscape(name)
}

// RestoreToScratchActivity restores the latest backup of the source cluster into the scratch namespace, per
// ADR-0207. It reads the backup location from the source cluster, so the check always tests what production
// writes. Every step finds what a previous attempt made, so a retry continues and does not start again.
func (a *Activities) RestoreToScratchActivity(ctx context.Context) (string, error) {
	err := a.needKube()
	if err != nil {
		return "", err
	}
	cfg := a.cfg.Restore
	var source cnpgCluster
	err = a.kube.do(
		ctx,
		http.MethodGet,
		clusterPath(cfg.SourceNamespace, cfg.SourceCluster),
		nil,
		&source,
		http.StatusOK,
	)
	if err != nil {
		return "", fmt.Errorf("read the source cluster: %w", err)
	}
	if source.Spec.Backup == nil || source.Spec.Backup.Store == nil {
		return "", fmt.Errorf("cluster %s has no backup to verify", cfg.SourceCluster)
	}
	err = a.copyBackupCreds(ctx)
	if err != nil {
		return "", err
	}
	err = a.kube.do(
		ctx,
		http.MethodPost,
		"/apis/postgresql.cnpg.io/v1/namespaces/"+url.PathEscape(cfg.Namespace)+"/clusters",
		restoreManifest(source, cfg.SourceCluster),
		nil,
		http.StatusCreated,
		http.StatusConflict,
	)
	if err != nil {
		return "", fmt.Errorf("create the scratch cluster: %w", err)
	}
	err = a.waitRestored(ctx)
	if err != nil {
		return "", err
	}
	a.log.InfoContext(ctx, "backup restored into the scratch namespace", "namespace", cfg.Namespace)
	return cfg.Namespace, nil
}

// copyBackupCreds puts the archive's credential in the scratch namespace, because a cluster reads secrets only in its
// own namespace.
func (a *Activities) copyBackupCreds(ctx context.Context) error {
	cfg := a.cfg.Restore
	var creds kubeSecret
	err := a.kube.do(ctx, http.MethodGet, secretPath(cfg.SourceNamespace, cfg.BackupSecret), nil, &creds, http.StatusOK)
	if err != nil {
		return fmt.Errorf("read the backup credentials: %w", err)
	}
	err = a.kube.do(
		ctx,
		http.MethodPost,
		"/api/v1/namespaces/"+url.PathEscape(cfg.Namespace)+"/secrets",
		map[string]any{
			"apiVersion": "v1",
			"kind":       "Secret",
			"metadata":   map[string]any{fieldName: restoreCreds},
			"data":       creds.Data,
		},
		nil,
		http.StatusCreated,
		http.StatusConflict,
	)
	if err != nil {
		return fmt.Errorf("copy the backup credentials: %w", err)
	}
	return nil
}

// waitRestored polls until the scratch cluster has a ready instance, for one attempt's share of the wait.
func (a *Activities) waitRestored(ctx context.Context) error {
	deadline := time.Now().Add(restoreReadyWait)
	for {
		var scratch cnpgCluster
		err := a.kube.do(
			ctx,
			http.MethodGet,
			clusterPath(a.cfg.Restore.Namespace, restoreCluster),
			nil,
			&scratch,
			http.StatusOK,
		)
		if err != nil {
			return fmt.Errorf("read the scratch cluster: %w", err)
		}
		if scratch.Status.ReadyInstances >= 1 && strings.Contains(scratch.Status.Phase, "healthy") {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("the restore is not ready after %s, phase %q", restoreReadyWait, scratch.Status.Phase)
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("wait for the restore: %w", ctx.Err())
		case <-time.After(restorePoll):
		}
	}
}

// restoreManifest is a one-instance cluster that bootstraps from the source's backup store. It reads the store as an
// external cluster, so nothing that it does writes to the source's archive.
func restoreManifest(source cnpgCluster, sourceName string) map[string]any {
	store := map[string]any{}
	for k, v := range source.Spec.Backup.Store {
		// The data settings describe a backup to write. A recovery reads, and CNPG rejects them there.
		if k != "data" {
			store[k] = v
		}
	}
	_, named := store["serverName"]
	if !named {
		store["serverName"] = sourceName
	}
	store["s3Credentials"] = map[string]any{
		"accessKeyId":     map[string]string{fieldName: restoreCreds, "key": "ACCESS_KEY_ID"},
		"secretAccessKey": map[string]string{fieldName: restoreCreds, "key": "SECRET_ACCESS_KEY"},
	}
	return map[string]any{
		"apiVersion": "postgresql.cnpg.io/v1",
		"kind":       "Cluster",
		"metadata":   map[string]any{fieldName: restoreCluster},
		"spec": map[string]any{
			"instances":             1,
			"imageName":             source.Spec.ImageName,
			"enableSuperuserAccess": true,
			"storage":               map[string]any{"size": source.Spec.Storage.Size},
			"resources": map[string]any{
				"requests": map[string]string{"cpu": "50m", "memory": "256Mi"},
				"limits":   map[string]string{"memory": "1Gi"},
			},
			"bootstrap":        map[string]any{"recovery": map[string]any{"source": "archive"}},
			"externalClusters": []any{map[string]any{fieldName: "archive", "barmanObjectStore": store}},
		},
	}
}

// AssertRestoredRowCountsActivity fails unless every table with rows in the source has rows in the restore, per
// ADR-0207. A restore that gives an empty database succeeds, and only a count shows it. Equality is not required,
// because rows after the last archived WAL are not in the restore.
func (a *Activities) AssertRestoredRowCountsActivity(ctx context.Context, namespace string) error {
	err := a.needKube()
	if err != nil {
		return err
	}
	cfg := a.cfg.Restore
	readonly, err := a.secretLogin(ctx, cfg.SourceNamespace, cfg.ReadonlySecret)
	if err != nil {
		return err
	}
	superuser, err := a.secretLogin(ctx, namespace, restoreCluster+"-superuser")
	if err != nil {
		return err
	}
	sourceHost := fmt.Sprintf("%s-rw.%s.svc", cfg.SourceCluster, cfg.SourceNamespace)
	restoreHost := fmt.Sprintf("%s-rw.%s.svc", restoreCluster, namespace)

	var failures []string
	for _, db := range cfg.Databases {
		live, err := rowCounts(ctx, readonly.dsn(sourceHost, db))
		if err != nil {
			return fmt.Errorf("count the source %s: %w", db, err)
		}
		restored, err := rowCounts(ctx, superuser.dsn(restoreHost, db))
		if err != nil {
			failures = append(failures, fmt.Sprintf("%s: %v", db, err))
			continue
		}
		failures = append(failures, compareCounts(db, live, restored)...)
		a.log.InfoContext(ctx, "row counts compared", "database", db, "source", live, "restored", restored)
	}
	if len(failures) > 0 {
		return fmt.Errorf("the restore is not complete: %s", strings.Join(failures, "; "))
	}
	return nil
}

// compareCounts names every table that has rows in the source and none, or no table, in the restore.
func compareCounts(db string, live, restored map[string]int64) []string {
	var out []string
	tables := make([]string, 0, len(live))
	for t := range live {
		tables = append(tables, t)
	}
	sort.Strings(tables)
	for _, t := range tables {
		if live[t] == 0 {
			continue
		}
		got, ok := restored[t]
		switch {
		case !ok:
			out = append(out, fmt.Sprintf("%s.%s is missing", db, t))
		case got == 0:
			out = append(out, fmt.Sprintf("%s.%s is empty, and the source has %d rows", db, t, live[t]))
		}
	}
	return out
}

type login struct{ user, password string }

func (l login) dsn(host, db string) string {
	u := url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(l.user, l.password),
		Host:   host + ":5432",
		Path:   "/" + db,
	}
	return u.String() + "?sslmode=require&connect_timeout=10"
}

func (a *Activities) secretLogin(ctx context.Context, ns, name string) (login, error) {
	var s kubeSecret
	err := a.kube.do(ctx, http.MethodGet, secretPath(ns, name), nil, &s, http.StatusOK)
	if err != nil {
		return login{}, fmt.Errorf("read secret %s/%s: %w", ns, name, err)
	}
	user, err := base64.StdEncoding.DecodeString(s.Data["username"])
	if err != nil {
		return login{}, fmt.Errorf("secret %s/%s: username: %w", ns, name, err)
	}
	password, err := base64.StdEncoding.DecodeString(s.Data["password"])
	if err != nil {
		return login{}, fmt.Errorf("secret %s/%s: password: %w", ns, name, err)
	}
	return login{user: string(user), password: string(password)}, nil
}

// rowCounts counts every table in the public schema. The tables are few and small enough for an exact count.
func rowCounts(ctx context.Context, dsn string) (map[string]int64, error) {
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	defer func() { _ = conn.Close(ctx) }()
	rows, err := conn.Query(
		ctx,
		`
		select table_name::text from information_schema.tables
		where table_schema = 'public' and table_type = 'BASE TABLE'`,
	)
	if err != nil {
		return nil, fmt.Errorf("list tables: %w", err)
	}
	tables, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, fmt.Errorf("list tables: %w", err)
	}
	out := make(map[string]int64, len(tables))
	for _, t := range tables {
		var n int64
		err = conn.QueryRow(ctx, "select count(*) from "+pgx.Identifier{t}.Sanitize()).Scan(&n)
		if err != nil {
			return nil, fmt.Errorf("count %s: %w", t, err)
		}
		out[t] = n
	}
	return out, nil
}

// TeardownScratchRestoreActivity deletes the scratch cluster and its credential, and waits until its volumes are
// gone. A scratch namespace that keeps a volume holds a full copy of production data, so the wait is the point.
func (a *Activities) TeardownScratchRestoreActivity(ctx context.Context, namespace string) error {
	err := a.needKube()
	if err != nil {
		return err
	}
	for _, path := range []string{clusterPath(namespace, restoreCluster), secretPath(namespace, restoreCreds)} {
		err = a.kube.do(
			ctx,
			http.MethodDelete,
			path,
			nil,
			nil,
			http.StatusOK,
			http.StatusAccepted,
			http.StatusNotFound,
		)
		if err != nil {
			return fmt.Errorf("delete %s: %w", path, err)
		}
	}
	deadline := time.Now().Add(restoreReadyWait)
	for {
		var claims struct {
			Items []any `json:"items"`
		}
		err = a.kube.do(
			ctx,
			http.MethodGet,
			"/api/v1/namespaces/"+url.PathEscape(namespace)+"/persistentvolumeclaims",
			nil,
			&claims,
			http.StatusOK,
		)
		if err != nil {
			return fmt.Errorf("list the scratch volumes: %w", err)
		}
		if len(claims.Items) == 0 {
			a.log.InfoContext(ctx, "scratch restore torn down", "namespace", namespace)
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("%d volumes remain in %s after %s", len(claims.Items), namespace, restoreReadyWait)
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("wait for the teardown: %w", ctx.Err())
		case <-time.After(restorePoll):
		}
	}
}
