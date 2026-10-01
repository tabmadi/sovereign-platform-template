// Package buildinfo exposes the identity of the running binary: git SHA, release version, and build time. The
// artifact then states what is deployed, per ADR-0103.
package buildinfo

import "runtime/debug"

// The build sets these with `-ldflags "-X .../libs/go/buildinfo.SHA=<sha>"`. Do not assign them at runtime.
var (
	// Version is the CalVer release tag, per ADR-0103, for example `v2026.07.0`. It is `dev` outside a release.
	Version = "dev"
	// SHA is the git commit the binary was built from.
	SHA = ""
	// BuiltAt is the build timestamp in RFC 3339 format.
	BuiltAt = ""
)

//nolint:gochecknoinits // one-time fallback to the Go VCS stamp at load when ldflags didn't inject.
func init() {
	if SHA != "" && BuiltAt != "" {
		return
	}
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return
	}
	for _, s := range info.Settings {
		switch s.Key {
		case "vcs.revision":
			if SHA == "" {
				SHA = s.Value
			}
		case "vcs.time":
			if BuiltAt == "" {
				BuiltAt = s.Value
			}
		}
	}
}

type Info struct {
	Version string `json:"version"`
	SHA     string `json:"sha"`
	BuiltAt string `json:"builtAt"`
}

func Get() Info { return Info{Version: Version, SHA: SHA, BuiltAt: BuiltAt} }
