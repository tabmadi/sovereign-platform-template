package activities

import (
	"context"
	"errors"
	"fmt"
	"net/http"
)

// cardinalityTop is how many rows of each ranking the report keeps.
const cardinalityTop = 10

type tsdbStatus struct {
	Data struct {
		HeadStats struct {
			NumSeries int64 `json:"numSeries"`
		} `json:"headStats"`
		SeriesByMetric []countEntry `json:"seriesCountByMetricName"`
		ValuesByLabel  []countEntry `json:"labelValueCountByLabelName"`
		SeriesByPair   []countEntry `json:"seriesCountByLabelValuePair"`
	} `json:"data"`
}

type countEntry struct {
	Name  string `json:"name"`
	Value int64  `json:"value"`
}

// AuditCardinalityActivity is a report, not a threshold. `ActiveSeriesNearCeiling` already alerts on the total, and
// the growing labels are a ranking, per ADR-0500. Prometheus keeps the rankings for its head block, so one call
// answers which metrics and which labels hold the series.
func (a *Activities) AuditCardinalityActivity(ctx context.Context) error {
	if a.cfg.PrometheusAPI == "" {
		return errors.New("PROMETHEUS_URL is not set")
	}
	var status tsdbStatus
	err := a.do(
		ctx,
		http.MethodGet,
		fmt.Sprintf("%s/api/v1/status/tsdb?limit=%d", a.cfg.PrometheusAPI, cardinalityTop),
		nil,
		nil,
		&status,
		http.StatusOK,
	)
	if err != nil {
		return fmt.Errorf("read the TSDB status: %w", err)
	}
	a.log.InfoContext(
		ctx,
		"cardinality audit",
		"series",
		status.Data.HeadStats.NumSeries,
		"series_by_metric",
		status.Data.SeriesByMetric,
		"values_by_label",
		status.Data.ValuesByLabel,
		"series_by_label_pair",
		status.Data.SeriesByPair,
	)
	return nil
}
