// The consent gate for marketing events (ADR-0700).

/** The recorded decision. `unknown` is "has not been asked", which is not a refusal. */
export type ConsentState = "granted" | "withdrawn" | "refused" | "unknown";

export type ConsentSource = "control" | "gpc";

export type ConsentDecision = {
  state: ConsentState;
  source: ConsentSource;
  purposeVersion: string;
};

/**
 * Whether a `marketing.*` event may be emitted. Only an explicit grant permits it: `unknown` means the visitor
 * has not answered, and silence is not agreement.
 */
export function mayEmitMarketing(decision: ConsentDecision | null): boolean {
  return decision?.state === "granted";
}

/**
 * Whether the visitor should be shown the consent control. A Global Privacy Control signal is honoured as a
 * refusal and suppresses the prompt, so a `gpc` decision is never re-asked, where a `control` refusal could be
 * revisited when the purpose changes.
 */
export function shouldPrompt(decision: ConsentDecision | null, purposeVersion: string): boolean {
  if (decision === null) {
    return !globalPrivacyControl();
  }
  if (decision.source === "gpc") {
    return false;
  }
  // Consent is to a STATED purpose, so a changed purpose text is a new question
  // rather than a continuing answer (GDPR Art. 7(1)).
  return decision.purposeVersion !== purposeVersion;
}

/**
 * The visitor's Global Privacy Control signal, read from the navigator. It was sent before anything was asked,
 * which is what makes the absence of a prompt correct rather than an omission.
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
 * The decision to record for a visitor who sent Global Privacy Control. It is written rather than merely obeyed,
 * because Art. 7(1) asks for consent — and its absence — to be demonstrable: a refusal nobody recorded looks
 * identical to a question nobody asked.
 */
export function gpcDecision(purposeVersion: string): ConsentDecision {
  return { state: "refused", source: "gpc", purposeVersion };
}
