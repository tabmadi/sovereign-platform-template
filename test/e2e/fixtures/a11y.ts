// Accessibility scanning for the e2e suite, per ADR-0400 and ADR-0601.
import AxeBuilder from "@axe-core/playwright";
import { expect, type Page } from "@playwright/test";

/** Impact levels that fail a merge. */
const BLOCKING = new Set(["serious", "critical"]);

/**
 * WCAG 2.2 AA is the target for every route group. So the tag set is the AA levels plus the two WCAG 2.2 additions.
 * `best-practice` is absent on purpose: it is axe's opinion, not a success criterion.
 */
const WCAG22AA = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

export interface ScanOptions {
    /** CSS selector that limits the scan, for example one kitchen-sink section. */
  include?: string;
    /**
     * Selectors to exclude. The scan does not cover vendored islands with their own theme, per ADR-0400.
     * Scalar's rendered console is the standard example.
     */
  exclude?: string[];
}

/**
 * Scan the current page and fail on any serious or critical violation.
 * `label` names the surface in the failure message. A violation count with no surface needs a bisect before anyone can act on it.
 */
export async function expectNoA11yViolations(
  page: Page,
  label: string,
  options: ScanOptions = {},
): Promise<void> {
  let builder = new AxeBuilder({ page }).withTags(WCAG22AA);
  if (options.include) {
    builder = builder.include(options.include);
  }
  for (const selector of options.exclude ?? []) {
    builder = builder.exclude(selector);
  }

  const results = await builder.analyze();
  const blocking = results.violations.filter((v) => BLOCKING.has(v.impact ?? ""));
  if (blocking.length === 0) {
    return;
  }

  const detail = blocking
    .map((v) => {
      const where = v.nodes
        .slice(0, 3)
        .map((n) => n.target.join(" "))
        .join("\n      ");
      return `  [${v.impact}] ${v.id}: ${v.help}\n    ${v.helpUrl}\n    at: ${where}`;
    })
    .join("\n");

  expect(
    blocking,
    `${label}: ${blocking.length} serious or critical WCAG 2.2 AA violations\n${detail}`,
  ).toHaveLength(0);
}

/**
 * Every `<section>` on the kitchen-sink page, by its heading text. A primitive's conformance is proven once here, not in every consumer, per ADR-0400.
 * So the scan runs per section, and a failure names the primitive.
 */
export async function kitchenSinkSections(page: Page): Promise<string[]> {
  return page.locator("main section h2").allInnerTexts();
}
