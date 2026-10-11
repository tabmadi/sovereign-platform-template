package handlers

import (
	"compress/gzip"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-faster/jx"

	analytics "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/analytics"
)

const (
	marketingPrefix = "marketing."
	eventDataPrefix = "event_data_"
	maxOTLPBytes    = 4 << 20
)

// otlpLogs is the part of an OTLP/HTTP JSON logs export that a Faro event fills. The Faro receiver writes the whole
// event as a logfmt body, so the body is the one field read.
type otlpLogs struct {
	ResourceLogs []struct {
		ScopeLogs []struct {
			LogRecords []struct {
				Body struct {
					StringValue string `json:"stringValue"`
				} `json:"body"`
			} `json:"logRecords"`
		} `json:"scopeLogs"`
	} `json:"resourceLogs"`
}

// OTLPLogs serves `POST /otlp/v1/logs`: the collector's export of `marketing.*` browser events, per ADR-0700. OTLP
// names its fields in camelCase, so the route sits beside the generated server and not in the spec. Each session's
// events go through RecordEvents, which drops a session that has no grant.
func (h *Handlers) OTLPLogs(w http.ResponseWriter, r *http.Request) {
	var body io.Reader = r.Body
	// The collector's OTLP/HTTP exporter compresses with gzip by default.
	if r.Header.Get("Content-Encoding") == "gzip" {
		zr, err := gzip.NewReader(r.Body)
		if err != nil {
			http.Error(w, "the body is not gzip", http.StatusBadRequest)
			return
		}
		defer func() { _ = zr.Close() }()
		body = zr
	}
	var payload otlpLogs
	err := json.NewDecoder(io.LimitReader(body, maxOTLPBytes)).Decode(&payload)
	if err != nil {
		http.Error(w, "the body is not an OTLP JSON logs export", http.StatusBadRequest)
		return
	}
	for _, batch := range batches(payload) {
		_, err = h.RecordEvents(r.Context(), batch)
		if err != nil {
			// A failed store is worth a retry, so the collector gets a server error.
			http.Error(w, "failed to record events", http.StatusServiceUnavailable)
			return
		}
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte("{}"))
}

// batches groups the marketing events of an export by session. A record that is not a marketing event is skipped.
func batches(payload otlpLogs) []*analytics.EventBatch {
	bySession := map[string]*analytics.EventBatch{}
	var order []string
	for _, rl := range payload.ResourceLogs {
		for _, sl := range rl.ScopeLogs {
			for _, rec := range sl.LogRecords {
				fields := parseLogfmt(rec.Body.StringValue)
				event, ok := eventOf(fields)
				if !ok {
					continue
				}
				session := fields["session_id"]
				b, seen := bySession[session]
				if !seen {
					b = batchOf(fields)
					bySession[session] = b
					order = append(order, session)
				}
				b.Events = append(b.Events, event)
			}
		}
	}
	out := make([]*analytics.EventBatch, 0, len(order))
	for _, s := range order {
		out = append(out, bySession[s])
	}
	return out
}

func batchOf(fields map[string]string) *analytics.EventBatch {
	b := &analytics.EventBatch{SessionID: fields["session_id"]}
	user := fields["user_id"]
	if user != "" {
		b.IdentityID = analytics.NewOptString(user)
	}
	switch fields["browser_mobile"] {
	case "true":
		b.DeviceClass = analytics.NewOptEventBatchDeviceClass(analytics.EventBatchDeviceClassMobile)
	case "false":
		b.DeviceClass = analytics.NewOptEventBatchDeviceClass(analytics.EventBatchDeviceClassDesktop)
	}
	return b
}

// eventOf reads one event. The `marketing.` prefix routes the event in the collector, and it is not part of the name.
func eventOf(fields map[string]string) (analytics.Event, bool) {
	name, ok := strings.CutPrefix(fields["event_name"], marketingPrefix)
	if !ok || name == "" || fields["session_id"] == "" {
		return analytics.Event{}, false
	}
	at, err := time.Parse(time.RFC3339Nano, fields["timestamp"])
	if err != nil {
		at = time.Now().UTC()
	}
	event := analytics.Event{Name: name, OccurredAt: at}
	props := analytics.EventProperties{}
	for k, v := range fields {
		key, ok := strings.CutPrefix(k, eventDataPrefix)
		if ok {
			props[key] = jx.Raw(strconv.AppendQuote(nil, v))
		}
	}
	if len(props) > 0 {
		event.Properties = analytics.NewOptEventProperties(props)
	}
	return event, true
}

var errUnterminated = errors.New("unterminated quoted value")

// parseLogfmt reads `key=value` pairs separated by spaces. A quoted value uses Go string escapes, as the Faro receiver
// writes it. A malformed pair ends the parse, and the pairs before it are kept.
func parseLogfmt(line string) map[string]string {
	out := map[string]string{}
	for line != "" {
		line = strings.TrimLeft(line, " ")
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			return out
		}
		key := line[:eq]
		value, rest, err := logfmtValue(line[eq+1:])
		if err != nil {
			return out
		}
		out[key] = value
		line = rest
	}
	return out
}

func logfmtValue(s string) (string, string, error) {
	if !strings.HasPrefix(s, `"`) {
		end := strings.IndexByte(s, ' ')
		if end < 0 {
			return s, "", nil
		}
		return s[:end], s[end:], nil
	}
	for i := 1; i < len(s); i++ {
		switch s[i] {
		case '\\':
			i++
		case '"':
			v, err := strconv.Unquote(s[:i+1])
			if err != nil {
				return "", "", errUnterminated
			}
			return v, s[i+1:], nil
		}
	}
	return "", "", errUnterminated
}
