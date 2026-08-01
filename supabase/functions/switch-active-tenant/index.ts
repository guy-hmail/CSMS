import { serve } from "../_shared/handler.ts";
import { HttpError, jsonResponse, readJson } from "../_shared/http.ts";
import { bearerToken, createAdminClient } from "../_shared/supabase-admin.ts";

interface SwitchTenantRequest {
  tenantId?: string;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

serve(async (request, headers) => {
  const body = await readJson<SwitchTenantRequest>(request);
  if (!body.tenantId || !UUID_PATTERN.test(body.tenantId)) {
    throw new HttpError(400, "INVALID_TENANT_ID", "A valid tenant ID is required.");
  }

  const admin = createAdminClient();
  const accessToken = bearerToken(request);
  const { data: authData, error: authError } = await admin.auth.getUser(accessToken);
  if (authError || !authData.user) {
    throw new HttpError(401, "AUTH_REQUIRED", "The Supabase session is invalid.");
  }

  const { data: appUser, error: userError } = await admin
    .from("users")
    .select("id, last_active_church_id")
    .eq("auth_user_id", authData.user.id)
    .eq("is_active", true)
    .is("deleted_at", null)
    .maybeSingle();
  if (userError || !appUser) {
    throw new HttpError(403, "USER_NOT_FOUND", "No active application user was found.");
  }

  const { data: membership, error: membershipError } = await admin
    .from("church_members")
    .select("id, church_id, churches!inner(id, status, is_active, deleted_at)")
    .eq("user_id", appUser.id)
    .eq("church_id", body.tenantId)
    .eq("status", "active")
    .in("churches.status", ["trial", "active"])
    .eq("churches.is_active", true)
    .is("churches.deleted_at", null)
    .maybeSingle();
  if (membershipError || !membership) {
    throw new HttpError(403, "TENANT_ACCESS_DENIED", "The requested tenant is not selectable.");
  }

  const { error: metadataError } = await admin.auth.admin.updateUserById(
    authData.user.id,
    {
      app_metadata: {
        ...authData.user.app_metadata,
        active_church_id: body.tenantId,
      },
    },
  );
  if (metadataError) throw new HttpError(500, "TENANT_CLAIM_UPDATE_FAILED", "Unable to switch tenant.");

  const { error: completionError } = await admin.rpc("complete_tenant_switch", {
    p_auth_user_id: authData.user.id,
    p_tenant_id: body.tenantId,
  });
  if (completionError) {
    await admin.auth.admin.updateUserById(authData.user.id, {
      app_metadata: {
        ...authData.user.app_metadata,
        active_church_id: authData.user.app_metadata?.active_church_id ?? null,
      },
    });
    throw new HttpError(500, "TENANT_SWITCH_FAILED", "Unable to complete tenant switch.");
  }

  return jsonResponse({
    success: true,
    data: {
      tenantId: body.tenantId,
      sessionRefreshRequired: true,
      redirectTo: "/app/dashboard",
    },
  }, 200, headers);
});
