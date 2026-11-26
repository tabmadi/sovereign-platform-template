// The page manifest that `tabkit gen admin` writes from the service specs, per ADR-0401.
// The console renders only what the manifest names, so a new page is a spec marker and not new code.
import data from "../../_generated/manifest.json" with { type: "json" };

export type Call = { method: string; path: string };
export type Field = {
  name: string;
  label: string;
  kind: "string" | "integer" | "number" | "boolean" | "password";
};
export type Column = { field: string; header: string };
export type Link = { page: string; title: string };

type Base = { id: string; service: string; title: string };

export type ListPage = Base & {
  kind: "list";
  list: Call;
  columns: Column[];
  add?: Link;
  edit?: string;
};
export type CreatePage = Base & {
  kind: "create";
  create: Call;
  fields: Field[];
  back: string;
  done: string;
};
export type EditPage = Base & {
  kind: "edit";
  get?: Call;
  update?: Call;
  remove?: Call;
  fields: Field[];
  back: string;
};
export type ActionPage = Base & { kind: "action"; run: Call; params: Field[]; fields: Field[] };
export type Page = ListPage | CreatePage | EditPage | ActionPage;

export type Manifest = {
  pageSize: number;
  groups: { service: string; title: string; links: Link[] }[];
  pages: Page[];
};

export const manifest = data as Manifest;

export function findPage(id: string): Page | undefined {
  return manifest.pages.find((p) => p.id === id);
}
