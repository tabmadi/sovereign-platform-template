// The catalog seam (ADR-0400, ADR-0701). Server-side reads: `createServerClient`
// is server-only, so this module is too.
//
// Everything a screen knows about where its data comes from is here. A page calls
// `listProducts()`; whether that reached the catalog service or a committed fixture
// is this file's business, which is what makes promoting a designed screen a
// one-line change rather than a rewrite.
import type { paths } from "@sdks/catalog";
import { products as fixtureProducts } from "@/fixtures/catalog";
import { createServerClient } from "@/lib/server-fetch/server";
import { fixturesEnabled } from "./mode";

export type Product = { id: string; name: string; price: { amount: string; currency: string } };

export async function listProducts(): Promise<Product[]> {
  if (fixturesEnabled) {
    return fixtureProducts;
  }
  const catalog = await createServerClient<paths>();
  const { data } = await catalog.GET("/products");
  return data ?? [];
}
