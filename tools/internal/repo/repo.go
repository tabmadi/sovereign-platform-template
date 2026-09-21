// Package repo enumerates and reads the checkout the tools run against.
package repo

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// gitTimeout bounds every git call, so a wedged git cannot hang a gate.
const gitTimeout = 30 * time.Second

func Root() (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), gitTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return "", fmt.Errorf("git rev-parse: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

// Files is the set git accounts for: everything committed plus anything new that is not ignored, the same
// set scripts/lib/repo-files.sh enumerates. A machine-local file a .gitignore excludes must not reach a
// gate, or its verdict differs between a working tree and a clean checkout. Paths are relative to Root.
func Files() ([]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), gitTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z").Output()
	if err != nil {
		return nil, fmt.Errorf("git ls-files: %w", err)
	}
	var files []string
	for p := range strings.SplitSeq(string(out), "\x00") {
		if p != "" {
			files = append(files, filepath.Clean(p))
		}
	}
	return files, nil
}

// Glob is Files filtered by filepath.Match, so a `*` does not cross a path separator.
func Glob(pat string) ([]string, error) {
	files, err := Files()
	if err != nil {
		return nil, err
	}
	var hits []string
	for _, f := range files {
		ok, err := filepath.Match(pat, f)
		if err != nil {
			return nil, fmt.Errorf("match %s: %w", pat, err)
		}
		if ok {
			hits = append(hits, f)
		}
	}
	return hits, nil
}

// Read carries the gosec annotation for the package: a path here is an operator-supplied repo file, never user input.
func Read(path string) ([]byte, error) {
	// #nosec G304 G703 -- path is an operator-supplied repo file; these are local lint helpers, not servers.
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	return data, nil
}

func ReadJSON[T any](path string) (T, error) {
	var v T
	data, err := Read(path)
	if err != nil {
		return v, err
	}
	err = json.Unmarshal(data, &v)
	if err != nil {
		return v, fmt.Errorf("parse %s: %w", path, err)
	}
	return v, nil
}

func ReadYAML[T any](path string) (T, error) {
	var v T
	data, err := Read(path)
	if err != nil {
		return v, err
	}
	err = yaml.Unmarshal(data, &v)
	if err != nil {
		return v, fmt.Errorf("parse %s: %w", path, err)
	}
	return v, nil
}
