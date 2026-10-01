// Package rollup turns raw event rows into ordered funnel counts, per ADR-0700.
package rollup

import "time"

type Step struct {
	SessionID string
	Name      string
	FirstSeen time.Time
}

// Count returns, per step, the sessions that reached it in order. The result always has the same length as
// `steps`, so a step that nothing reached is a zero and not a missing row. Counts never increase.
func Count(steps []string, rows []Step) []int64 {
	counts := make([]int64, len(steps))
	if len(steps) == 0 {
		return counts
	}

	// Group first-seen times by session. A session's rows arrive in no fixed
	// order, and a step's position in `steps` orders them.
	bySession := make(map[string]map[string]time.Time)
	for _, r := range rows {
		seen, ok := bySession[r.SessionID]
		if !ok {
			seen = make(map[string]time.Time, len(steps))
			bySession[r.SessionID] = seen
		}
		// The query returns one row per session and name, but a caller can pass
		// more. First seen means the earliest, in both cases.
		prev, exists := seen[r.Name]
		if !exists || r.FirstSeen.Before(prev) {
			seen[r.Name] = r.FirstSeen
		}
	}

	for _, seen := range bySession {
		// `!Before`, not `After`. The funnel's definition orders two events in the same millisecond, not a clock that
		// cannot separate them.
		var prev time.Time
		for i, name := range steps {
			at, ok := seen[name]
			if !ok || at.Before(prev) {
				// The session left the funnel here. Every later step is not reached
				// BY THIS PATH, even if the event exists. This makes a funnel
				// different from a set of independent counts.
				break
			}
			counts[i]++
			prev = at
		}
	}
	return counts
}

// Buckets aligns to midnight UTC and not to the window's start, so the same day is the same bucket on every run.
// The last bucket can extend past `to`. The bucket limits the query, so the next pass replaces a partial day.
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
