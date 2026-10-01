// Panel route-group layout, per ADR-0400. It exists to place the client-state providers on this group only.
import type { ReactNode } from "react";
import { PanelProviders } from "./providers";

// Every route here fetches live data through the edge, so none can be prerendered. Without this, `next build` fails and names the missing variable, not the prerender.
// An origin at build time would bake one environment's host into an image that is promoted by digest, per ADR-0103.
export const dynamic = "force-dynamic";

export default function PanelLayout({ children }: { children: ReactNode }) {
  return <PanelProviders>{children}</PanelProviders>;
}
