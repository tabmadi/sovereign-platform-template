// Package funnels loads the committed funnel definitions (ADR-0700).
package funnels

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Funnel struct {
	ID    string   `yaml:"id"`
	Name  string   `yaml:"name"`
	Steps []string `yaml:"steps"`
}

type file struct {
	Funnels []Funnel `yaml:"funnels"`
}

type Set struct {
	byID map[string]Funnel
}

// Load: Validation at load, not at use, so a malformed definition stops the service starting. A one-step funnel is a
// count, and would report 100% conversion forever.
func Load(path string) (*Set, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var f file
	err = yaml.Unmarshal(data, &f)
	if err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if len(f.Funnels) == 0 {
		return nil, fmt.Errorf("%s: no funnels defined", path)
	}

	set := &Set{byID: make(map[string]Funnel, len(f.Funnels))}
	for _, fn := range f.Funnels {
		if fn.ID == "" {
			return nil, fmt.Errorf("%s: a funnel has no id", path)
		}
		if len(fn.Steps) < 2 {
			return nil, fmt.Errorf(
				"%s: funnel %q has %d steps; a funnel needs at least two",
				path,
				fn.ID,
				len(fn.Steps),
			)
		}
		// A repeated step would count the same event twice and make the funnel
		// appear to hold at 100% through the duplicate.
		seen := make(map[string]bool, len(fn.Steps))
		for _, step := range fn.Steps {
			if seen[step] {
				return nil, fmt.Errorf("%s: funnel %q repeats step %q", path, fn.ID, step)
			}
			seen[step] = true
		}
		_, dup := set.byID[fn.ID]
		if dup {
			return nil, fmt.Errorf("%s: funnel %q is defined twice", path, fn.ID)
		}
		set.byID[fn.ID] = fn
	}
	return set, nil
}

func (s *Set) Get(id string) (Funnel, bool) {
	fn, ok := s.byID[id]
	return fn, ok
}

func (s *Set) Len() int { return len(s.byID) }
