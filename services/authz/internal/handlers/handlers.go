// Package handlers implements the ogen-generated authz.Handler interface: spec-first like every HTTP service, though
// it owns no database (ADR-0303, ADR-0306).
package handlers

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"go.temporal.io/sdk/client"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	authzsdk "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/authz"
	"github.com/tabmadi/sovereign-platform-template/services/authz/internal/kratos"
	"github.com/tabmadi/sovereign-platform-template/services/authz/internal/workflows"
)

const (
	aalLevel2        = "aal2" // operator MFA assurance level (ADR-0304)
	operatorFlagTrue = "true" // metadata_public.operator, when set
	// The task queue this service's worker serves. Named for the service, like
	// every other queue on the platform.
	taskQueue = "authz-queue"
	// Both legs are single calls; the bound covers their retries without holding a console request open for long.
	setOperatorTimeout = 30 * time.Second
)

type Handlers struct {
	checker     authz.Checker
	granter     authz.Granter
	fineGrained bool // when true, also require dashboard:<tool>#view in OpenFGA
	identities  *kratos.Admin
	tc          client.Client
	log         *slog.Logger
}

func New(
	checker authz.Checker,
	granter authz.Granter,
	fineGrained bool,
	tc client.Client,
	log *slog.Logger,
) *Handlers {
	if log == nil {
		log = slog.Default()
	}
	return &Handlers{
		checker:     checker,
		granter:     granter,
		fineGrained: fineGrained,
		identities:  kratos.New(log),
		tc:          tc,
		log:         log,
	}
}

var _ authzsdk.Handler = (*Handlers)(nil)

// Authorize answers in two layers (ADR-0306). Coarse is a claim check — metadata_public.operator and AAL2 — and
// makes no OpenFGA call, so a product-authz outage cannot lock operators out of the dashboards that diagnose it.
// Fine is `dashboard:<tool>#view`, enabled per project. A bare authenticated session never grants tool access.
func (h *Handlers) Authorize(ctx context.Context, req *authzsdk.AuthorizeRequest) (authzsdk.AuthorizeRes, error) {
	allowed, reason, err := h.decide(ctx, req)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	// Auth audit event (ADR-0306): who reached which tool, and the outcome.
	h.log.LogAttrs(
		ctx,
		slog.LevelInfo,
		"ops-authz decision",
		slog.String("subject", req.Subject),
		slog.String("tool", req.Tool),
		slog.Bool("allowed", allowed),
		slog.String("reason", reason),
	)
	if !allowed {
		// A deny is the expected answer here, not a failure: Oathkeeper reads the
		// body. It still carries the platform error shape (ADR-0303) so a client
		// parses one thing whatever produced it.
		denied := apierr.Forbidden(reason).WithTrace(ctx)
		return &authzsdk.Problem{
			Type:   denied.Type,
			Title:  denied.Title,
			Status: denied.Status,
			Detail: authzsdk.NewOptString(denied.Detail),
		}, nil
	}
	return &authzsdk.AuthorizeOK{}, nil
}

// CheckRelation is the non-Go door to the same Checker the services use (ADR-0304, ADR-0700).
// A deny is a 200 with `allowed: false`, not an error: an exception would make "you may not see this"
// indistinguishable from "authz is down".
func (h *Handlers) CheckRelation(
	ctx context.Context, req *authzsdk.RelationCheck,
) (*authzsdk.RelationDecision, error) {
	allowed, err := h.checker.Allowed(ctx, req.Subject, req.Relation, req.Object)
	if err != nil {
		h.log.Error("check relation", "err", err, "object", req.Object)
		return nil, apierr.Internal("failed to check relation")
	}
	h.log.LogAttrs(
		ctx,
		slog.LevelInfo,
		"relation decision",
		slog.String("subject", req.Subject),
		slog.String("relation", req.Relation),
		slog.String("object", req.Object),
		slog.Bool("allowed", allowed),
	)
	return &authzsdk.RelationDecision{Allowed: allowed}, nil
}

// ListIdentities: Only authz may reach the Kratos admin API (network-policies/30-ory.yaml), so the console fetches
// through here rather than talking to Kratos directly (ADR-0401).
func (h *Handlers) ListIdentities(
	ctx context.Context, params authzsdk.ListIdentitiesParams,
) ([]authzsdk.Identity, error) {
	ids, err := h.identities.ListIdentities(ctx, params.PerPage.Or(0))
	if err != nil {
		h.log.Error("list kratos identities", "err", err)
		return nil, apierr.Internal("failed to list identities")
	}
	return ids, nil
}

