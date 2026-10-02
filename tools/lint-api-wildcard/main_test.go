package main

import "testing"

func TestBareAPIWildcard(t *testing.T) {
	t.Parallel()
	cases := map[string]bool{
		// Causes collisions: a wildcard directly after /api/.
		"<{http,https}>://<**>/api/<**>": true,
		"<{http,https}>://<**>/api/<*>":  true,
		"http://host.test/api/*":         true,
		// Safe: enumerated resources or a literal segment.
		"<{http,https}>://<**>/api/<{products,orders}><**>": false,
		"http://host.test/api/products":                     false,
		// Wildcards elsewhere in the path are unrelated.
		"<{http,https}>://lowdefy.ops.<**>/<**>": false,
	}
	for url, want := range cases {
		if got := bareAPIWildcard.MatchString(url); got != want {
			t.Errorf("MatchString(%q) = %v, want %v", url, got, want)
		}
	}
}
