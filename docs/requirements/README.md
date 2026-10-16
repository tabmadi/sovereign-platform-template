# Journey requirements

What a journey across services must do, per [ADR-0602](../adr/0602-behaviour-requirements.md). A service's own requirements are in `services/<name>/requirements.md`. The browser acceptance suite cites each ID here as a Playwright tag, so `playwright test --grep @PUR-002` runs the proof of one requirement.

| File | Prefix | Journey |
| --- | --- | --- |
| [purchase](purchase.md) | `PUR` | an operator adds a product, and a shopper buys it |
| [registration](registration.md) | `REG` | a person registers, and cannot grant themselves the operator role |
