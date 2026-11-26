"use server";
// The one Server Action of the console. Each form names its page and its step, and the manifest says which call to make.
import { redirect } from "next/navigation";
import { bodyFrom, fillPath, recordPath } from "@/lib/form";
import { type ActionPage, type CreatePage, type EditPage, findPage } from "@/lib/manifest";
import { call } from "@/lib/service";
import { text } from "@/lib/text";

function withQuery(page: string, query: Record<string, string>): string {
  return `/${page}?${new URLSearchParams(query).toString()}`;
}

async function create(
  page: CreatePage,
  form: FormData,
  back: (error: string) => string,
): Promise<string> {
  const res = await call(
    page.service,
    page.create.method,
    page.create.path,
    bodyFrom(page.fields, form),
  );
  return res.ok ? `/${page.back}` : back(res.error);
}

async function edit(
  page: EditPage,
  form: FormData,
  id: string,
  back: (error: string) => string,
): Promise<string> {
  const step = String(form.get("_step") ?? "");
  if (step === "remove" && page.remove) {
    const res = await call(page.service, page.remove.method, recordPath(page.remove.path, id));
    return res.ok ? `/${page.back}` : back(res.error);
  }
  if (step === "update" && page.update) {
    const body = bodyFrom(page.fields, form);
    const res = await call(
      page.service,
      page.update.method,
      recordPath(page.update.path, id),
      body,
    );
    return res.ok ? withQuery(page.id, { id, ok: text.saved }) : back(res.error);
  }
  return back(text.noStep);
}

async function action(
  page: ActionPage,
  form: FormData,
  back: (error: string) => string,
): Promise<string> {
  const values: Record<string, string> = {};
  for (const param of page.params) {
    values[param.name] = String(form.get(param.name) ?? "");
  }
  const body = page.fields.length > 0 ? bodyFrom(page.fields, form) : undefined;
  const res = await call(page.service, page.run.method, fillPath(page.run.path, values), body);
  return res.ok ? withQuery(page.id, { ok: text.succeeded(page.title) }) : back(res.error);
}

/** Makes the call of one submitted form and returns the next URL. It never throws, so every error shows on the page. */
async function next(form: FormData): Promise<string> {
  const page = findPage(String(form.get("_page") ?? ""));
  if (!page) {
    return "/";
  }
  const id = String(form.get("_id") ?? "");
  const back = (error: string) => withQuery(page.id, id ? { id, err: error } : { err: error });
  try {
    switch (page.kind) {
      case "create":
        return await create(page, form, back);
      case "edit":
        return await edit(page, form, id, back);
      case "action":
        return await action(page, form, back);
      default:
        return `/${page.id}`;
    }
  } catch (err) {
    return back((err as Error).message);
  }
}

export async function submit(form: FormData): Promise<void> {
  redirect(await next(form));
}
