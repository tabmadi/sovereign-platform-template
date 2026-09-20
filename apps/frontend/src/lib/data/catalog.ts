// The catalog seam (ADR-0400, ADR-0701): where a screen's data comes from, and the only thing fixtures change.
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
