// Every fixed text of the console in one place. Operator tooling is English only, per ADR-0400.
export const text = {
  brand: "Platform admin",
  dashboard: "Dashboard",
  intro:
    "Each resource opens a list of its records. A row opens its edit page, where you can save or delete. Every page calls the service API, never a database, per ADR-0401.",
  generated: "The generator makes these pages from the x-admin markers in the service specs.",
  rowHint: "Click a row to edit.",
  create: "Create",
  save: "Save",
  remove: "Delete",
  back: "Back to list",
  previous: "Previous",
  next: "Next",
  editing: "Editing id:",
  saved: "Saved changes",
  noStep: "This page has no such step",
  pageOf: (at: number, of: number) => `Page ${at} of ${of}`,
  succeeded: (title: string) => `${title} succeeded`,
} as const;
