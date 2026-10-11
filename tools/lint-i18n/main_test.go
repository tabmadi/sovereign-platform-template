package main

import "testing"

func TestToLogical(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		`className="ml-2 pr-4 text-left"`:              `className="ms-2 pe-4 text-start"`,
		`"-right-24 top-10"`:                           `"-end-24 top-10"`,
		`"left-1/2 -translate-x-1/2"`:                  `"left-1/2 -translate-x-1/2"`,
		`"data-[side=left]:slide-in-from-right-2"`:     `"data-[side=left]:slide-in-from-right-2"`,
		`"data-[side=right]:left-0 data-open:left-0"`:  `"data-[side=right]:left-0 data-open:start-0"`,
		`"[&_pre]:text-left **:data-[slot=x]:ml-auto"`: `"[&_pre]:text-start **:data-[slot=x]:ms-auto"`,
	}
	for in, want := range cases {
		got := toLogical(in)
		if got != want {
			t.Errorf("toLogical(%q) = %q, want %q", in, got, want)
		}
	}
}
