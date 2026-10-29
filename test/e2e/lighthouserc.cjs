// Web vitals and per-route bundle budgets as a merge gate, per ADR-0400.
//
// A .cjs config and not JSON, because a JSON file cannot carry the two notes below. Each note names a known trap.
// The origin is a variable because the budgets are a property of the build, not of the machine that serves it.
// The default is the stack that `mise run lighthouse:up` starts. Not `LHCI_URL`: lhci reads every `LHCI_*` variable as its own flag, and that one replaces the URL list.
const ORIGIN = process.env.LIGHTHOUSE_ORIGIN ?? "https://dev.localtest.me:8444";

// The gate. LCP, CLS, and TBT are ADR-0400's numbers. TBT replaces INP, because INP is a field metric
// and a navigation run has no interaction to measure.
const ASSERTIONS = {
  "largest-contentful-paint": ["error", { maxNumericValue: 2500 }],
  "cumulative-layout-shift": ["error", { maxNumericValue: 0.1 }],
  "total-blocking-time": ["error", { maxNumericValue: 200 }],
  "performance-budget": "error",
  "unused-javascript": "off",
  "uses-long-cache-ttl": "off",
  "csp-xss": "off",
  "is-on-https": "off",
};

module.exports = {
  ci: {
    collect: {
      // The app route is /auth/register, and the Kratos flow is named `registration`. The two are easy to confuse.
      // /auth/registration is a 404, and lighthouse reports only that it is unable to load the page, with no route.
      // test/e2e/fixtures/env.ts guards the specs against the same trap.
      url: [`${ORIGIN}/`, `${ORIGIN}/auth/login`, `${ORIGIN}/auth/register`],
      numberOfRuns: 3,
      chromePath: "",
      settings: {
        chromeFlags: "--ignore-certificate-errors --no-sandbox",
        formFactor: "mobile",
        screenEmulation: {
          mobile: true,
          width: 412,
          height: 823,
          deviceScaleFactor: 1.75,
          disabled: false,
        },
        throttlingMethod: "simulate",
        // The gate reads only performance audits. The SEO category's font-size gatherer took half of each run on the landing page's DOM.
        onlyCategories: ["performance"],
        disableFullPageScreenshot: true,
        budgetsPath: "./lighthouse-budgets.json",
      },
    },
    assert: {
      // median, not the lhci default optimistic: a budget measures a typical load, not the best of three runs.
      // lhci groups runs by finalUrl. The Kratos stub returns one fixed flow id for each route, so the three runs of an auth route are one group too.
      aggregationMethod: "median",
      assertions: ASSERTIONS,
    },
    upload: { target: "filesystem", outputDir: "./lighthouse-report" },
  },
};
