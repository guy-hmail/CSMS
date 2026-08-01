import { HttpError } from "./http.ts";

export interface VerifiedLineIdentity {
  sub: string;
  name?: string;
  picture?: string;
  email?: string;
}

export function lineVerificationErrorCode(description?: string): string {
  return description?.toLowerCase().includes("expired")
    ? "LINE_TOKEN_EXPIRED"
    : "LINE_TOKEN_INVALID";
}

export async function verifyLineIdToken(
  idToken: string,
  nonce?: string,
): Promise<VerifiedLineIdentity> {
  const channelId = Deno.env.get("LINE_CHANNEL_ID");
  if (!channelId) {
    throw new HttpError(500, "SERVER_MISCONFIGURED", "LINE_CHANNEL_ID is not configured.");
  }

  const form = new URLSearchParams({ id_token: idToken, client_id: channelId });
  if (nonce) form.set("nonce", nonce);

  const response = await fetch("https://api.line.me/oauth2/v2.1/verify", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: form,
  });

  if (!response.ok) {
    const failure = await response.json().catch(() => null) as {
      error?: string;
      error_description?: string;
    } | null;
    console.warn("LINE ID token verification rejected", {
      status: response.status,
      error: failure?.error ?? "unknown_error",
      description: failure?.error_description ?? "No description returned by LINE.",
    });
    const code = lineVerificationErrorCode(failure?.error_description);
    const message = code === "LINE_TOKEN_EXPIRED"
      ? "The LINE session has expired. Please sign in again."
      : "LINE authentication could not be verified.";
    throw new HttpError(401, code, message);
  }

  const identity = await response.json() as VerifiedLineIdentity;
  if (!identity.sub) {
    throw new HttpError(401, "LINE_TOKEN_INVALID", "LINE token has no subject.");
  }
  return identity;
}

export async function syntheticLineEmail(lineUserId: string): Promise<string> {
  const channelId = Deno.env.get("LINE_CHANNEL_ID") ?? "";
  const bytes = new TextEncoder().encode(`${channelId}:${lineUserId}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hash = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `line-${hash}@auth.csms.invalid`;
}
