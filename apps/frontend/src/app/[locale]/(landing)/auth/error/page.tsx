// Kratos self-service error flow, a public route under the landing shell (ADR-0304, ADR-0400).
import { AuthError } from "@/components/auth/AuthError";

export default function AuthErrorPage() {
  return <AuthError />;
}
