// authz is the ops-tier edge authorizer Oathkeeper's remote_json authorizer calls: no database, no edge route
// (ADR-0306).
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tabmadi/sovereign-platform-template/libs/go/apierr"
	"github.com/tabmadi/sovereign-platform-template/libs/go/authz"
	"github.com/tabmadi/sovereign-platform-template/libs/go/httpmw"
	"github.com/tabmadi/sovereign-platform-template/libs/go/observability"
	authzsdk "github.com/tabmadi/sovereign-platform-template/libs/go/sdks/authz"
	"github.com/tabmadi/sovereign-platform-template/libs/go/temporalmw"
	"github.com/tabmadi/sovereign-platform-template/services/authz/internal/handlers"
)

const serviceName = "authz"

func main() {
	err := run()
	if err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdown, err := observability.Init(ctx, observability.Config{ServiceName: serviceName})
	if err != nil {
		return fmt.Errorf("obs init: %w", err)
	}
	defer func() { _ = shutdown(context.Background()) }()

	checker, err := authz.New()
	if err != nil {
		return fmt.Errorf("authz client: %w", err)
	}
	granter, err := authz.NewGranter()
	if err != nil {
		return fmt.Errorf("authz granter: %w", err)
	}

	// Coarse claim gate is always on; the optional fine per-tool OpenFGA layer is
	// enabled per-project (ADR-0306). Default off keeps the coarse gate free of any
	// OpenFGA dependency.
	fineGrained := os.Getenv("OPS_FINE_GRAINED") == "true"

	// A hard dependency of startup rather than a lazy dial: a service that accepts `createOperator` and then discovers
	// it has nowhere to send it has already told the caller yes.
	tc, err := temporalmw.NewClient(serviceName)
	if err != nil {
		return fmt.Errorf("temporal: %w", err)
	}
	defer tc.Close()

	// authz is spec-first like every HTTP service (ADR-0303): the ogen server routes
	// and validates; the handlers implement the generated interface. No authmw — the
	// caller is Oathkeeper (remote_json), not a user session.
	api, err := authzsdk.NewServer(
		handlers.New(checker, granter, fineGrained, tc, slog.Default()),
		// A request the generated server rejects before a handler runs — a malformed
		// body, a bad parameter, a missing required header — still gets an RFC 9457
		// problem with a 4xx rather than ogen's bare 500 (ADR-0303).
		authzsdk.WithErrorHandler(apierr.ServeError),
	)
	if err != nil {
		return fmt.Errorf("ogen server: %w", err)
	}

	srv := &http.Server{
		Addr:              httpmw.ListenAddr(),
		Handler:           httpmw.Chain(api, serviceName),
		ReadHeaderTimeout: 5 * time.Second,
	}
	serveErr := make(chan error, 1)
	go func() {
		err := srv.ListenAndServe()
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			serveErr <- fmt.Errorf("http server: %w", err)
		}
	}()
	slog.Info("authz listening", "addr", srv.Addr)

	select {
	case err := <-serveErr:
		return err
	case <-ctx.Done():
	}
	shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	err = srv.Shutdown(shutCtx)
	if err != nil {
		return fmt.Errorf("authz: server shutdown: %w", err)
	}
	return nil
}
