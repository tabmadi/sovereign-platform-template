// These tests pin the consent gate's rules, per ADR-0700.
import { describe, expect, test as it } from "bun:test";

import { type ConsentDecision, gpcDecision, mayEmitMarketing, shouldPrompt } from "./consent";

const VERSION = "2026-08-01";
const granted: ConsentDecision = { state: "granted", source: "control", purposeVersion: VERSION };

describe("mayEmitMarketing", () => {
  it("an explicit grant permits emission", () => {
    expect(mayEmitMarketing(granted)).toBe(true);
  });

  // The key rule: a visitor who has not answered has not consented.
  it("no decision is not a grant", () => {
    expect(mayEmitMarketing(null)).toBe(false);
  });

  it("withdrawal stops emission", () => {
    expect(mayEmitMarketing({ ...granted, state: "withdrawn" })).toBe(false);
  });

  it("a refusal stops emission", () => {
    expect(mayEmitMarketing({ ...granted, state: "refused" })).toBe(false);
  });

  // A grant to an older purpose text still permits emission. It triggers a new
  // prompt, not a silent stop. A stop would lose data that the visitor agreed to.
  it("a grant to an older purpose still permits emission", () => {
    expect(mayEmitMarketing({ ...granted, purposeVersion: "2026-01-01" })).toBe(true);
  });
});

describe("shouldPrompt", () => {
  it("an unanswered visitor is prompted", () => {
    expect(shouldPrompt(null, VERSION)).toBe(true);
  });

  it("a current grant is not re-asked", () => {
    expect(shouldPrompt(granted, VERSION)).toBe(false);
  });

  // A changed purpose is a new question, per GDPR Art. 7(1).
  it("a changed purpose re-asks", () => {
    expect(shouldPrompt({ ...granted, purposeVersion: "2026-01-01" }, VERSION)).toBe(true);
  });

  // Never ask again a visitor who sent a signal before, even after a purpose change.
  it("a GPC refusal is never re-asked", () => {
    expect(shouldPrompt(gpcDecision("2026-01-01"), VERSION)).toBe(false);
  });
});

describe("gpcDecision", () => {
  it("records a refusal rather than merely obeying one", () => {
    const decision = gpcDecision(VERSION);
    expect(decision.state).toBe("refused");
    expect(decision.source).toBe("gpc");
  });
});
