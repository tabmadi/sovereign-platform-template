# syntax=docker/dockerfile:1.29
ARG GO_VERSION=1.27.3
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/root/go/pkg/mod go mod download
COPY libs/go ./libs/go
ARG APP_CMD=server
ARG SERVICE=authz
COPY services/${SERVICE} ./services/${SERVICE}
# The build identity goes into the binary, per ADR-0112, so the running pod reports its
# git SHA and release. The build scripts and CI pass it. Without it, the VCS stamp is used.
ARG GIT_SHA=""
ARG BUILD_VERSION=dev
ARG BUILD_TIME=""
RUN --mount=type=cache,target=/root/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build \
      -ldflags="-s -w \
        -X github.com/tabmadi/sovereign-platform-template/libs/go/buildinfo.Version=${BUILD_VERSION} \
        -X github.com/tabmadi/sovereign-platform-template/libs/go/buildinfo.SHA=${GIT_SHA} \
        -X github.com/tabmadi/sovereign-platform-template/libs/go/buildinfo.BuiltAt=${BUILD_TIME}" \
      -o /out/app ./services/${SERVICE}/cmd/${APP_CMD}

FROM gcr.io/distroless/static-debian13:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
