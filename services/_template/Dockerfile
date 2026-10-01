# syntax=docker/dockerfile:1.7
ARG GO_VERSION=1.26.3
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/root/go/pkg/mod go mod download
# Copy only the shared libs and this service's source. Then an edit to one service
# does not invalidate the build cache of the others.
COPY libs/go ./libs/go
ARG APP_CMD=server
ARG SERVICE=_template
COPY services/${SERVICE} ./services/${SERVICE}
# The build identity goes into the binary, per ADR-0103, so the running pod reports its
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
RUN mkdir -p /out/migrations && cp -r services/${SERVICE}/migrations/* /out/migrations/ 2>/dev/null || true

FROM gcr.io/distroless/static-debian13:nonroot@sha256:f7f8f729987ad0fdf6b05eeeae94b26e6a0f613bdf46feea7fc40f7bd72953e6
COPY --from=build /out/app /app
COPY --from=build /out/migrations /db/migrations
# The static dbmate binary sits next to the migrations in the image. So the chart's
# migration initContainer runs them from this image, with no separate dbmate image.
COPY --from=amacneil/dbmate:2.27.0 /usr/local/bin/dbmate /usr/local/bin/dbmate
USER nonroot:nonroot
ENTRYPOINT ["/app"]
