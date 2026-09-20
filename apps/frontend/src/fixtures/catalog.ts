/**
 * Catalog fixtures (ADR-0701), read only by `lib/data/catalog.ts`. Deterministic: a fixture that changes
 * between renders makes a visual baseline useless.
 * Full, not minimal — two rows hide every layout decision a real table forces.
 */
import type { Money } from "@libs/money";

export type ProductFixture = { id: string; name: string; price: Money };

const usd = (amount: string): Money => ({ amount, currency: "USD" });

export const products: ProductFixture[] = [
  { id: "product_01h9xk2m4n8p6q3r5s7t9v0w1x", name: "Starter seat", price: usd("19.00") },
  { id: "product_01h9xk2m4n8p6q3r5s7t9v0w2y", name: "Team seat", price: usd("49.00") },
  { id: "product_01h9xk2m4n8p6q3r5s7t9v0w3z", name: "Business seat", price: usd("99.00") },
  {
    id: "product_01h9xk2m4n8p6q3r5s7t9v0w4a",
    name: "Enterprise seat, annual commitment",
    price: usd("1188.00"),
  },
  {
    id: "product_01h9xk2m4n8p6q3r5s7t9v0w5b",
    name: "Additional storage, 100 GB",
    price: usd("8.50"),
  },
  {
    id: "product_01h9xk2m4n8p6q3r5s7t9v0w6c",
    name: "Additional storage, 1 TB",
    price: usd("72.00"),
  },
  { id: "product_01h9xk2m4n8p6q3r5s7t9v0w7d", name: "Priority support", price: usd("250.00") },
  { id: "product_01h9xk2m4n8p6q3r5s7t9v0w8e", name: "Onboarding workshop", price: usd("1500.00") },
  { id: "product_01h9xk2m4n8p6q3r5s7t9v0w9f", name: "Audit log export", price: usd("0.00") },
  { id: "product_01h9xk2m4n8p6q3r5s7t9v0wag", name: "Sandbox environment", price: usd("35.00") },
];
