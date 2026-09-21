// Command lint-pii asserts that a column holding personal data carries its `pii:<class>` comment in the migration set
// (ADR-0301, ADR-0300).
package main

import (
	"fmt"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/tabmadi/sovereign-platform-template/tools/internal/lint"
	"github.com/tabmadi/sovereign-platform-template/tools/internal/repo"
)

// Column-name fragments that carry personal data often enough that an untagged one
// is a review finding rather than a guess.
var piiIndicators = []string{
	"email", "phone", "mobile", "address", "postcode", "zip",
	"first_name", "last_name", "full_name", "given_name", "family_name", "surname",
	"user_id", "subject_id", "identity_id", "customer_id", "person",
	"dob", "birth", "national_id", "passport", "ssn", "tax_id",
	"ip_address", "user_agent", "device_id", "latitude", "longitude",
}

// Classes a tag may name. `none` is the explicit "considered, and it is not
// personal data" answer, which is what keeps the gate from being satisfied by
// mislabelling something.
var validClasses = []string{
	"none",
	"contact",          // email, phone, postal address
	"name",             // a person's name
	"identifier",       // a pseudonymous subject or account identifier
	"government_id",    // national identifier, passport, tax number
	"financial",        // payment instrument details
	"location",         // coordinates, precise geolocation
	"device",           // IP address, user agent, device identifier
	"special_category", // GDPR Art. 9 — health, biometrics, and the rest
	"free_text",        // a field a user types into, which may hold anything
}

var (
	createTableRe = regexp.MustCompile(
		`(?is)create\s+table\s+(?:if\s+not\s+exists\s+)?([a-z0-9_."]+)\s*\((.*?)\n\s*\)\s*;`,
	)
	commentRe = regexp.MustCompile(`(?i)comment\s+on\s+column\s+([a-z0-9_."]+)\.([a-z0-9_"]+)\s+is\s+'pii:([a-z_]+)'`)
	columnRe  = regexp.MustCompile(`(?i)^\s*([a-z0-9_"]+)\s+[a-z]`)
)

// A finding is one column that needs a decision, or one tag that is malformed.
type finding struct {
	file    string
	message string
}

func main() {
	lint.Main("PII column tagging (ADR-0301)", run)
}

func run(r *lint.Report) error {
	migrations, err := repo.Glob(filepath.Join("services", "*", "migrations", "*.sql"))
	if err != nil {
		return err
	}
	if len(migrations) == 0 {
		r.Okf("no migrations yet")
		return nil
	}

	columns, tagged, findings, err := scan(migrations)
	if err != nil {
		return err
	}
	for _, f := range findings {
		r.Addf("%s: %s", f.file, f.message)
	}

	for _, key := range sortedKeys(columns) {
		column := key[strings.LastIndex(key, ".")+1:]
		if !looksPersonal(column) {
			continue
		}
		_, isTagged := tagged[key]
		if isTagged {
			continue
		}
		const form = "%s: %s holds personal data by its name and carries no pii: tag — add one, or pii:none if it does not"
		r.Addf(form, columns[key], key)
	}

	r.Okf("%d columns across %d migrations; every personal-data column is tagged", len(columns), len(migrations))
	return nil
}

// scan reads every migration once. Tags are collected across the whole service: a dbmate migration is immutable, so a
// retrospective tag is a new file.
func scan(migrations []string) (map[string]string, map[string]string, []finding, error) {
	columns := map[string]string{} // "service:table.column" -> file that declares it
	tagged := map[string]string{}  // "service:table.column" -> class
	var findings []finding

	for _, path := range migrations {
		service := filepath.Base(filepath.Dir(filepath.Dir(path)))
		data, err := repo.Read(path)
		if err != nil {
			return nil, nil, nil, err
		}
		sql := string(data)

		for _, m := range createTableRe.FindAllStringSubmatch(sql, -1) {
			table := unquote(m[1])
			for line := range strings.SplitSeq(m[2], "\n") {
				name := columnName(line)
				if name == "" {
					continue
				}
				columns[service+":"+table+"."+name] = path
			}
		}

		for _, m := range commentRe.FindAllStringSubmatch(sql, -1) {
			key := service + ":" + unquote(m[1]) + "." + unquote(m[2])
			class := m[3]
			if !slices.Contains(validClasses, class) {
				const form = "%s is tagged pii:%s, which is not a class — one of: %s"
				msg := fmt.Sprintf(form, key, class, strings.Join(validClasses, ", "))
				findings = append(findings, finding{path, msg})
				continue
			}
			tagged[key] = class
		}
	}
	return columns, tagged, findings, nil
}

func looksPersonal(column string) bool {
	lower := strings.ToLower(column)
	for _, indicator := range piiIndicators {
		if strings.Contains(lower, indicator) {
			return true
		}
	}
	return false
}

// columnName reads a column definition line, skipping table constraints.
func columnName(line string) string {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, "--") {
		return ""
	}
	lower := strings.ToLower(trimmed)
	for _, keyword := range []string{"primary key", "foreign key", "unique", "check", "constraint", "exclude"} {
		if strings.HasPrefix(lower, keyword) {
			return ""
		}
	}
	m := columnRe.FindStringSubmatch(trimmed)
	if m == nil {
		return ""
	}
	return unquote(m[1])
}

func unquote(s string) string {
	s = strings.ReplaceAll(s, `"`, "")
	// A schema-qualified name is stored under its table name alone: the migrations
	// declare one schema, and pg_description is queried by table.
	i := strings.LastIndex(s, ".")
	if i >= 0 {
		s = s[i+1:]
	}
	return s
}

func sortedKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
