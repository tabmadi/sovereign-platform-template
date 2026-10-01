"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { isId } from "@libs/id";
// Cross-service mutation, per ADR-0302 and ADR-0400. The orders service returns 202 and a workflow handle.
// The seam in lib/data/orders.ts owns both the POST and the poll. This screen only decides what the user sees at each step.
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import {
  type ComponentProps,
  type Dispatch,
  type SetStateAction,
  useCallback,
  useMemo,
  useState,
} from "react";
import {
  type Control,
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

// The schema is built inside the component, not at module scope, because its message is copy.
// An English validation error on a German page is the part of localisation that people forget.
function makeSchema(invalidId: string) {
  return z.object({
    // A wire identifier, not a bare UUID, per ADR-0003. `isId` is the shared codec that both languages check, so the accepted shape always matches the one the services mint.
    product_id: z.string().refine((v) => isId(v, "product"), invalidId),
    quantity: z.number().int().positive(),
  });
}

type FormValues = z.output<ReturnType<typeof makeSchema>>;

type Status = { text: string; tone: ComponentProps<typeof Badge>["variant"] };

function ProductIdField({ control }: { control: Control<FormValues> }) {
  const t = useTranslations("panel.checkout");
  // A stable reference and not an inline arrow, because react-hook-form would remount an inline arrow on every keystroke.
  const render = useCallback(
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
          // An identifier is Latin script in every locale, so it keeps LTR on a mirrored page too.
          // Otherwise the `product_` prefix shows on the wrong end, and the value makes no sense.
          dir="ltr"
        />
        <FieldError errors={[fieldState.error]} />
      </Field>
    ),
    [t],
  );

  return <Controller control={control} name="product_id" render={render} />;
}

// A mutation, not an awaited call, and not for caching. A denial interrupt reaches forbidden.tsx only if it is thrown during a render,
// and React boundaries never see what an event handler throws. `throwOnError` in the panel providers throws it again, for denials only.
function usePlaceOrder(setStatus: Dispatch<SetStateAction<Status>>) {
  const t = useTranslations("panel.checkout");
  return useMutation({
    async mutationFn(values: FormValues) {
      const handle = await startOrder(values);
      setStatus({ text: t("running", { id: handle.id }), tone: "outline" });
      // The saga confirms the order when catalog and payment succeed, per ADR-0302.
      return await awaitOrder(handle);
    },
    onMutate() {
      setStatus({ text: t("starting"), tone: "outline" });
    },
    onSuccess(order) {
      // The status is the domain's own value, not copy. The code compares it with `confirmed` and shows it as it arrived.
      // A translated status is a status that the next reader cannot grep for in a log.
      setStatus({
        text: order.status,
        tone: order.status === "confirmed" ? "default" : "destructive",
      });
    },
    onError() {
      setStatus({ text: t("error"), tone: "destructive" });
    },
  });
}

export default function Checkout() {
  const t = useTranslations("panel.checkout");
  const [status, setStatus] = useState<Status>({ text: t("idle"), tone: "secondary" });
  const schema = useMemo(() => makeSchema(t("productIdInvalid")), [t]);

  const { control, handleSubmit } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { product_id: "", quantity: 1 },
  });

  const placeOrder = usePlaceOrder(setStatus);
  const onSubmit = handleSubmit((values) => placeOrder.mutate(values));

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="text-2xl font-semibold">{t("title")}</h1>
      <form onSubmit={onSubmit} className="mt-4 space-y-3">
        <ProductIdField control={control} />
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
