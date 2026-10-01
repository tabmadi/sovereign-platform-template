// authz is the ops-tier edge authorizer that Oathkeeper's remote_json authorizer calls. It has no database and no
// edge route, per ADR-0306.
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

	// The coarse claim gate is always on. Each project can enable the optional fine
	// per-tool OpenFGA layer, per ADR-0306. It is off by default, so the coarse gate
	// has no OpenFGA dependency.
	fineGrained := os.Getenv("OPS_FINE_GRAINED") == "true"

	// A hard startup dependency, not a dial on first use. If a promotion is accepted and then has no workflow engine
	// to run on, the console has already received a yes.
	tc, err := temporalmw.NewClient(serviceName)
	if err != nil {
		return fmt.Errorf("temporal: %w", err)
	}
	defer tc.Close()

	// authz is spec-first like every HTTP service, per ADR-0303. The ogen server routes
	// and validates, and the handlers implement the generated interface. There is no
	// authmw, because the caller is Oathkeeper's remote_json, not a user session.
	api, err := authzsdk.NewServer(
		handlers.New(checker, granter, fineGrained, tc, slog.Default()),
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
