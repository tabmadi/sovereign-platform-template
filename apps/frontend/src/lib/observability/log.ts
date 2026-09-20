// Browser log/error forwarding (ADR-0500, ADR-0400).
"use client";

type Loggable = string | number | boolean | null | undefined | object;

export const obsLog = {
  info: (msg: string, ctx?: Record<string, Loggable>) =>
    window.faro?.api.pushLog([msg], { context: ctx }),
  warn: (msg: string, ctx?: Record<string, Loggable>) =>
    window.faro?.api.pushLog([msg], { context: ctx, level: "warn" }),
  error: (err: Error, ctx?: Record<string, Loggable>) =>
    window.faro?.api.pushError(err, { context: ctx }),
};

declare global {
  // biome-ignore lint/style/useConsistentTypeDefinitions: global augmentation must use `interface`
  interface Window {
    faro?: {
      api: {
        pushLog: (args: unknown[], opts?: { context?: object; level?: string }) => void;
        pushError: (err: Error, opts?: { context?: object }) => void;
      };
    };
  }
}
