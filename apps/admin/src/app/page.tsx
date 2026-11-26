// The hand-written landing page. The generator makes only the pages of one service, so a view across services lives here.
import Link from "next/link";
import { manifest } from "@/lib/manifest";
import { text } from "@/lib/text";

export default function Dashboard() {
  return (
    <>
      <h1>{text.brand}</h1>
      <p>{text.intro}</p>
      <p>{text.generated}</p>
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
    </>
  );
}
