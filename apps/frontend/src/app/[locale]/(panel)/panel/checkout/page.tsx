"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { isId } from "@libs/id";
// Cross-service mutation (ADR-0302, ADR-0400). The orders service returns 202 + a
// workflow handle, and the seam (lib/data/orders.ts) owns both the POST and the
// poll — this screen only decides what the user is told at each step.
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { type ComponentProps, useCallback, useMemo, useState } from "react";
import {
  Controller,
  type ControllerFieldState,
  type ControllerRenderProps,
  useForm,
} from "react-hook-form";
import { z } from "zod";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { awaitOrder, startOrder } from "@/lib/data/orders";

// The schema is built inside the component, not at module scope, because its
// message is copy: a validation error the user reads in English on a German page is
// the half of localisation that gets forgotten.
function makeSchema(invalidId: string) {
  return z.object({
    // A wire identifier, not a bare UUID (ADR-0003). `isId` is the shared codec both languages check against, so the accepted shape cannot drift from the one the services mint.
    product_id: z.string().refine((v) => isId(v, "product"), invalidId),
    quantity: z.number().int().positive(),
  });
}

type FormValues = z.output<ReturnType<typeof makeSchema>>;

type Status = { text: string; tone: ComponentProps<typeof Badge>["variant"] };

export default function Checkout() {
  const t = useTranslations("panel.checkout");
  const [status, setStatus] = useState<Status>({ text: t("idle"), tone: "secondary" });
  const schema = useMemo(() => makeSchema(t("productIdInvalid")), [t]);

  const { control, handleSubmit } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { product_id: "", quantity: 1 },
  });

  // A stable reference rather than an inline arrow, which react-hook-form would
  // remount on every keystroke.
  const renderProductId = useCallback(
    ({
      field,
      fieldState,
    }: {
      field: ControllerRenderProps<FormValues, "product_id">;
      fieldState: ControllerFieldState;
    }) => (
      <Field data-invalid={fieldState.invalid}>
        <FieldLabel htmlFor="product-id">{t("productLabel")}</FieldLabel>
        <Input
          id="product-id"
          name={field.name}
          ref={field.ref}
          value={field.value}
          onChange={field.onChange}
          onBlur={field.onBlur}
          aria-invalid={fieldState.invalid}
          placeholder={t("productPlaceholder")}
          // An identifier is Latin-script in every locale, so it keeps LTR even on
          // a mirrored page — otherwise the `product_` prefix renders on the wrong
          // end and the value reads as nonsense.
          dir="ltr"
        />
        <FieldError errors={[fieldState.error]} />
      </Field>
    ),
    [t],
  );

  // A mutation, not an awaited call, and not for the caching: a denial interrupt only reaches forbidden.tsx if it
  // is thrown during a render, and React boundaries never see what an event handler throws.
  // `throwOnError` in the panel providers does the re-throw, for denials only.
  const placeOrder = useMutation({
    async mutationFn(values: FormValues) {
      const handle = await startOrder(values);
      setStatus({ text: t("running", { id: handle.id }), tone: "outline" });
      // The saga confirms the order once catalog + payment succeed (ADR-0302).
      return await awaitOrder(handle);
    },
    onMutate() {
      setStatus({ text: t("starting"), tone: "outline" });
    },
    onSuccess(order) {
      // The status is the domain's own value, not copy: it is compared against
      // "confirmed" and shown as it arrived. A translated status is a status the
      // next reader cannot grep for in a log.
      setStatus({
        text: order.status,
        tone: order.status === "confirmed" ? "default" : "destructive",
      });
    },
    onError() {
      setStatus({ text: t("error"), tone: "destructive" });
    },
  });

  const onSubmit = handleSubmit((values) => placeOrder.mutate(values));

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="text-2xl font-semibold">{t("title")}</h1>
      <form onSubmit={onSubmit} className="mt-4 space-y-3">
        <Controller control={control} name="product_id" render={renderProductId} />
        <Button type="submit" disabled={placeOrder.isPending}>
          {t("buy")}
        </Button>
      </form>
      <div className="mt-3">
        <Badge variant={status.tone}>{status.text}</Badge>
      </div>
    </main>
  );
}
