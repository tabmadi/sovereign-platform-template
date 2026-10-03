package activities

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"

	"github.com/google/uuid"
)

// maxExportBytes keeps an export under Temporal's payload limit of 2 MB, with room for the history's own fields. An
// export larger than this fails and says why. It does not arrive cut short.
const maxExportBytes = 1_500_000

// erasedPrefix marks an identifier that an erasure already replaced. The services skip it when they list subjects.
const erasedPrefix = "erased-"

// identityShape is a Kratos identity id. Anything else in an identifier column, such as a service account name, is
// not a person, and the retention sweep leaves it alone.
var identityShape = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// The services that hold personal data, by the name that the erasure workflow passes.
const (
	storeOrders    = "orders"
	storeOrgs      = "orgs"
	storeAnalytics = "analytics"
)

// subjectStores are the services that hold personal data, per docs/reference/data-classes.md. Payment and catalog
// tag no identifier column, so an erasure has nothing to change there.
func (a *Activities) subjectStores() map[string]string {
	return map[string]string{
		storeOrders:    a.cfg.OrdersAPI,
		storeOrgs:      a.cfg.OrgsAPI,
		storeAnalytics: a.cfg.AnalyticsAPI,
	}
}

// subjectURL is a service's subject API for one identity, or the list of its subjects when identityID is empty.
func (a *Activities) subjectURL(service, identityID string) (string, bool, error) {
	base, ok := a.subjectStores()[service]
	if !ok {
		return "", false, nil
	}
	if base == "" {
		return "", true, fmt.Errorf("the %s API URL is not set", service)
	}
	u := fmt.Sprintf("%s/api/subject-data/%s", base, service)
	if identityID != "" {
		u += "/" + url.PathEscape(identityID)
	}
	return u, true, nil
}

// NewPseudonym is the replacement for one subject's identity, the same in every store, per ADR-0301.
func NewPseudonym() string {
	return erasedPrefix + uuid.NewString()
}

// EraseServiceDataActivity runs per service, not as one query across every database, per ADR-0301. Each service owns
// its schema, and the choice to delete or anonymise is per data class. A second run changes nothing.
func (a *Activities) EraseServiceDataActivity(ctx context.Context, service, identityID, pseudonym string) error {
	endpoint, holds, err := a.subjectURL(service, identityID)
	if err != nil {
		return err
	}
	if !holds {
		a.log.InfoContext(ctx, "service holds no personal data", "service", service)
		return nil
	}
	var result map[string]int
	err = a.do(
		ctx,
		http.MethodPost,
		endpoint+"/erase",
		nil,
		map[string]string{"pseudonym": pseudonym},
		&result,
		http.StatusOK,
	)
	if err != nil {
		return fmt.Errorf("erase %s: %w", service, err)
	}
	a.log.InfoContext(ctx, "service data erased", "service", service, "rows", result)
	return nil
}

// EraseIdentityActivity deletes the Kratos identity, which also ends its sessions. An identity that is already gone
// is the result that a retry wants, so a 404 succeeds.
func (a *Activities) EraseIdentityActivity(ctx context.Context, identityID string) error {
	if a.cfg.KratosAdmin == "" {
		return errors.New("KRATOS_ADMIN_URL is not set")
	}
	err := a.do(
		ctx,
		http.MethodDelete,
		a.cfg.KratosAdmin+"/admin/identities/"+url.PathEscape(identityID),
		nil,
		nil,
		nil,
		http.StatusNoContent,
		http.StatusNotFound,
	)
	if err != nil {
		return fmt.Errorf("erase identity: %w", err)
	}
	a.log.InfoContext(ctx, "identity erased")
	return nil
}

// EraseAuthzTuplesActivity runs last in the workflow. While the tuples exist, the services can still answer questions
// about the subject, so a failed run is safe to retry.
func (a *Activities) EraseAuthzTuplesActivity(ctx context.Context, identityID string) error {
	fga, err := a.openFGA(ctx)
	if err != nil {
		return err
	}
	tuples, err := fga.subjectTuples(ctx, "user:"+identityID)
	if err != nil {
		return err
	}
	err = fga.delete(ctx, tuples)
	if err != nil {
		return err
	}
	a.log.InfoContext(ctx, "authz tuples erased", "tuples", len(tuples))
	return nil
}

// subjectExport is the document that a subject access request returns, per GDPR Art. 15 and 20.
type subjectExport struct {
	IdentityID string                     `json:"identity_id"`
	Identity   json.RawMessage            `json:"identity"`
	Stores     map[string]json.RawMessage `json:"stores"`
	Tuples     []tuple                    `json:"authz_tuples"`
}

