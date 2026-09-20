// Shared e2e environment constants (ADR-0306), host-agnostic and overridable.
import path from "node:path";

export const HOST = process.env.E2E_HOST ?? "dev.localtest.me:8443";
export const BASE_URL = `https://${HOST}`;

// The right-to-left locale (ADR-0400). Without a spec that visits it, `fa` rots quietly: the copy stays translated and the layout stops being checked.
export const RTL_LOCALE = "fa";
export const rtlURL = (path = ""): string => `${BASE_URL}/${RTL_LOCALE}${path}`;

// Operator dashboards each live on their own origin `{tool}.ops.<host>` (ADR-0306).
export const opsURL = (tool: string): string => `https://${tool}.ops.${HOST}`;

export const LOGIN_URL = `${BASE_URL}/auth/login`;
// The app route is /auth/register; Kratos' FLOW is named "registration" and the two
// are easy to confuse. A spec that navigates to /auth/registration gets a 404 and a
// failure that reads as a missing form, so the path lives here once.
export const REGISTER_URL = `${BASE_URL}/auth/register`;
export const SETTINGS_URL = `${BASE_URL}/auth/settings`;

export const AUTH_DIR = path.join(process.cwd(), ".auth");
export const OPERATOR_STATE = path.join(AUTH_DIR, "operator.json");
export const USER_STATE = path.join(AUTH_DIR, "user.json");
// The operator's enrolled TOTP secret, so the interactive login smoke can step up
// to AAL2 from a fresh context without re-enrolling.
export const OPERATOR_TOTP_FILE = path.join(AUTH_DIR, "operator-totp.txt");
