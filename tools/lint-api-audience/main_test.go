package main

import "testing"

func TestCheck(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		auds    []string
		exposed bool
		wantOK  bool
	}{
		{"public op + edge route", []string{audiencePublic}, true, true},
		{"internal op + edge route", []string{audienceInternal}, true, true},
		{"mixed public + cluster + edge route", []string{audiencePublic, audienceCluster}, true, true},
		{"cluster-only + east-west", []string{audienceCluster}, false, true},
		{"no operations + not exposed", nil, false, true},
		{"public op but no route", []string{audiencePublic}, false, false},
		{"internal op but no route", []string{audienceInternal}, false, false},
		{"edge-exposed but all cluster", []string{audienceCluster}, true, false},
		{"unknown audience", []string{"external"}, true, false},
	}
	for _, c := range cases {
		t.Run(
			c.name,
			func(t *testing.T) {
				t.Parallel()
				ok := len(check("svc", c.auds, c.exposed)) == 0
				if ok != c.wantOK {
					t.Fatalf("check(%v, exposed=%v): ok=%v, want %v", c.auds, c.exposed, ok, c.wantOK)
				}
			},
		)
	}
}
