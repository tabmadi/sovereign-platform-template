// Shared e2e environment constants, per ADR-0306. They do not depend on a host, and an environment variable can override them.
import path from "node:path";

export const HOST = process.env.E2E_HOST ?? "dev.localtest.me:8443";
export const BASE_URL = `https://${HOST}`;

// The right-to-left locale, per ADR-0400. Without a spec that visits it, `fa` breaks with no signal: the copy stays translated, and nothing checks the layout.
export const RTL_LOCALE = "fa";
export const rtlURL = (path = ""): string => `${BASE_URL}/${RTL_LOCALE}${path}`;

// Each operator dashboard has its own origin `{tool}.ops.<host>`, per ADR-0306.
export const opsURL = (tool: string): string => `https://${tool}.ops.${HOST}`;

export const LOGIN_URL = `${BASE_URL}/auth/login`;
// The app route is /auth/register, and the Kratos flow is named `registration`. The two are easy to confuse.
// A spec that goes to /auth/registration gets a 404 and a failure that looks like a missing form. So the path is defined here once.
export const REGISTER_URL = `${BASE_URL}/auth/register`;
export const SETTINGS_URL = `${BASE_URL}/auth/settings`;

export const AUTH_DIR = path.join(process.cwd(), ".auth");
export const OPERATOR_STATE = path.join(AUTH_DIR, "operator.json");
export const USER_STATE = path.join(AUTH_DIR, "user.json");
// The operator's enrolled TOTP secret. With it, the interactive login smoke can step up to AAL2 from a new context without a new enrolment.
export const OPERATOR_TOTP_FILE = path.join(AUTH_DIR, "operator-totp.txt");
