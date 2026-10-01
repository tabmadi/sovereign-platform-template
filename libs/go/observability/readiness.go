package observability

import (
	"context"
	"sync"
	"time"
)

// Readiness reports whether this pod can serve now. It is deep: each check pings a live dependency, per ADR-0500.
// dbmw.Open and temporalmw.NewClient register their own checks, so a service gets a check for each thing it opens.
// Liveness stays shallow and must not use these checks.
type readyCheck struct {
	name string
	ping func(context.Context) error
}

var (
	readyMu     sync.RWMutex
	readyChecks []readyCheck
)

// RegisterReadinessCheck adds a dependency probe to /readyz. It is safe for concurrent
// use. The admin server that Init starts reads the set on every /readyz request.
func RegisterReadinessCheck(name string, ping func(context.Context) error) {
	readyMu.Lock()
	defer readyMu.Unlock()
	readyChecks = append(readyChecks, readyCheck{name: name, ping: ping})
}

// checkReadiness runs every registered check under a bounded context. It returns
// the name of the first failing dependency and its error. It returns an empty name
// and nil if all pass or none are registered, so a pod with no dependencies is ready.
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
