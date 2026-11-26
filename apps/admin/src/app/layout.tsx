// The frame of every console page: the navigation from the manifest and the operator that the edge forwarded.
import type { Metadata } from "next";
import { headers } from "next/headers";
import Link from "next/link";
import type { ReactNode } from "react";
import { manifest } from "@/lib/manifest";
import { text } from "@/lib/text";
import "./styles.css";

export const metadata: Metadata = { title: text.brand };
// Every page reads the identity header and live service data, so nothing renders at build time.
export const dynamic = "force-dynamic";

export default async function Layout({ children }: { children: ReactNode }) {
  // Oathkeeper sets this header after the edge checks the operator claim and AAL2, per ADR-0401.
  const operator = (await headers()).get("x-user-email") ?? "";
  return (
    <html lang="en">
      <body>
        <nav aria-label="Console">
          <p className="brand">
            <Link href="/">{text.brand}</Link>
          </p>
          {operator ? <p className="operator">{operator}</p> : null}
          <ul>
            <li>
              <Link href="/">{text.dashboard}</Link>
            </li>
          </ul>
          {manifest.groups.map((group) => (
            <section key={group.service}>
              <h2>{group.title}</h2>
              <ul>
                {group.links.map((link) => (
                  <li key={link.page}>
                    <Link href={`/${link.page}`}>{link.title}</Link>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </nav>
        <main>{children}</main>
      </body>
    </html>
  );
}
