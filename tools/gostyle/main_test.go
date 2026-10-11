package main

import (
	"testing"

	"golang.org/x/tools/go/analysis/analysistest"
)

func TestCallArgs(t *testing.T) {
	t.Parallel()
	analysistest.RunWithSuggestedFixes(t, analysistest.TestData(), callArgsAnalyzer, "a")
}
