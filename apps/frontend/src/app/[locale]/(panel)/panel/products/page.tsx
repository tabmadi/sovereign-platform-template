// A server component reading through the data seam (ADR-0400, ADR-0701).
import { formatMoney } from "@libs/money";
import { getTranslations } from "next-intl/server";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { listProducts } from "@/lib/data/catalog";

export default async function Products() {
  const t = await getTranslations("panel.products");
  const products = await listProducts();

  return (
    <main className="mx-auto max-w-3xl p-6">
      <h1 className="text-2xl font-semibold">{t("title")}</h1>
      <Table className="mt-4">
        <TableHeader>
          <TableRow>
            <TableHead>{t("columnName")}</TableHead>
            <TableHead>{t("columnPrice")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {products.map((product) => (
            <TableRow key={product.id}>
              <TableCell className="font-medium">{product.name}</TableCell>
              {/* formatMoney, not `/ 100` and a hardcoded `$`: the minor digits and the
                  symbol belong to the currency, and the amount is a decimal string
                  precisely so it never passes through a double (ADR-0300). */}
              <TableCell className="tabular-nums">{formatMoney(product.price)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </main>
  );
}