// GetIdentity returns one identity by id — the console's edit-form prefill (ADR-0401).
func (h *Handlers) GetIdentity(ctx context.Context, params authzsdk.GetIdentityParams) (*authzsdk.Identity, error) {
	full, err := h.identities.GetIdentity(ctx, params.ID)
	if err != nil {
		h.log.Error("get kratos identity", "err", err, "id", params.ID)
		return nil, apierr.Internal("failed to get identity")
	}
	id := full.Flatten()
	return &id, nil
}

// UpdateIdentity: a name is a PUT of the whole record; operator is the SetOperator dual write, the one way to become
// an operator (ADR-0304), and runs after the PUT so the PUT cannot overwrite the flag it writes.
func (h *Handlers) UpdateIdentity(
	ctx context.Context, req *authzsdk.IdentityUpdate, params authzsdk.UpdateIdentityParams,
) (*authzsdk.Identity, error) {
	full, err := h.identities.GetIdentity(ctx, params.ID)
	if err != nil {
		h.log.Error("get kratos identity", "err", err, "id", params.ID)
		return nil, apierr.Internal("failed to load identity")
	}
	name, ok := req.Name.Get()
	if ok && name != full.Traits.Name {
		full.Traits.Name = name
		full, err = h.identities.PutIdentity(ctx, full)
		if err != nil {
			h.log.Error("update kratos identity", "err", err, "id", params.ID)
			return nil, apierr.Internal("failed to update identity")
		}
	}
	operator, ok := req.Operator.Get()
	if ok && operator != full.Operator() {
		err = h.setOperator(ctx, params.ID, operator)
		if err != nil {
			return nil, err
		}
		full, err = h.identities.GetIdentity(ctx, params.ID)
		if err != nil {
			h.log.Error("get kratos identity", "err", err, "id", params.ID)
			return nil, apierr.Internal("failed to load identity")
		}
	}
	id := full.Flatten()
	return &id, nil
}

// NewError maps a handler error onto the generated RFC 9457 response (ADR-0303).
func (h *Handlers) NewError(ctx context.Context, err error) *authzsdk.ErrorStatusCode {
	e := apierr.Resolved(ctx, err)

	problem := authzsdk.Problem{Type: e.Type, Title: e.Title, Status: e.Status}
	if e.Detail != "" {
		problem.Detail = authzsdk.NewOptString(e.Detail)
	}
	if e.TraceID != "" {
		problem.TraceID = authzsdk.NewOptString(e.TraceID)
	}
	for _, v := range e.Errors {
		problem.Errors = append(problem.Errors, authzsdk.ProblemErrorsItem{Pointer: v.Pointer, Message: v.Message})
	}
	return &authzsdk.ErrorStatusCode{StatusCode: e.Status, Response: problem}
}

// setOperator runs SetOperator to completion. The workflow id names the identity, so two concurrent edits of one
// identity share a run rather than racing two dual writes.
func (h *Handlers) setOperator(ctx context.Context, identityID string, op bool) error {
	ctx, cancel := context.WithTimeout(ctx, setOperatorTimeout)
	defer cancel()
	run, err := h.tc.ExecuteWorkflow(
		ctx,
		client.StartWorkflowOptions{ID: "set-operator-" + identityID, TaskQueue: taskQueue},
		workflows.SetOperator,
		workflows.SetOperatorInput{IdentityID: identityID, Operator: op},
	)
	if err == nil {
		err = run.Get(ctx, nil)
	}
	if err != nil {
		h.log.Error("set operator", "err", err, "id", identityID, "operator", op)
		return apierr.Internal("failed to change the operator role")
	}
	return nil
}

// decide returns the allow/deny decision and its reason. The error is non-nil only
// on an infrastructure failure (a OpenFGA call error), never on a plain deny.
func (h *Handlers) decide(ctx context.Context, req *authzsdk.AuthorizeRequest) (bool, string, error) {
	if req.Subject == "" {
		return false, "no session", nil
	}
	// Coarse gate — a CLAIM, not a Checker call: AAL2 session and the operator flag in metadata_public, which only the
	// admin API writes. No OpenFGA is consulted, so a product-authz outage never locks operators out.
	if req.Aal != aalLevel2 {
		return false, "aal2 required", nil
	}
	if req.Operator != operatorFlagTrue {
		return false, "not an operator", nil
	}
	// Fine gate (optional): per-tool grant in OpenFGA. Skipped unless enabled.
	if h.fineGrained {
		ok, err := h.checker.Allowed(ctx, "user:"+req.Subject, "view", "dashboard:"+req.Tool)
		if err != nil {
			return false, "", fmt.Errorf("checker: %w", err)
		}
		if !ok {
			return false, "no grant for " + req.Tool, nil
		}
	}
	return true, "ok", nil
}
