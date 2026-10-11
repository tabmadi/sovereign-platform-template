package main

import "testing"

func TestIsMoneyName(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		want bool
	}{
		{wordPrice, true},
		{"unitPrice", true},
		{"total_amount", true},
		{"AmountCents", true},
		{"refund_total", true},
		{"totals", false},
		{"pricing_enabled", false},
		{"total", true},
		{"total_count", false},
		{"total_pages", false},
		{"totalPages", false},
		{"page_count", false},
		{"total_tokens", false},
		{"quantity", false},
		{"name", false},
	}
	for _, tc := range tests {
		t.Run(
			tc.name,
			func(t *testing.T) {
				t.Parallel()
				if got := isMoneyName(tc.name); got != tc.want {
					t.Fatalf("isMoneyName(%q) = %v, want %v", tc.name, got, tc.want)
				}
			},
		)
	}
}

func TestSplitIdentifier(t *testing.T) {
	t.Parallel()

	tests := []struct {
		in   string
		want []string
	}{
		{"price_cents", []string{wordPrice, "cents"}},
		{"unitPrice", []string{"unit", wordPrice}},
		{"AmountCents", []string{wordAmount, "cents"}},
		{"price.amount", []string{wordPrice, wordAmount}},
	}
	for _, tc := range tests {
		t.Run(
			tc.in,
			func(t *testing.T) {
				t.Parallel()
				got := splitIdentifier(tc.in)
				if len(got) != len(tc.want) {
					t.Fatalf("splitIdentifier(%q) = %v, want %v", tc.in, got, tc.want)
				}
				for i := range got {
					if got[i] != tc.want[i] {
						t.Fatalf("splitIdentifier(%q) = %v, want %v", tc.in, got, tc.want)
					}
				}
			},
		)
	}
}

func TestDisplayOnlyMarker(t *testing.T) {
	t.Parallel()
	marked := "// lint:money-allow: demo figures for the landing showcase\nconst row = { cost: 12 };\n"
	got := checkTypeScriptFile("a.ts", marked)
	if len(got) != 0 {
		t.Errorf("a marked file reported %v", got)
	}
	bare := "// lint:money-allow:\nconst row = { cost: 12 };\n"
	got = checkTypeScriptFile("a.ts", bare)
	if len(got) != 1 {
		t.Errorf("a marker without a reason reported %d findings, want 1", len(got))
	}
}
