# syntax=docker/dockerfile:1.7
ARG GO_VERSION=1.26.3
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/root/go/pkg/mod go mod download
COPY libs/go ./libs/go
ARG APP_CMD=server
ARG SERVICE=authz
COPY services/${SERVICE} ./services/${SERVICE}
# Build identity baked into the binary (ADR-0013) so the running pod self-reports
# its git SHA / release; passed by the build scripts + CI, VCS-stamp fallback when absent.
ARG GIT_SHA=""
ARG BUILD_VERSION=dev
ARG BUILD_TIME=""
RUN --mount=type=cache,target=/root/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w \
        -X github.com/tabmadi/microservices-monorepo-template/libs/go/buildinfo.Version=${BUILD_VERSION} \
        -X github.com/tabmadi/microservices-monorepo-template/libs/go/buildinfo.SHA=${GIT_SHA} \
        -X github.com/tabmadi/microservices-monorepo-template/libs/go/buildinfo.BuiltAt=${BUILD_TIME}" \
      -o /out/app ./services/${SERVICE}/cmd/${APP_CMD}

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
