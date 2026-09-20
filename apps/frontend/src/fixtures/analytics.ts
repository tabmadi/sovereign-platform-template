/**
 * Analytics fixtures (ADR-0701), read only by `lib/data/analytics.ts`. Shaped like a real funnel: occurrences
 * fall away faster than sessions, and flat tidy numbers make a broken chart look fine.
 */
import type { EventSummary } from "@/lib/data/analytics";

export const summary: EventSummary[] = [
  { name: "page_view", occurrences: 18_402, sessions: 6120 },
  { name: "signup_started", occurrences: 1944, sessions: 1802 },
  { name: "signup_completed", occurrences: 1207, sessions: 1207 },
  { name: "email_verified", occurrences: 1106, sessions: 1094 },
  { name: "panel_first_open", occurrences: 2871, sessions: 1038 },
  { name: "product_viewed", occurrences: 4530, sessions: 902 },
  { name: "checkout_started", occurrences: 688, sessions: 604 },
  { name: "checkout_confirmed", occurrences: 431, sessions: 428 },
  { name: "checkout_failed", occurrences: 97, sessions: 91 },
  { name: "support_contacted", occurrences: 143, sessions: 118 },
];
