# Registration requirements

- **Prefix:** REG
- **Proven by:** the browser acceptance suite in `test/e2e/platform/`, per [ADR-0601](../adr/0601-testing-strategy.md)

What self-service registration must do across Kratos, orgs, and authz, per [ADR-0602](../adr/0602-behaviour-requirements.md). Each service's own rules are in its `requirements.md`.

| ID | Requirement |
| --- | --- |
| REG-001 | When a person registers, the platform creates exactly one personal organisation for the new identity. |
| REG-002 | If a password is shorter than the length policy, registration refuses it, names the length rule, and creates no identity. |
| REG-003 | If a registration carries an operator field, registration refuses it and creates no identity. |
| REG-004 | If a settings update carries an operator field, the update is refused and the identity gains no operator trait or flag. |
