// Shared renderer for the Kratos self-service flows, used by every /auth/* route, per ADR-0304 and ADR-0400.
"use client";

import { useTranslations } from "next-intl";
import type { HTMLAttributeReferrerPolicy, ReactNode } from "react";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

export type FlowKind = "login" | "registration" | "recovery" | "verification" | "settings";

export type FlowStrings = {
  title: string;
  starting: string;
  submit: string;
  error: string;
};

type UiText = { id: number; text: string };
type UiNode = {
  type?: string; // node_type at the node level: input, text, img, script, or a
  group?: string;
  attributes: {
    node_type?: string;
    name?: string;
    type?: string;
    value?: string | number | boolean;
    required?: boolean;
    disabled?: boolean;
    // text node, for example the TOTP secret, and img node, the TOTP QR code
    text?: UiText;
    src?: string;
    // webauthn registration is a submit button, and the script node sets its handler
    onclick?: string;
    // script node attributes for the Kratos WebAuthn helper
    id?: string;
    async?: boolean;
    referrerpolicy?: string;
    crossorigin?: string;
    integrity?: string;
    nonce?: string;
  };
  messages?: UiText[];
  meta: { label?: UiText };
};

function nodeType(node: UiNode): string {
  return node.type ?? node.attributes.node_type ?? "input";
}

function nodeKey(node: UiNode): string {
  const attr = node.attributes;
  return [nodeType(node), attr.name, attr.type, attr.value, attr.id, attr.text?.id, attr.src].join(
    ":",
  );
}
type Flow = {
  ui: { action: string; method: string; nodes: UiNode[]; messages?: UiText[] };
};

// Kratos sets the CSRF cookie and redirects back here with ?flow=<id>. Start the browser flow, or start it again, and keep any return_to.
function restartFlow(kind: FlowKind): void {
  const returnTo = new URLSearchParams(window.location.search).get("return_to");
  const init = new URL(`/auth/self-service/${kind}/browser`, window.location.origin);
  if (returnTo) {
    init.searchParams.set("return_to", returnTo);
  }
  window.location.replace(init.toString());
}

// Kratos WebAuthn helper script. The src is same-origin, and the nonce lets it run under the strict CSP with strict-dynamic.
// It defines the window.__oryWebAuthn* functions that the buttons use.
function ScriptNode({ attr }: { attr: UiNode["attributes"] }) {
  return (
    <script
      src={attr.src}
      async={attr.async}
      nonce={attr.nonce}
      crossOrigin={attr.crossorigin as "anonymous" | "use-credentials" | undefined}
      integrity={attr.integrity}
      referrerPolicy={attr.referrerpolicy as HTMLAttributeReferrerPolicy | undefined}
    />
  );
}

// TOTP QR code. A plain <img> is correct: Kratos returns a data: URL, which img-src 'self' data: allows, and not a routable next/image asset.
function ImgNode({ src, alt }: { src?: string; alt: string }) {
  // biome-ignore lint/performance/noImgElement: data: URL QR, not a next/image asset.
  return <img src={src} alt={alt} width={200} height={200} className="my-2" />;
}

function InputNode({ node, submitLabel }: { node: UiNode; submitLabel: string }) {
  const attr = node.attributes;
  const value = String(attr.value ?? "");
  const labelText = node.meta.label ? node.meta.label.text : undefined;

  if (attr.type === "hidden") {
    return <input type="hidden" name={attr.name} value={value} />;
  }
  if (attr.type === "submit" || attr.type === "button") {
    // Kratos finds the pressed method by name=value. A settings flow renders every method in one form, and `formNoValidate` stops an empty field of one method from blocking another method's submit.
    return (
      <Button
        type={attr.type === "button" ? "button" : "submit"}
        name={attr.name}
        value={value}
        formNoValidate
        className="w-full"
      >
        {labelText ?? submitLabel}
      </Button>
    );
  }
  const messages = node.messages ?? [];
  const errorText = messages.map((message) => message.text).join(" ");
  const fieldId = `kratos-${attr.name}`;
  return (
    <Field data-invalid={messages.length > 0}>
      <FieldLabel htmlFor={fieldId}>{labelText ?? attr.name}</FieldLabel>
      <Input
        id={fieldId}
        name={attr.name}
        // Kratos sets the input type: email, password, text, and others.
        type={attr.type as "text" | "email" | "password" | "search" | "tel" | "url"}
        required={attr.required}
        disabled={attr.disabled}
        aria-invalid={messages.length > 0}
        // Never pre-fill password fields from the flow response.
        defaultValue={attr.type === "password" ? undefined : value}
      />
      <FieldError>{errorText || null}</FieldError>
    </Field>
  );
}

// Renders one Kratos UI node. Besides inputs, MFA settings flows emit `text` for the TOTP secret, `img` for the TOTP QR code, and `script` for the WebAuthn helper.
// With these, an operator can enrol a second factor for AAL2, per ADR-0304.
function FlowNode({ node, submitLabel }: { node: UiNode; submitLabel: string }) {
  const t = useTranslations("auth");
  const qrAlt = t("qrAlt");
  const attr = node.attributes;
  const labelText = node.meta.label ? node.meta.label.text : undefined;
  switch (nodeType(node)) {
    case "text":
      // for example, the TOTP shared secret to type into an authenticator app.
      return (
        <p className="break-all rounded bg-muted p-2 font-mono text-sm text-foreground">
          {attr.text?.text}
        </p>
      );
    case "img":
      return <ImgNode src={attr.src} alt={labelText ?? qrAlt} />;
    case "script":
      return <ScriptNode attr={attr} />;
    default:
      return <InputNode node={node} submitLabel={submitLabel} />;
  }
}

export function KratosFlow({
  kind,
  strings,
  footer,
}: {
  kind: FlowKind;
  strings: FlowStrings;
  footer?: ReactNode;
}) {
  const [flow, setFlow] = useState<Flow | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const id = new URLSearchParams(window.location.search).get("flow");
    if (!id) {
      restartFlow(kind);
      return;
    }
    fetch(`/auth/self-service/${kind}/flows?id=${encodeURIComponent(id)}`, {
      headers: { accept: "application/json" },
      credentials: "include",
    })
      .then((res) => {
        if (res.status === 404 || res.status === 410) {
          // The flow is expired or unknown, so start a new one.
          restartFlow(kind);
          return null;
        }
        if (!res.ok) {
          throw new Error(String(res.status));
        }
        return res.json() as Promise<Flow>;
      })
      .then((data) => data && setFlow(data))
      .catch(() => setFailed(true));
  }, [kind]);

  if (failed) {
    return (
      <main className="mx-auto max-w-md p-6">
        <h1 className="text-2xl font-semibold">{strings.title}</h1>
        <p className="mt-2 text-red-600">{strings.error}</p>
      </main>
    );
  }

  if (!flow) {
    return (
      <main className="mx-auto max-w-md p-6">
        <h1 className="text-2xl font-semibold">{strings.title}</h1>
        <p className="mt-2 text-muted-foreground">{strings.starting}</p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="text-2xl font-semibold">{strings.title}</h1>
      {flow.ui.messages?.map((message) => (
        <p key={message.id} className="mt-2 text-muted-foreground">
          {message.text}
        </p>
      ))}
      <form method={flow.ui.method} action={flow.ui.action} className="mt-4 space-y-3">
        {flow.ui.nodes.map((node) => (
          <FlowNode key={nodeKey(node)} node={node} submitLabel={strings.submit} />
        ))}
      </form>
      {footer}
    </main>
  );
}
