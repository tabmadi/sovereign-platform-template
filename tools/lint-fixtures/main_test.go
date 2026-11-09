package main

import (
	"strings"
	"testing"
)

const dts = `export interface paths {
    "/members": {
        parameters: {
            query?: never;
        };
        get: operations["listMembers"];
        put?: never;
        post: operations["addMember"];
    };
    "/members/{id}": {
        get?: never;
        patch: operations["updateMember"];
    };
}
export interface components {
    schemas: {
        get: string;
    };
}
`

func TestParseEndpoints(t *testing.T) {
	t.Parallel()
	got := parseEndpoints(dts)
	want := []string{"GET /members", "POST /members", "PATCH /members/{}"}
	for _, key := range want {
		if !got[key] {
			t.Errorf("parseEndpoints is missing %s", key)
		}
	}
	if len(got) != len(want) {
		t.Errorf("parseEndpoints = %v, want only %v", got, want)
	}
}

func TestCheckFile(t *testing.T) {
	t.Parallel()
	endpoints := map[string]string{"GET /members": "@sdks/orgs", "PATCH /members/{}": "@sdks/orgs"}
	cases := []struct {
		name string
		src  string
		want []string
	}{
		{
			name: "typed",
			src: `import type { components } from "@sdks/orgs";

// A comment with satisfies in it.
export const members = [
  { name: "a; b", id: "x" },
] satisfies components["schemas"]["Member"][];

export const page = {
  rows: [],
} as const satisfies Partial<components["schemas"]["MemberPage"]>;
`,
		},
		{
			name: "aliased import",
			src: `import { type components as Orgs } from "@sdks/orgs";
export const one = { id: "x" } satisfies Orgs["schemas"]["Member"];
`,
		},
		{
			name: "local alias of an SDK type",
			src: `import type { components } from "@sdks/orgs";

type O = components["schemas"];
export const one = { id: "x" } satisfies O["Member"];
`,
		},
		{
			name: "local alias of a local shape",
			src: `type Member = { id: string };
export const one = { id: "x" } satisfies Member;
`,
			want: []string{"`one` satisfies `Member`, which is not imported from `@sdks/*`"},
		},
		{
			name: "no satisfies",
			src: `import type { components } from "@sdks/orgs";
export const members: components["schemas"]["Member"][] = [];
`,
			want: []string{"`members` has no `satisfies <T>`"},
		},
		{
			name: "satisfies only inside the value",
			src: `import type { components } from "@sdks/orgs";
export const members = [({} satisfies components["schemas"]["Member"])];
`,
			want: []string{"`members` has no `satisfies <T>`"},
		},
		{
			name: "local type",
			src: `import type { Member } from "@/lib/data/orgs";
export const members = [] satisfies Member[];
`,
			want: []string{"`members` satisfies `Member[]`, which is not imported from `@sdks/*`"},
		},
		{
			name: "builtin type only",
			src: `export const names = ["a"] satisfies string[];
`,
			want: []string{"`names` satisfies `string[]`, which is not imported from `@sdks/*`"},
		},
		{
			name: "function export",
			src: `export function members() {
  return [];
}
`,
			want: []string{"a fixture exports only `const` values"},
		},
		{
			name: "no export",
			src:  "const members = [];\n",
			want: []string{"exports no fixture"},
		},
		{
			name: "no-spec marker for a missing endpoint",
			src: `// no-spec: GET /invoices
type Invoice = { id: string };
export const invoices = [] satisfies Invoice[];
`,
		},
		{
			name: "no-spec marker still needs satisfies",
			src: `// no-spec: GET /invoices
export const invoices = [];
`,
			want: []string{"`invoices` has no `satisfies <T>`"},
		},
		{
			name: "stale no-spec marker",
			src: `// no-spec: PATCH /members/{member_id}
type Member = { id: string };
export const member = { id: "x" } satisfies Member;
`,
			want: []string{"PATCH /members/{member_id} is in @sdks/orgs now. Use its type and remove the no-spec marker"},
		},
		{
			name: "malformed no-spec marker",
			src: `// no-spec: members
import type { components } from "@sdks/orgs";
export const members = [] satisfies components["schemas"]["Member"][];
`,
			want: []string{"the no-spec marker must name one endpoint"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, _ := checkFile("f.ts", tc.src, endpoints)
			if len(got) != len(tc.want) {
				t.Fatalf("checkFile = %q, want %d findings %q", got, len(tc.want), tc.want)
			}
			for i, want := range tc.want {
				if !strings.Contains(got[i], want) {
					t.Errorf("finding %q does not contain %q", got[i], want)
				}
			}
		})
	}
}

func TestMaskKeepsOffsets(t *testing.T) {
	t.Parallel()
	src := "const a = \"x;y\"; // c;\n/* d\n; */ const b = `e;${f}`;\n"
	got := mask(src)
	if len(got) != len(src) || strings.Count(got, "\n") != strings.Count(src, "\n") {
		t.Fatalf("mask changed the offsets: %q", got)
	}
	if strings.Count(got, ";") != 2 {
		t.Errorf("mask(%q) = %q, want only the 2 code semicolons", src, got)
	}
}
