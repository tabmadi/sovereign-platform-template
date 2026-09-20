// Package rollup turns raw event rows into ordered funnel counts (ADR-0700).
package rollup

import "time"

type Step struct {
	SessionID string
	Name      string
	FirstSeen time.Time
}

// Count returns, per step, the sessions that reached it in order. The result is always the same length as
// `steps`, so a step nothing reached is a zero rather than a missing row, and counts are non-increasing.
func Count(steps []string, rows []Step) []int64 {
	counts := make([]int64, len(steps))
	if len(steps) == 0 {
		return counts
	}

	// Group first-seen times by session. A session's rows arrive in no particular
	// order, and a step's position in `steps` is what orders them.
	bySession := make(map[string]map[string]time.Time)
	for _, r := range rows {
		seen, ok := bySession[r.SessionID]
		if !ok {
			seen = make(map[string]time.Time, len(steps))
			bySession[r.SessionID] = seen
		}
		// The query returns one row per session and name, but a caller could pass
		// more; keeping the earliest is what "first seen" means either way.
		prev, exists := seen[r.Name]
		if !exists || r.FirstSeen.Before(prev) {
			seen[r.Name] = r.FirstSeen
		}
	}

	for _, seen := range bySession {
		// `!Before` rather than `After`: two events in the same millisecond are ordered by the funnel's definition, not by
		// a clock that cannot separate them.
		var prev time.Time
		for i, name := range steps {
			at, ok := seen[name]
			if !ok || at.Before(prev) {
				// The session left the funnel here. Every later step is unreached
				// BY THIS PATH even if the event exists, which is the difference
				// between a funnel and a set of independent counts.
				break
			}
			counts[i]++
			prev = at
		}
	}
	return counts
}

// Buckets: Aligned to midnight UTC rather than to the window's start, so the same day is the same bucket on every
// run. The last bucket may extend past `to`; the query is bounded by the bucket, so a partial day is replaced next
// pass.
func Buckets(from, to time.Time) [][2]time.Time {
	var out [][2]time.Time
	if !from.Before(to) {
		return out
	}
	start := from.UTC().Truncate(24 * time.Hour)
	for start.Before(to) {
		end := start.Add(24 * time.Hour)
		out = append(out, [2]time.Time{start, end})
		start = end
	}
	return out
}
