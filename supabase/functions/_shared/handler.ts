import { corsHeaders } from "./cors.ts";
import { HttpError, jsonResponse } from "./http.ts";

export function serve(
  handler: (request: Request, headers: HeadersInit) => Promise<Response>,
): void {
  Deno.serve(async (request) => {
    let headers: HeadersInit = {};
    try {
      headers = corsHeaders(request);
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers });
      }
      if (request.method !== "POST") {
        return jsonResponse(
          { success: false, error: { code: "METHOD_NOT_ALLOWED" } },
          405,
          { ...headers, allow: "POST, OPTIONS" },
        );
      }
      return await handler(request, headers);
    } catch (error) {
      if (!(error instanceof HttpError)) {
        console.error("Unhandled edge function error", {
          name: error instanceof Error ? error.name : typeof error,
          message: error instanceof Error ? error.message : String(error),
        });
      }
      const known = error instanceof HttpError
        ? error
        : new HttpError(500, "INTERNAL_ERROR", "Unexpected server error.");
      return jsonResponse(
        {
          success: false,
          error: { code: known.code, message: known.message },
        },
        known.status,
        headers,
      );
    }
  });
}
