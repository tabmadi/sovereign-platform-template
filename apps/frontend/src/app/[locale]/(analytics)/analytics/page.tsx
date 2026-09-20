// The funnel surface (ADR-0700).

import { getTranslations } from "next-intl/server";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { eventSummary } from "@/lib/data/analytics";

const WINDOW_DAYS = 7;

export default async function AnalyticsPage() {
  const t = await getTranslations("analytics");
  const rows = await eventSummary(WINDOW_DAYS);

  return (
    <main className="mx-auto max-w-3xl p-6">
      <h1 className="text-2xl font-semibold">{t("title")}</h1>
      <p className="mt-2 text-sm text-muted-foreground">
        {t("description", { days: WINDOW_DAYS })}
      </p>
      {rows.length === 0 ? (
        <p className="mt-6 text-sm text-muted-foreground">{t("empty")}</p>
      ) : (
        <Table className="mt-6">
          <TableHeader>
            <TableRow>
              <TableHead>{t("columnEvent")}</TableHead>
              <TableHead className="text-end">{t("columnOccurrences")}</TableHead>
              <TableHead className="text-end">{t("columnSessions")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.name}>
                <TableCell className="font-medium">{row.name}</TableCell>
                <TableCell className="text-end tabular-nums">{row.occurrences}</TableCell>
                <TableCell className="text-end tabular-nums">{row.sessions}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </main>
  );
}
