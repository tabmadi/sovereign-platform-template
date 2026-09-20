"use client";

import { ApiReferenceReact } from "@scalar/api-reference-react";
// Scalar ships its stylesheet as a separate export; the JS wrapper does not import
// it, so without this the reference renders unstyled. Bundled by Next → served
// same-origin (style-src 'self'), no CDN.
import "@scalar/api-reference-react/style.css";

// One merged document rather than a per-service switcher: the flat /api namespace hides service topology (ADR-0306). Served same-origin under the /devportal session gate.
export function ApiReference() {
  return (
    <ApiReferenceReact
      configuration={{
        url: "/devportal/openapi/internal.json",
        // No CDN: self-host fonts so the bundle stays offline-clean and CSP-safe
        // (font-src 'self', ADR-0400). Scalar's own theme is a deliberate island.
        withDefaultFonts: false,
      }}
    />
  );
}
