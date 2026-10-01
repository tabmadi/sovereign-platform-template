"use client";

import { ApiReferenceReact } from "@scalar/api-reference-react";
// Scalar ships its stylesheet as a separate export, and the JS wrapper does not import it. Without this, the reference has no styles.
// Next bundles it, so it is served same-origin under style-src 'self', with no CDN.
import "@scalar/api-reference-react/style.css";

// One merged document and not a switcher per service: the flat /api namespace hides service topology, per ADR-0306. It is served same-origin behind the /devportal session gate.
export function ApiReference() {
  return (
    <ApiReferenceReact
      configuration={{
        url: "/devportal/openapi/internal.json",
        // No CDN: self-host fonts, so the bundle works offline and is CSP-safe with font-src 'self', per ADR-0400.
        // Scalar's own theme is a deliberate island.
        withDefaultFonts: false,
      }}
    />
  );
}