// ExportSubjectDataActivity builds the subject-access export and returns it as JSON. It reads the stores in the order
// that erasure writes them, and the tuples last.
func (a *Activities) ExportSubjectDataActivity(ctx context.Context, identityID string) (string, error) {
	doc := subjectExport{IdentityID: identityID, Stores: map[string]json.RawMessage{}}

	if a.cfg.KratosAdmin == "" {
		return "", errors.New("KRATOS_ADMIN_URL is not set")
	}
	var identity json.RawMessage
	err := a.do(
		ctx,
		http.MethodGet,
		a.cfg.KratosAdmin+"/admin/identities/"+url.PathEscape(identityID),
		nil,
		nil,
		&identity,
		http.StatusOK,
	)
	switch {
	case isStatus(err, http.StatusNotFound):
		doc.Identity = json.RawMessage("null")
	case err != nil:
		return "", fmt.Errorf("export identity: %w", err)
	default:
		doc.Identity = identity
	}

	for _, service := range []string{storeOrgs, storeOrders, storeAnalytics} {
		endpoint, _, err := a.subjectURL(service, identityID)
		if err != nil {
			return "", err
		}
		var data json.RawMessage
		err = a.do(ctx, http.MethodGet, endpoint, nil, nil, &data, http.StatusOK)
		if err != nil {
			return "", fmt.Errorf("export %s: %w", service, err)
		}
		doc.Stores[service] = data
	}

	fga, err := a.openFGA(ctx)
	if err != nil {
		return "", err
	}
	doc.Tuples, err = fga.subjectTuples(ctx, "user:"+identityID)
	if err != nil {
		return "", err
	}

	out, err := json.Marshal(doc)
	if err != nil {
		return "", fmt.Errorf("marshal export: %w", err)
	}
	if len(out) > maxExportBytes {
		return "", fmt.Errorf(
			"the export is %d bytes, over the %d that a workflow result can carry",
			len(out),
			maxExportBytes,
		)
	}
	a.log.InfoContext(ctx, "subject export built", "bytes", len(out), "tuples", len(doc.Tuples))
	return string(out), nil
}

// ApplyRetentionActivity runs the daily pass, per ADR-0301. Analytics drops its expired months. Then the sweep finds
// every identifier whose Kratos identity is gone, and erases it in every store and in OpenFGA. An identity can
// disappear without an erasure request, such as by a delete in the admin console, and the sweep covers that case.
func (a *Activities) ApplyRetentionActivity(ctx context.Context) error {
	if a.cfg.AnalyticsAPI == "" {
		return errors.New("ANALYTICS_API_URL is not set")
	}
	var partitions map[string]any
	err := a.do(
		ctx,
		http.MethodPost,
		a.cfg.AnalyticsAPI+"/api/analytics/retention",
		nil,
		nil,
		&partitions,
		http.StatusOK,
	)
	if err != nil {
		return fmt.Errorf("analytics retention: %w", err)
	}
	a.log.InfoContext(ctx, "analytics retention applied", "result", partitions)

	orphans, err := a.orphans(ctx)
	if err != nil {
		return err
	}
	for _, id := range orphans {
		pseudonym := NewPseudonym()
		for service := range a.subjectStores() {
			err = a.EraseServiceDataActivity(ctx, service, id, pseudonym)
			if err != nil {
				return err
			}
		}
		err = a.EraseAuthzTuplesActivity(ctx, id)
		if err != nil {
			return err
		}
	}
	a.log.InfoContext(ctx, "retention sweep done", "orphans_erased", len(orphans))
	return nil
}

// orphans lists every subject id in every store whose Kratos identity no longer exists. Only a 404 counts as gone.
// Any other failure stops the pass, because a Kratos outage must not read as every account being deleted.
func (a *Activities) orphans(ctx context.Context) ([]string, error) {
	if a.cfg.KratosAdmin == "" {
		return nil, errors.New("KRATOS_ADMIN_URL is not set")
	}
	seen := map[string]bool{}
	var out []string
	for service := range a.subjectStores() {
		ids, err := a.subjects(ctx, service)
		if err != nil {
			return nil, err
		}
		for _, id := range ids {
			if seen[id] || !identityShape.MatchString(id) {
				continue
			}
			seen[id] = true
			err = a.do(
				ctx,
				http.MethodGet,
				a.cfg.KratosAdmin+"/admin/identities/"+url.PathEscape(id),
				nil,
				nil,
				nil,
				http.StatusOK,
			)
			if isStatus(err, http.StatusNotFound) {
				out = append(out, id)
				continue
			}
			if err != nil {
				return nil, fmt.Errorf("look up identity: %w", err)
			}
		}
	}
	return out, nil
}

// subjects reads every page of one store's subject list.
func (a *Activities) subjects(ctx context.Context, service string) ([]string, error) {
	endpoint, _, err := a.subjectURL(service, "")
	if err != nil {
		return nil, err
	}
	var out []string
	after := ""
	for {
		var page struct {
			Subjects []string `json:"subjects"`
			Next     string   `json:"next"`
		}
		err = a.do(
			ctx,
			http.MethodGet,
			endpoint+"?limit=1000&after="+url.QueryEscape(after),
			nil,
			nil,
			&page,
			http.StatusOK,
		)
		if err != nil {
			return nil, fmt.Errorf("list %s subjects: %w", service, err)
		}
		out = append(out, page.Subjects...)
		if page.Next == "" {
			return out, nil
		}
		after = page.Next
	}
}
