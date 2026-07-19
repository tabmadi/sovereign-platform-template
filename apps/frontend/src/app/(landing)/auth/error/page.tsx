// Kratos self-service error flow (ADR-0010, ADR-0014). Public route under
// (landing); the shared AuthError component renders the error detail.
import { AuthError } from "@/components/auth/AuthError";

export default function AuthErrorPage() {
  return <AuthError />;
}
