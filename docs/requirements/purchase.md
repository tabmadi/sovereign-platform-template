# Purchase requirements

- **Prefix:** PUR
- **Proven by:** the browser acceptance suite in `test/e2e/platform/`, per [ADR-0601](../adr/0601-testing-strategy.md)

What the purchase journey must do across catalog, orders, and payment, per [ADR-0602](../adr/0602-behaviour-requirements.md). Each service's own rules are in its `requirements.md`.

| ID | Requirement |
| --- | --- |
| PUR-001 | When an operator adds a product in the admin console, the catalog lists it, and a shopper can buy it by its identifier. |
| PUR-002 | When a registered shopper buys a product at the storefront checkout, the order reaches `confirmed` after the catalog lookup and the charge succeed. |
| PUR-003 | When a checkout runs, one trace holds the spans of orders, catalog, and payment. |
