// Web vitals and per-route bundle budgets as a merge gate, per ADR-0400.
//
// A .cjs config and not JSON, because a JSON file cannot carry the two notes below. Each note names a known trap.
// The origin is a variable because the budgets are a property of the build, not of the machine that serves it.
const ORIGIN = process.env.LHCI_URL ?? "https://dev.localtest.me:8443";

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
        budgetsPath: "./lighthouse-budgets.json",
      },
    },
    assert: {
      // median, not the lhci default optimistic: a budget measures a typical load, not the best of three runs.
      // It applies only to the landing page. lhci groups runs by finalUrl, and each auth route 307s to a Kratos flow init with a new `?flow=<uuid>`.
      // So each auth run is a group of one, with no median. `assertMatrix` does not help: it selects assertions after the grouping.
      aggregationMethod: "median",
      assertions: ASSERTIONS,
    },
    upload: { target: "filesystem", outputDir: "./lighthouse-report" },
  },
};
