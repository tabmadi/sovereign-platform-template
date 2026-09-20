// Panel route-group layout (ADR-0400): it exists to place the client-state providers on this group alone.
import type { ReactNode } from "react";
import { PanelProviders } from "./providers";

// Every route here fetches live data through the edge, so none can be prerendered, and without this `next build`
// fails naming the missing variable rather than the prerender.
// Supplying an origin at build time would bake one environment's host into an image promoted by digest (ADR-0103).
export const dynamic = "force-dynamic";

export default function PanelLayout({ children }: { children: ReactNode }) {
  return <PanelProviders>{children}</PanelProviders>;
}
