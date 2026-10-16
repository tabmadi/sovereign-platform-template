package handlers

import (
	"encoding/json"
	"testing"
)

// The body that the Faro receiver of otelcol-contrib 0.154.0 writes for one event.
const faroEvent = `timestamp=2026-10-11T18:32:29Z kind=event level=info event_name=marketing.api_key_created ` +
	`event_domain=marketing event_data_owner="personal key" app_name=frontend app_version=probe ` +
	`session_id=probe-session-1 session_attr_isSampled=true browser_mobile=false`

// ANL-005.
func TestParseLogfmt(t *testing.T) {
	t.Parallel()
	got := parseLogfmt(faroEvent)
	want := map[string]string{
		"event_name": "marketing.api_key_created", "event_data_owner": "personal key",
		"session_id": "probe-session-1", "browser_mobile": "false",
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}

// ANL-005.
func TestBatches(t *testing.T) {
	t.Parallel()
	body := map[string]any{"resourceLogs": []any{map[string]any{"scopeLogs": []any{map[string]any{"logRecords": []any{
		map[string]any{"body": map[string]any{"stringValue": faroEvent}},
		map[string]any{"body": map[string]any{"stringValue": "kind=event event_name=page_view session_id=x"}},
	}}}}}}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	var payload otlpLogs
	err = json.Unmarshal(raw, &payload)
	if err != nil {
		t.Fatal(err)
	}
	got := batches(payload)
	if len(got) != 1 || len(got[0].Events) != 1 {
		t.Fatalf("got %d batches, want 1 batch with 1 event", len(got))
	}
	b := got[0]
	if b.SessionID != "probe-session-1" || b.Events[0].Name != "api_key_created" {
		t.Errorf("got session %q and event %q", b.SessionID, b.Events[0].Name)
	}
	props, _ := b.Events[0].Properties.Get()
	if string(props["owner"]) != `"personal key"` {
		t.Errorf("owner = %s", props["owner"])
	}
	class, _ := b.DeviceClass.Get()
	if class != "desktop" {
		t.Errorf("device class = %s", class)
	}
}
