import { corsHeaders } from "./cors.ts";
import { HttpError } from "./http.ts";
import { lineVerificationErrorCode, syntheticLineEmail } from "./line.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("synthetic LINE email is deterministic and does not expose LINE user ID", async () => {
  Deno.env.set("LINE_CHANNEL_ID", "test-channel");
  const first = await syntheticLineEmail("U-sensitive-user-id");
  const second = await syntheticLineEmail("U-sensitive-user-id");

  assert(first === second, "synthetic email must be deterministic");
  assert(first.endsWith("@auth.csms.invalid"), "synthetic email domain");
  assert(!first.includes("U-sensitive-user-id"), "LINE user ID must not be exposed");
});

Deno.test("expired LINE ID tokens are classified for reauthentication", () => {
  assert(
    lineVerificationErrorCode("IdToken expired.") === "LINE_TOKEN_EXPIRED",
    "expired token should trigger reauthentication",
  );
  assert(
    lineVerificationErrorCode("Invalid IdToken.") === "LINE_TOKEN_INVALID",
    "other verification failures should remain invalid",
  );
});

Deno.test("CORS accepts only configured exact origins", () => {
  Deno.env.set("ALLOWED_ORIGINS", "http://localhost:5173,https://app.example.test");
  const allowed = new Request("https://edge.example.test", {
    headers: { origin: "https://app.example.test" },
  });
  const headers = new Headers(corsHeaders(allowed));
  assert(
    headers.get("access-control-allow-origin") === "https://app.example.test",
    "configured origin should be reflected",
  );
  const allowedHeaders = headers.get("access-control-allow-headers") ?? "";
  assert(
    allowedHeaders.includes("x-client-info") &&
      allowedHeaders.includes("x-supabase-api-version"),
    "Supabase browser client headers should be allowed",
  );

  const denied = new Request("https://edge.example.test", {
    headers: { origin: "https://evil.example.test" },
  });
  try {
    corsHeaders(denied);
    throw new Error("unconfigured origin was accepted");
  } catch (error) {
    assert(
      error instanceof HttpError && error.code === "ORIGIN_NOT_ALLOWED",
      "unconfigured origin should be rejected",
    );
  }
});
