// The committed deterministic test identities, provisioned the same way everywhere (ADR-0601).
export type TestIdentity = {
  label: "operator" | "user" | "admin";
  email: string;
  password: string;
  // operator => enrolled in TOTP (AAL2) and added to group:operator at bootstrap.
  operator: boolean;
  // true => deleted and recreated per e2e run; false => created once, then kept.
  reset: boolean;
};

export const OPERATOR: TestIdentity = {
  label: "operator",
  email: "operator@e2e.localtest.me",
  password: "0perator-e2e-Sessi0n!",
  operator: true,
  reset: true,
};

export const ADMIN: TestIdentity = {
  label: "admin",
  email: "admin@localtest.me",
  password: "1st Password!",
  operator: true,
  reset: false,
};

export const USER: TestIdentity = {
  label: "user",
  email: "user@e2e.localtest.me",
  password: "Pr0duct-e2e-Sessi0n!",
  operator: false,
  reset: true,
};

export const IDENTITIES: TestIdentity[] = [OPERATOR, ADMIN, USER];
