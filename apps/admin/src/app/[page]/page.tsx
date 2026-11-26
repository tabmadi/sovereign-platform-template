// Every generated page. The manifest entry with the id of the URL decides what this route renders.
import Link from "next/link";
import { notFound } from "next/navigation";
import { inputType, read, recordPath, rowsOf, show } from "@/lib/form";
import {
  type ActionPage,
  type CreatePage,
  type EditPage,
  type Field,
  findPage,
  type ListPage,
  manifest,
} from "@/lib/manifest";
import { call } from "@/lib/service";
import { text } from "@/lib/text";
import { submit } from "../actions";
import { Switch } from "../switch";

type Query = Record<string, string | string[] | undefined>;

function one(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

export default async function GeneratedPage(props: {
  params: Promise<{ page: string }>;
  searchParams: Promise<Query>;
}) {
  const [{ page: id }, query] = await Promise.all([props.params, props.searchParams]);
  const page = findPage(id);
  if (!page) {
    notFound();
  }
  const notice = (
    <>
      {one(query.ok) ? <p role="status">{one(query.ok)}</p> : null}
      {one(query.err) ? <p role="alert">{one(query.err)}</p> : null}
    </>
  );
  switch (page.kind) {
    case "list":
      return <List page={page} query={query} notice={notice} />;
    case "create":
      return <Create page={page} notice={notice} />;
    case "edit":
      return <Edit page={page} id={one(query.id)} notice={notice} />;
    case "action":
      return <Action page={page} notice={notice} />;
    default:
      notFound();
  }
}

async function List({
  page,
  query,
  notice,
}: {
  page: ListPage;
  query: Query;
  notice: React.ReactNode;
}) {
  const res = await call(page.service, page.list.method, page.list.path);
  const rows = res.ok ? rowsOf(res.data) : [];
  const size = manifest.pageSize;
  const pages = Math.max(1, Math.ceil(rows.length / size));
  const at = Math.min(Math.max(1, Number.parseInt(one(query.p), 10) || 1), pages);
  const shown = rows.slice((at - 1) * size, at * size);
  return (
    <>
      <h1>{page.title}</h1>
      {notice}
      {res.ok ? null : <p role="alert">{res.error}</p>}
      {page.add ? (
        <form action={`/${page.add.page}`} className="buttons">
          <button type="submit">{page.add.title}</button>
        </form>
      ) : null}
      {page.edit ? <p>{text.rowHint}</p> : null}
      <table>
        <thead>
          <tr>
            {page.columns.map((c) => (
              <th key={c.field}>{c.header}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {shown.map((row, i) => (
            <tr key={show(row.id) || i}>
              {page.columns.map((c) => (
                <td key={c.field}>
                  {page.edit ? (
                    <Link href={`/${page.edit}?id=${encodeURIComponent(show(row.id))}`}>
                      {show(read(row, c.field))}
                    </Link>
                  ) : (
                    show(read(row, c.field))
                  )}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {pages > 1 ? (
        <p className="buttons">
          {at > 1 ? <Link href={`/${page.id}?p=${at - 1}`}>{text.previous}</Link> : null}
          <span>{text.pageOf(at, pages)}</span>
          {at < pages ? <Link href={`/${page.id}?p=${at + 1}`}>{text.next}</Link> : null}
        </p>
      ) : null}
    </>
  );
}

function Create({ page, notice }: { page: CreatePage; notice: React.ReactNode }) {
  return (
    <>
      <h1>{page.title}</h1>
      {notice}
      <form action={submit} className="fields">
        <input type="hidden" name="_page" value={page.id} />
        <Inputs fields={page.fields} />
        <div className="buttons">
          <button type="submit">{text.create}</button>
          <Link href={`/${page.back}`}>{text.back}</Link>
        </div>
      </form>
    </>
  );
}

async function Edit({ page, id, notice }: { page: EditPage; id: string; notice: React.ReactNode }) {
  const res =
    page.get && id
      ? await call(page.service, page.get.method, recordPath(page.get.path, id))
      : undefined;
  const record = res?.ok ? res.data : undefined;
  return (
    <>
      <h1>{page.title}</h1>
      {notice}
      {res && !res.ok ? <p role="alert">{res.error}</p> : null}
      <p>
        {text.editing} {id}
      </p>
      <form action={submit} className="fields">
        <input type="hidden" name="_page" value={page.id} />
        <input type="hidden" name="_id" value={id} />
        <Inputs fields={page.fields} record={record} />
        <div className="buttons">
          {page.update ? (
            <button type="submit" name="_step" value="update">
              {text.save}
            </button>
          ) : null}
          {page.remove ? (
            <button type="submit" name="_step" value="remove" className="danger">
              {text.remove}
            </button>
          ) : null}
          <Link href={`/${page.back}`}>{text.back}</Link>
        </div>
      </form>
    </>
  );
}

function Action({ page, notice }: { page: ActionPage; notice: React.ReactNode }) {
  return (
    <>
      <h1>{page.title}</h1>
      {notice}
      <form action={submit} className="fields">
        <input type="hidden" name="_page" value={page.id} />
        <Inputs fields={[...page.params, ...page.fields]} />
        <div className="buttons">
          <button type="submit">{page.title}</button>
        </div>
      </form>
    </>
  );
}

/** One labelled input per field. A boolean is a switch, and the record fills each value on an edit page. */
function Inputs({ fields, record }: { fields: Field[]; record?: unknown }) {
  return fields.map((f) => {
    const id = `field-${f.name}`;
    const value = read(record, f.name);
    if (f.kind === "boolean") {
      return (
        <label key={f.name} htmlFor={id}>
          {f.label}
          <Switch id={id} name={f.name} initial={value === true} />
        </label>
      );
    }
    return (
      <label key={f.name} htmlFor={id}>
        {f.label}
        <input
          id={id}
          name={f.name}
          type={inputType(f)}
          step={f.kind === "number" ? "any" : undefined}
          defaultValue={f.kind === "password" ? undefined : show(value)}
        />
      </label>
    );
  });
}
