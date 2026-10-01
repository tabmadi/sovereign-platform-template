// Locale-aware navigation, per ADR-0400. It wraps `next/link` and `useRouter`, so a href keeps its locale.
import { createNavigation } from "next-intl/navigation";
import { routing } from "./routing";

export const { Link, redirect, usePathname, useRouter, getPathname } = createNavigation(routing);
