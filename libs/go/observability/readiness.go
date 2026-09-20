package observability

import (
	"context"
	"sync"
	"time"
)

// Readiness answers "can this pod serve right now?" and is deep: each check pings a live dependency (ADR-0500).
// dbmw.Open and temporalmw.NewClient register their own, so a service gets checks for what it opens.
// Liveness stays shallow and must not consult these.
type readyCheck struct {
	name string
	ping func(context.Context) error
}

var (
	readyMu     sync.RWMutex
	readyChecks []readyCheck
)

// RegisterReadinessCheck adds a dependency probe to /readyz. Safe for concurrent
// use; the admin server (started in Init) reads the set on every /readyz request.
func RegisterReadinessCheck(name string, ping func(context.Context) error) {
	readyMu.Lock()
	defer readyMu.Unlock()
	readyChecks = append(readyChecks, readyCheck{name: name, ping: ping})
}

// checkReadiness runs every registered check under a bounded context. It returns
// the name of the first failing dependency and its error, or "" and nil if all
// pass (or none are registered — a pod with no dependencies is always ready).
func checkReadiness(ctx context.Context) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	readyMu.RLock()
	checks := readyChecks
	readyMu.RUnlock()
	for _, c := range checks {
		err := c.ping(ctx)
		if err != nil {
			return c.name, err
		}
	}
	return "", nil
}
