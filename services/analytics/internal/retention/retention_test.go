package retention

import (
	"os"
	"strings"
	"testing"
	"time"

	"gopkg.in/yaml.v3"
)

func TestName(t *testing.T) {
	t.Parallel()
	got := Name(time.Date(2026, 10, 31, 23, 0, 0, 0, time.FixedZone("x", -3600)))
	if got != "events_2026_11" {
		t.Errorf("Name = %q, want events_2026_11: the month is taken in UTC", got)
	}
}

func TestWanted(t *testing.T) {
	t.Parallel()
	got := Wanted(time.Date(2026, 12, 15, 0, 0, 0, 0, time.UTC))
	if Name(got[0]) != "events_2026_12" || Name(got[1]) != "events_2027_01" {
		t.Errorf("Wanted = %v, want this month and the next", got)
	}
}

func TestExpired(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 10, 3, 0, 0, 0, 0, time.UTC)
	names := []string{"events_2026_05", "events_2026_06", "events_2026_07", "events_2026_10", "events_default"}
	got := strings.Join(Expired(names, now), ",")
	// The cutoff is 2026-07-05. June ended before it. July ended after it, so it holds rows that are still kept.
	if got != "events_2026_05,events_2026_06" {
		t.Errorf("Expired = %q", got)
	}
}

// The period here and the `device` class in the registry must agree. A change to one without the other fails here.
func TestPeriodMatchesTheRegistry(t *testing.T) {
	t.Parallel()
	raw, err := os.ReadFile("../../../../tools/codegen/retention.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var reg struct {
		Classes map[string]struct {
			Period string `yaml:"period"`
		} `yaml:"classes"`
	}
	err = yaml.Unmarshal(raw, &reg)
	if err != nil {
		t.Fatal(err)
	}
	if got := reg.Classes["device"].Period; got != "90 days" {
		t.Errorf("the device class keeps %q, and this package keeps 90 days", got)
	}
}
