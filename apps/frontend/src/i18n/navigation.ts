// Locale-aware navigation (ADR-0400). These wrap `next/link`, `useRouter`,
// `redirect` and `usePathname` so an internal href never has to carry a locale
// prefix by hand: `<Link href="/panel">` resolves to `/de/panel` for a German
// reader. Importing `next/link` directly in a page is what silently sends every
// reader to the English URL, and is why lint:i18n forbids it outside this file.
import { createNavigation } from "next-intl/navigation";
import { routing } from "./routing";

export const { Link, redirect, usePathname, useRouter, getPathname } = createNavigation(routing);
