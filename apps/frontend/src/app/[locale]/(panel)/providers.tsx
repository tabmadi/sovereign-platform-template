// Panel providers, per ADR-0400. This is the interactive surface, and the only route group with client state.
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NuqsAdapter } from "nuqs/adapters/next/app";
import { type ReactNode, useState } from "react";
import { isAuthDenial } from "@/lib/auth/denial";

// The group's access-denial handling, in one place, so no page has an auth branch, per ADR-0400.
// TanStack Query catches what a query function throws, so `throwOnError` throws a denial again during render.
// It does this only for a denial, because a 500 from one widget must not break the page.
function makeQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: { throwOnError: isAuthDenial },
      mutations: { throwOnError: isAuthDenial },
    },
  });
}

export function PanelProviders({ children }: { children: ReactNode }) {
  const [queryClient] = useState(makeQueryClient);
  return (
    <QueryClientProvider client={queryClient}>
      <NuqsAdapter>{children}</NuqsAdapter>
    </QueryClientProvider>
  );
}
