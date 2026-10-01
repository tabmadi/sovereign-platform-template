// The consent gate for marketing events, per ADR-0700.

/** The recorded decision. `unknown` means the visitor was not asked, and it is not a refusal. */
export type ConsentState = "granted" | "withdrawn" | "refused" | "unknown";

export type ConsentSource = "control" | "gpc";

export type ConsentDecision = {
  state: ConsentState;
  source: ConsentSource;
  purposeVersion: string;
};

/**
 * Whether a `marketing.*` event may be emitted. Only an explicit grant permits it. `unknown` means the visitor
 * has not answered, and silence is not agreement.
 */
export function mayEmitMarketing(decision: ConsentDecision | null): boolean {
  return decision?.state === "granted";
}

/**
 * Whether to show the consent control to the visitor. A Global Privacy Control signal counts as a refusal and
 * hides the prompt. So a `gpc` decision is never asked again. A `control` refusal can be asked again when the
 * purpose changes.
 */
export function shouldPrompt(decision: ConsentDecision | null, purposeVersion: string): boolean {
  if (decision === null) {
    return !globalPrivacyControl();
  }
  if (decision.source === "gpc") {
    return false;
  }
  // Consent is to a STATED purpose, so a changed purpose text is a new question
  // and not a continuing answer, per GDPR Art. 7(1).
  return decision.purposeVersion !== purposeVersion;
}

/**
 * The visitor's Global Privacy Control signal, read from the navigator. The visitor sent it before any question,
 * so the missing prompt is correct and not an omission.
 */
export function globalPrivacyControl(): boolean {
  if (typeof navigator === "undefined") {
    return false;
  }
  return (
    (navigator as Navigator & { globalPrivacyControl?: boolean }).globalPrivacyControl === true
  );
}

/**
 * The decision to record for a visitor who sent Global Privacy Control. It is recorded, not only obeyed. Art. 7(1)
 * requires proof of consent and of its absence. A refusal that nobody recorded looks the same as a question that
 * nobody asked.
 */
export function gpcDecision(purposeVersion: string): ConsentDecision {
  return { state: "refused", source: "gpc", purposeVersion };
}
