import Link from "next/link";
import { landing } from "@/strings/landing";

export default function Landing() {
  return (
    <main className="mx-auto max-w-3xl p-6">
      <h1 className="text-3xl font-semibold">{landing.title}</h1>
      <p className="mt-2 text-tertiary">{landing.tagline}</p>
      <ul className="mt-6 space-y-2">
        <li>
          <Link href="/auth/login" className="text-brand-600 hover:underline">
            {landing.signIn}
          </Link>
        </li>
        <li>
          <Link href="/auth/register" className="text-brand-600 hover:underline">
            {landing.createAccount}
          </Link>
        </li>
        <li>
          <Link href="/auth/recovery" className="text-brand-600 hover:underline">
            {landing.forgotPassword}
          </Link>
        </li>
        <li>
          <Link href="/auth/settings" className="text-brand-600 hover:underline">
            {landing.accountSettings}
          </Link>
        </li>
        <li>
          <Link href="/panel" className="text-brand-600 hover:underline">
            {landing.customerPanel}
          </Link>
        </li>
        <li>
          <Link href="/devportal" className="text-brand-600 hover:underline">
            {landing.developerPortal}
          </Link>
        </li>
      </ul>
    </main>
  );
}
