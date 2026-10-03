package handlers

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	orders "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/orders"
	"github.com/tabmadi/sovereign-platform-template/services/orders/internal/store"
)

// defaultSubjectPage is the page size when the caller names none.
const defaultSubjectPage = 500

// The three handlers below answer the platform worker, east-west, per ADR-0301. They have no edge route, and a
// NetworkPolicy admits only the worker. So they carry no Checker call, like the Kratos webhook of orgs.

// ListOrderSubjects returns at most `limit` owners after `after`, in order. A full page sets `next`.
func (h *Handlers) ListOrderSubjects(
	ctx context.Context, params orders.ListOrderSubjectsParams,
) (*orders.SubjectPage, error) {
	limit := params.Limit.Or(defaultSubjectPage)
	ids, err := h.q.ListOrderSubjects(
		ctx,
		store.ListOrderSubjectsParams{
			After:    params.After.Or(""),
			PageSize: int64(limit),
		},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	page := &orders.SubjectPage{Subjects: ids}
	if page.Subjects == nil {
		page.Subjects = []string{}
	}
	if len(ids) == limit {
		page.Next = orders.NewOptString(ids[len(ids)-1])
	}
	return page, nil
}

// ExportOrdersSubject reads every order that the subject placed, per ADR-0301.
func (h *Handlers) ExportOrdersSubject(
	ctx context.Context, params orders.ExportOrdersSubjectParams,
) (*orders.SubjectOrders, error) {
	rows, err := h.q.ExportSubjectOrders(ctx, pgtype.Text{String: params.IdentityID, Valid: true})
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	out := &orders.SubjectOrders{Orders: make([]orders.Order, 0, len(rows))}
	for _, r := range rows {
		total, err := wireTotal(r.Total, r.Currency)
		if err != nil {
			return nil, err
		}
		out.Orders = append(
			out.Orders,
			orders.Order{
				ID:        orderID(r.ID),
				ProductID: productID(r.ProductID),
				Quantity:  int(r.Quantity),
				Total:     total,
				Status:    orders.OrderStatus(r.Status),
			},
		)
	}
	return out, nil
}

// EraseOrdersSubject anonymises the owner of the subject's orders, per ADR-0301. A second call changes no row.
func (h *Handlers) EraseOrdersSubject(
	ctx context.Context, req *orders.ErasureRequest, params orders.EraseOrdersSubjectParams,
) (*orders.ErasureResult, error) {
	n, err := h.q.EraseSubjectOrders(
		ctx,
		store.EraseSubjectOrdersParams{
			IdentityID: params.IdentityID,
			Pseudonym:  req.Pseudonym,
		},
	)
	if err != nil {
		return nil, apierr.Internal(err.Error())
	}
	return &orders.ErasureResult{Rows: int(n)}, nil
}
