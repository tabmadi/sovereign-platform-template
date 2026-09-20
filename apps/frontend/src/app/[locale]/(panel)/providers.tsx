// Panel providers (ADR-0400): the interactive surface, and the only route group that carries client state.
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NuqsAdapter } from "nuqs/adapters/next/app";
import { type ReactNode, useState } from "react";
import { isAuthDenial } from "@/lib/auth/denial";

// The group's access-denial handling, in one place, so no page carries an auth branch (ADR-0400).
// TanStack Query catches what a query function throws, so `throwOnError` re-throws a denial during render —
// only a denial, because a 500 from one widget should not take the page down.
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
