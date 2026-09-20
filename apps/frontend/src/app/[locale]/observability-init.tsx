// Loads browser observability off the critical path (ADR-0400, ADR-0500).
"use client";

import { useEffect } from "react";

export function ObservabilityInit() {
  useEffect(() => {
    let cancelled = false;
    const load = () => {
      if (cancelled) {
        return;
      }
      // Failing to load RUM must never break the page it is measuring, so the
      // rejection is swallowed deliberately — there is nowhere to report it to
      // when the thing that reports is what failed to load.
      import("@/lib/observability/client")
        .then(({ initBrowserObservability }) => {
          if (!cancelled) {
            initBrowserObservability();
          }
        })
        .catch(() => undefined);
    };

    let idleHandle: number | undefined;
    let timer: number | undefined;
    const schedule = () => {
      const idle = window.requestIdleCallback;
      if (typeof idle === "function") {
        idleHandle = idle(load, { timeout: 5000 });
      } else {
        timer = window.setTimeout(load, 2000);
      }
    };

    if (document.readyState === "complete") {
      schedule();
    } else {
      window.addEventListener("load", schedule, { once: true });
    }

    return () => {
      cancelled = true;
      window.removeEventListener("load", schedule);
      if (idleHandle !== undefined) {
        window.cancelIdleCallback?.(idleHandle);
      }
      if (timer !== undefined) {
        window.clearTimeout(timer);
      }
    };
  }, []);
  return null;
}
