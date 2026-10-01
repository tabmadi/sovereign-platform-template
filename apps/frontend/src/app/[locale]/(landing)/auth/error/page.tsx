// Kratos self-service error flow, a public route under the landing shell, per ADR-0304 and ADR-0400.
import { AuthError } from "@/components/auth/AuthError";

export default function AuthErrorPage() {
  return <AuthError />;
}
