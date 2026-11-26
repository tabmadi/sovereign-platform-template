// Pure helpers that turn form input into a request, and a response into form values. They hold no I/O, so unit tests cover them.
import type { Field } from "./manifest";

const PARAM = /\{(?<name>[^}]+)\}/gu;

/** Reads a dotted name, such as `price.amount`, from a nested value. */
export function read(value: unknown, name: string): unknown {
  let current = value;
  for (const key of name.split(".")) {
    if (current === null || typeof current !== "object") {
      return undefined;
    }
    current = (current as Record<string, unknown>)[key];
  }
  return current;
}

/** Writes a dotted name into a nested object, and makes each missing level. */
export function write(target: Record<string, unknown>, name: string, value: unknown): void {
  const keys = name.split(".");
  let current = target;
  for (const key of keys.slice(0, -1)) {
    const next = current[key];
    if (next === null || typeof next !== "object") {
      current[key] = {};
    }
    current = current[key] as Record<string, unknown>;
  }
  current[keys.at(-1) as string] = value;
}

/** Puts each path parameter, such as `{id}`, into the path. It escapes every value. */
export function fillPath(path: string, values: Record<string, string>): string {
  return path.replace(PARAM, (_match, name: string) => {
    const value = values[name];
    if (value === undefined || value === "") {
      throw new Error(`missing path parameter ${name}`);
    }
    return encodeURIComponent(value);
  });
}

/** Puts one record id into every path parameter of a record path, such as `/products/{id}`. */
export function recordPath(path: string, id: string): string {
  const values: Record<string, string> = {};
  for (const match of path.matchAll(PARAM)) {
    values[match.groups?.name as string] = id;
  }
  return fillPath(path, values);
}

/** The value of one field. An empty number has no value, so the body leaves it out. */
function fieldValue(field: Field, raw: FormDataEntryValue | null): unknown {
  if (field.kind === "boolean") {
    // An unchecked switch sends nothing in a form, so a boolean field is false when it is absent.
    return raw === "on";
  }
  const input = typeof raw === "string" ? raw : "";
  if (field.kind !== "integer" && field.kind !== "number") {
    return input;
  }
  if (input.trim() === "") {
    return undefined;
  }
  const value = field.kind === "integer" ? Number.parseInt(input, 10) : Number(input);
  if (Number.isNaN(value)) {
    throw new Error(`${field.label} is not a number`);
  }
  return value;
}

/** Builds the JSON body from the submitted form. */
export function bodyFrom(fields: Field[], form: FormData): Record<string, unknown> {
  const body: Record<string, unknown> = {};
  for (const field of fields) {
    const value = fieldValue(field, form.get(field.name));
    if (value !== undefined) {
      write(body, field.name, value);
    }
  }
  return body;
}

/** The rows of a list response. A service returns a bare array or an object with an `items` array. */
export function rowsOf(data: unknown): Record<string, unknown>[] {
  if (Array.isArray(data)) {
    return data as Record<string, unknown>[];
  }
  const items = read(data, "items");
  return Array.isArray(items) ? (items as Record<string, unknown>[]) : [];
}

/** The text of one table cell or one input value. */
export function show(value: unknown): string {
  if (value === undefined || value === null) {
    return "";
  }
  return typeof value === "object" ? JSON.stringify(value) : String(value);
}

/** The type of the input of one field. */
export function inputType(field: Field): "text" | "number" | "password" {
  if (field.kind === "password") {
    return "password";
  }
  return field.kind === "integer" || field.kind === "number" ? "number" : "text";
}
