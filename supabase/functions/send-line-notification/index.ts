import { serve } from "../_shared/handler.ts";
import { HttpError, jsonResponse } from "../_shared/http.ts";
import {
  type ClaimedLineDelivery,
  isAuthorizedWorkerRequest,
  normalizeDeliveryBaseUrl,
  parseDeliveryScope,
  pushLineNotification,
  safeDeliveryLogContext,
} from "../_shared/line-delivery.ts";
import { createAdminClient } from "../_shared/supabase-admin.ts";

interface WorkerRequest {
  limit?: number;
}

async function optionalBody(request: Request): Promise<WorkerRequest> {
  const text = await request.text();
  if (!text.trim()) return {};
  try {
    return JSON.parse(text) as WorkerRequest;
  } catch {
    throw new HttpError(
      400,
      "INVALID_JSON",
      "Request body must be valid JSON.",
    );
  }
}

serve(async (request, headers) => {
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!isAuthorizedWorkerRequest(request, serviceRoleKey)) {
    throw new HttpError(
      401,
      "WORKER_AUTH_REQUIRED",
      "A service-role worker credential is required.",
    );
  }

  let scope;
  try {
    scope = parseDeliveryScope(
      Deno.env.get("LINE_DELIVERY_ENABLED"),
      Deno.env.get("LINE_DELIVERY_CANARY_CHURCH_IDS"),
    );
  } catch {
    throw new HttpError(
      500,
      "LINE_DELIVERY_SCOPE_INVALID",
      "LINE delivery scope is not configured safely.",
    );
  }

  if (!scope.enabled) {
    return jsonResponse(
      {
        success: true,
        data: { enabled: false, claimed: 0, sent: 0, failed: 0, deadLetter: 0 },
      },
      200,
      headers,
    );
  }

  const channelAccessToken =
    Deno.env.get("LINE_MESSAGING_CHANNEL_ACCESS_TOKEN")?.trim() ?? "";
  if (!channelAccessToken) {
    throw new HttpError(
      500,
      "LINE_ACCESS_TOKEN_MISSING",
      "LINE delivery credentials are not configured.",
    );
  }

  let baseUrl: URL;
  try {
    baseUrl = normalizeDeliveryBaseUrl(
      Deno.env.get("LINE_DELIVERY_APP_BASE_URL"),
    );
  } catch {
    throw new HttpError(
      500,
      "LINE_DELIVERY_URL_INVALID",
      "LINE delivery application URL is not configured.",
    );
  }

  const body = await optionalBody(request);
  const limit = body.limit ?? 20;
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) {
    throw new HttpError(
      400,
      "INVALID_DELIVERY_CLAIM_LIMIT",
      "limit must be an integer from 1 to 50.",
    );
  }

  const admin = createAdminClient();
  const { data: claimed, error: claimError } = await admin.rpc(
    "claim_line_notification_deliveries",
    {
      p_limit: limit,
      p_church_ids: scope.churchIds,
    },
  );
  if (claimError) {
    throw new HttpError(
      500,
      "DELIVERY_CLAIM_FAILED",
      "Unable to claim LINE delivery work.",
    );
  }

  const deliveries = (claimed ?? []) as ClaimedLineDelivery[];
  let sent = 0;
  let failed = 0;
  let deadLetter = 0;
  let finalizationFailed = 0;

  for (const delivery of deliveries) {
    const result = await pushLineNotification(
      delivery,
      channelAccessToken,
      baseUrl,
    );
    const { data: completion, error: completionError } = await admin.rpc(
      "complete_line_notification_delivery",
      {
        p_delivery_id: delivery.delivery_id,
        p_delivery_cycle: delivery.delivery_cycle,
        p_attempt_count: delivery.attempt_count,
        p_outcome: result.outcome,
        p_provider_message_id: result.providerMessageId,
        p_error_code: result.errorCode,
        p_error_message: result.errorMessage,
      },
    );

    if (completionError) {
      finalizationFailed += 1;
      console.error(
        "LINE delivery finalization failed",
        safeDeliveryLogContext(delivery, "finalization_failed"),
      );
      continue;
    }

    const status = (completion as { data?: { status?: string } } | null)?.data
      ?.status;
    if (status === "sent") sent += 1;
    else if (status === "dead_letter") deadLetter += 1;
    else failed += 1;
    console.info(
      "LINE delivery processed",
      safeDeliveryLogContext(delivery, status ?? "unknown"),
    );
  }

  return jsonResponse(
    {
      success: true,
      data: {
        enabled: true,
        claimed: deliveries.length,
        sent,
        failed,
        deadLetter,
        finalizationFailed,
      },
    },
    200,
    headers,
  );
});
