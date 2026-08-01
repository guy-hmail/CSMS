import { HttpError } from "./http.ts";

function configuredOrigins(): Set<string> {
  const value = Deno.env.get("ALLOWED_ORIGINS") ?? "";
  return new Set(
    value
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  );
}

export function corsHeaders(request: Request): HeadersInit {
  const origin = request.headers.get("origin");
  if (!origin) return {};

  if (!configuredOrigins().has(origin)) {
    throw new HttpError(403, "ORIGIN_NOT_ALLOWED", "Request origin is not allowed.");
  }

  return {
    "access-control-allow-origin": origin,
    "access-control-allow-headers":
      "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-max-age": "86400",
    "vary": "Origin",
  };
}
