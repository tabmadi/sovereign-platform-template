package handlers

import (
	"context"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	orgs "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/orgs"
	"github.com/tabmadi/sovereign-platform-template/services/orgs/internal/store"
)

// defaultSubjectPage is the page size when the caller names none.
const defaultSubjectPage = 500

// The three handlers below answer the platform worker, east-west, per ADR-0301. Like OnIdentityCreated, they have no
// edge route, and a NetworkPolicy admits the caller. So they carry no Checker call.

// ListMemberSubjects pages through the users that hold memberships, for the retention sweep.
func (h *Handlers) ListMemberSubjects(
	ctx context.Context, params orgs.ListMemberSubjectsParams,
) (*orgs.SubjectPage, error) {
	limit := params.Limit.Or(defaultSubjectPage)
	ids, err := h.q.ListMemberSubjects(
		ctx,
		store.ListMemberSubjectsParams{
			After:    params.After.Or(""),
			PageSize: int64(limit),
		},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	page := &orgs.SubjectPage{Subjects: ids}
	if page.Subjects == nil {
		page.Subjects = []string{}
	}
	if len(ids) == limit {
		page.Next = orgs.NewOptString(ids[len(ids)-1])
	}
	return page, nil
}

// ExportOrgsSubject reads every membership of the subject, per ADR-0301.
func (h *Handlers) ExportOrgsSubject(
	ctx context.Context, params orgs.ExportOrgsSubjectParams,
) (*orgs.SubjectMemberships, error) {
	rows, err := h.q.ExportSubjectMemberships(ctx, params.IdentityID)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	out := &orgs.SubjectMemberships{Memberships: make([]orgs.SubjectMembership, 0, len(rows))}
	for _, r := range rows {
		out.Memberships = append(
			out.Memberships,
			orgs.SubjectMembership{
				OrgID:   orgID(r.ID),
				OrgName: r.Name,
				Role:    orgs.SubjectMembershipRole(r.Role),
			},
		)
	}
	return out, nil
}

// EraseOrgsSubject anonymises the subject's memberships, per ADR-0301. A second call changes no row.
func (h *Handlers) EraseOrgsSubject(
	ctx context.Context, req *orgs.ErasureRequest, params orgs.EraseOrgsSubjectParams,
) (*orgs.ErasureResult, error) {
	n, err := h.q.EraseSubjectMemberships(
		ctx,
		store.EraseSubjectMembershipsParams{
			IdentityID: params.IdentityID,
			Pseudonym:  req.Pseudonym,
		},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	return &orgs.ErasureResult{Rows: int(n)}, nil
}
