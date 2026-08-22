import { serve } from "../_shared/handler.ts";
import { HttpError, jsonResponse } from "../_shared/http.ts";
import {
  isAuthorizedScheduledRequest,
  parseNotificationScheduleScope,
} from "../_shared/scheduled-notifications.ts";
import { createAdminClient } from "../_shared/supabase-admin.ts";

serve(async (request, headers) => {
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!isAuthorizedScheduledRequest(request, serviceRoleKey)) {
    throw new HttpError(
      401,
      "SCHEDULE_AUTH_REQUIRED",
      "A service-role scheduler credential is required.",
    );
  }

  let scope;
  try {
    scope = parseNotificationScheduleScope(
      Deno.env.get("NOTIFICATION_SCHEDULE_ENABLED"),
      Deno.env.get("NOTIFICATION_SCHEDULE_CANARY_CHURCH_IDS"),
    );
  } catch {
    throw new HttpError(
      500,
      "NOTIFICATION_SCHEDULE_INVALID",
      "Notification schedule scope or local hour is not configured safely.",
    );
  }

  if (!scope.enabled) {
    return jsonResponse(
      {
        success: true,
        data: { enabled: false, tenantsScanned: 0, notificationsCreated: 0 },
      },
      200,
      headers,
    );
  }

  const admin = createAdminClient();
  const { data, error } = await admin.rpc(
    "run_tenant_pending_approval_digests",
    { p_church_ids: scope.churchIds },
  );
  if (error) {
    throw new HttpError(
      500,
      "APPROVAL_DIGEST_FAILED",
      "Unable to create pending approval digests.",
    );
  }
  return jsonResponse(
    {
      success: true,
      data: { enabled: true, ...(data as { data?: object }).data },
    },
    200,
    headers,
  );
});
