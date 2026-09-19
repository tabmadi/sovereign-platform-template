import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { ApiReference } from "./api-reference";

// Metadata is copy too, so it is translated like the rest — a page whose <title>
// stays English in a German tab is a page that is half localised.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("devportal");
  return { title: t("title"), description: t("description") };
}

// Developer portal (ADR-0305): the internal projection of every service's OpenAPI
// spec, rendered by Scalar behind the (devportal) Kratos session gate.
export default function DevPortal() {
  return <ApiReference />;
}
