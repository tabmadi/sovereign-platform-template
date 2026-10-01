import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { ApiReference } from "./api-reference";

// Metadata is copy too, so it is translated like the rest. A page with an English <title> in a German tab is only half localised.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("devportal");
  return { title: t("title"), description: t("description") };
}

// Developer portal, per ADR-0305: the internal projection of the OpenAPI spec of every service.
// Scalar renders it behind the Kratos session gate of the `(devportal)` group.
export default function DevPortal() {
  return <ApiReference />;
}
