// Command lint-tasks checks that every mise task has a command or a dependency, per ADR-0600.
package main

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

// included lists the task files that a `.mise.toml` pulls in through `task_config.includes`.
var included = regexp.MustCompile(`(?m)^includes\s*=\s*\[(.*)\]`)

// quoted matches each entry of that list.
var quoted = regexp.MustCompile(`"([^"]+)"`)

// tableHeader matches a TOML table header and captures its dotted name.
var tableHeader = regexp.MustCompile(`^\[([^\[\]]+)\]\s*(#.*)?$`)

// taskPrefix is the table prefix of a task in a `.mise.toml`.
const taskPrefix = "tasks."

// does matches a key that makes a task do something: a command, a dependency, or a script file.
var does = regexp.MustCompile(`^(run|depends|depends_post|file)\s*=`)

func main() {
	lint.Main("a mise task has no command and no dependency, per ADR-0600", run)
}

func run(r *lint.Report) error {
	files, err := repo.Files()
	if err != nil {
		return err
	}
	tasks := 0
	for _, f := range files {
		if filepath.Base(f) != ".mise.toml" {
			continue
		}
		data, err := repo.Read(f)
		if err != nil {
			return err
		}
		n, findings := check(f, string(data), taskPrefix)
		tasks += n
		r.Add(findings...)
		for _, inc := range includes(string(data)) {
			path := filepath.Join(filepath.Dir(f), inc)
			data, err := repo.Read(path)
			if err != nil {
				return fmt.Errorf("%s includes %s: %w", f, inc, err)
			}
			n, findings := check(path, string(data), "")
			tasks += n
			r.Add(findings...)
		}
	}
	r.Hintf("Add `run` or `depends`. A task with neither passes and does nothing.")
	r.Okf("every mise task has a command or a dependency, %d tasks", tasks)
	return nil
}

func includes(config string) []string {
	var out []string
	for _, m := range included.FindAllStringSubmatch(config, -1) {
		for _, q := range quoted.FindAllStringSubmatch(m[1], -1) {
			out = append(out, q[1])
		}
	}
	return out
}

// check returns the number of task tables in config, and one finding for each that has none of the keys in does.
// prefix is `tasks.` for a `.mise.toml`. It is empty for an included file, where every table is a task.
func check(path, config, prefix string) (int, []string) {
	var findings []string
	tasks := 0
	name, line, active := "", 0, false
	flush := func() {
		if name != "" && !active {
			findings = append(findings, fmt.Sprintf("%s:%d: task %s", path, line, name))
		}
	}
	for i, text := range strings.Split(config, "\n") {
		m := tableHeader.FindStringSubmatch(text)
		if m != nil {
			flush()
			name, active = "", false
			table, ok := strings.CutPrefix(m[1], prefix)
			if ok && table != "" {
				name, line = strings.Trim(table, `"`), i+1
				tasks++
			}
			continue
		}
		if name != "" && does.MatchString(text) {
			active = true
		}
	}
	flush()
	return tasks, findings
}
