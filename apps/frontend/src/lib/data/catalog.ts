// The catalog seam, per ADR-0400 and ADR-0701. It decides where a screen gets its data, and it is the only thing that fixtures change.
import type { components, paths } from "@sdks/catalog";
import { products as fixtureProducts } from "@/fixtures/catalog";
import { createServerClient } from "@/lib/server-fetch/server";
import { fixturesEnabled } from "./mode";

export type Product = components["schemas"]["Product"];

export async function listProducts(): Promise<Product[]> {
  if (fixturesEnabled) {
    return fixtureProducts;
  }
  const catalog = await createServerClient<paths>();
  const { data } = await catalog.GET("/products");
  return data ?? [];
}
