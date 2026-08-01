import type { SupabaseClient, User } from "@supabase/supabase-js";
import { serve } from "../_shared/handler.ts";
import { HttpError, jsonResponse, readJson } from "../_shared/http.ts";
import { syntheticLineEmail, verifyLineIdToken } from "../_shared/line.ts";
import { createAdminClient } from "../_shared/supabase-admin.ts";

interface LineAuthRequest {
  idToken?: string;
  nonce?: string;
  inviteToken?: string;
}

interface AppUser {
  id: string;
  auth_user_id: string;
  last_active_church_id: string | null;
  is_active: boolean;
}

interface TenantMembership {
  id: string;
  church_id: string;
  churches: {
    id: string;
    slug: string;
    name: string;
    status: string;
    is_active: boolean;
    deleted_at: string | null;
  };
}

async function loadOrCreateIdentity(
  admin: SupabaseClient,
  lineUserId: string,
  displayName: string,
  pictureUrl: string | null,
  verifiedEmail: string | null,
): Promise<{ appUser: AppUser; authUser: User; authEmail: string }> {
  const { data: existing, error: lookupError } = await admin
    .from("users")
    .select("id, auth_user_id, last_active_church_id, is_active")
    .eq("line_user_id", lineUserId)
    .maybeSingle<AppUser>();

  if (lookupError) throw new HttpError(500, "IDENTITY_LOOKUP_FAILED", "Unable to resolve identity.");

  if (existing) {
    if (!existing.is_active) {
      throw new HttpError(403, "USER_INACTIVE", "This user account is inactive.");
    }
    const { data, error } = await admin.auth.admin.getUserById(existing.auth_user_id);
    if (error || !data.user) {
      throw new HttpError(409, "AUTH_IDENTITY_MISSING", "The linked authentication identity is missing.");
    }

    const authEmail = data.user.email ?? await syntheticLineEmail(lineUserId);
    const profileChanges: Record<string, string | null> = {
      display_name: displayName,
      picture_url: pictureUrl,
      last_login_at: new Date().toISOString(),
    };
    if (verifiedEmail) profileChanges.email = verifiedEmail;

    const { error: profileError } = await admin
      .from("users")
      .update(profileChanges)
      .eq("id", existing.id);
    if (profileError) throw new HttpError(500, "PROFILE_SYNC_FAILED", "Unable to synchronize profile.");

    return { appUser: existing, authUser: data.user, authEmail };
  }

  const authEmail = await syntheticLineEmail(lineUserId);
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: authEmail,
    email_confirm: true,
    user_metadata: { auth_provider: "line" },
  });
  if (createError || !created.user) {
    throw new HttpError(500, "AUTH_IDENTITY_CREATE_FAILED", "Unable to create authentication identity.");
  }

  const { data: inserted, error: insertError } = await admin
    .from("users")
    .insert({
      auth_user_id: created.user.id,
      line_user_id: lineUserId,
      display_name: displayName,
      picture_url: pictureUrl,
      email: verifiedEmail,
      global_role: "user",
      is_active: true,
      last_login_at: new Date().toISOString(),
    })
    .select("id, auth_user_id, last_active_church_id, is_active")
    .single<AppUser>();

  if (insertError || !inserted) {
    // Compensate only for the Auth identity created by this invocation.
    await admin.auth.admin.deleteUser(created.user.id, true);
    throw new HttpError(409, "IDENTITY_CREATE_CONFLICT", "Unable to create application identity.");
  }

  return { appUser: inserted, authUser: created.user, authEmail };
}

async function selectableTenants(
  admin: SupabaseClient,
  appUserId: string,
): Promise<TenantMembership[]> {
  const { data, error } = await admin
    .from("church_members")
    .select("id, church_id, churches!inner(id, slug, name, status, is_active, deleted_at)")
    .eq("user_id", appUserId)
    .eq("status", "active")
    .in("churches.status", ["trial", "active"])
    .eq("churches.is_active", true)
    .is("churches.deleted_at", null);
  if (error) throw new HttpError(500, "TENANT_LOOKUP_FAILED", "Unable to load tenant access.");
  return (data ?? []) as unknown as TenantMembership[];
}

serve(async (request, headers) => {
  const body = await readJson<LineAuthRequest>(request);
  if (!body.idToken || body.idToken.length > 12_000) {
    throw new HttpError(400, "LINE_ID_TOKEN_REQUIRED", "A valid LINE ID token is required.");
  }

  const line = await verifyLineIdToken(body.idToken, body.nonce);
  const admin = createAdminClient();
  const displayName = (line.name?.trim() || "LINE User").slice(0, 255);
  const pictureUrl = line.picture?.slice(0, 2_048) ?? null;
  const verifiedEmail = line.email?.slice(0, 255) ?? null;
  const { appUser, authUser, authEmail } = await loadOrCreateIdentity(
    admin,
    line.sub,
    displayName,
    pictureUrl,
    verifiedEmail,
  );

  let invitedTenantId: string | null = null;
  if (body.inviteToken) {
    if (body.inviteToken.length < 32 || body.inviteToken.length > 256) {
      throw new HttpError(400, "INVITATION_TOKEN_INVALID", "The invitation link is invalid.");
    }
    const { data: invitation, error: invitationError } = await admin.rpc(
      "accept_tenant_invitation_by_token",
      {
        p_user_id: appUser.id,
        p_raw_token: body.inviteToken,
      },
    );
    if (invitationError) {
      const code = invitationError.message || "INVITATION_ACCEPT_FAILED";
      const status = code.includes("ALREADY_USED") ? 409 : 400;
      throw new HttpError(status, code, "Unable to accept the invitation link.");
    }
    invitedTenantId = (invitation as { tenantId?: string } | null)?.tenantId ?? null;
  } else if (verifiedEmail) {
    const { error: invitationError } = await admin.rpc(
      "accept_tenant_invitations_for_user",
      {
        p_user_id: appUser.id,
        p_verified_email: verifiedEmail,
      },
    );
    if (invitationError) {
      throw new HttpError(
        500,
        "INVITATION_ACCEPT_FAILED",
        "Unable to accept the pending tenant invitation.",
      );
    }
  }

  const memberships = await selectableTenants(admin, appUser.id);
  const existingClaim = authUser.app_metadata?.active_church_id as string | undefined;
  const existingIsValid = memberships.some((item) => item.church_id === existingClaim);
  const invitedIsValid = memberships.some((item) => item.church_id === invitedTenantId);
  const activeChurchId = invitedIsValid
    ? invitedTenantId
    : existingIsValid
    ? existingClaim!
    : memberships.length === 1
    ? memberships[0].church_id
    : null;

  const { error: metadataError } = await admin.auth.admin.updateUserById(
    authUser.id,
    {
      app_metadata: {
        ...authUser.app_metadata,
        auth_provider: "line",
        active_church_id: activeChurchId,
      },
    },
  );
  if (metadataError) throw new HttpError(500, "TENANT_CLAIM_UPDATE_FAILED", "Unable to set tenant context.");

  if (activeChurchId !== appUser.last_active_church_id) {
    const { error } = await admin
      .from("users")
      .update({ last_active_church_id: activeChurchId })
      .eq("id", appUser.id);
    if (error) throw new HttpError(500, "PROFILE_SYNC_FAILED", "Unable to store tenant preference.");
  }

  const activeMembership = memberships.find((item) => item.church_id === activeChurchId);
  const { error: auditError } = await admin.from("audit_logs").insert({
    church_id: activeChurchId,
    user_id: appUser.id,
    actor_church_member_id: activeMembership?.id ?? null,
    entity_type: "users",
    entity_id: appUser.id,
    action: "line_login",
    metadata: { selectable_tenant_count: memberships.length },
  });
  if (auditError) throw new HttpError(500, "AUDIT_WRITE_FAILED", "Unable to audit LINE login.");

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: authEmail,
  });
  const tokenHash = link?.properties?.hashed_token;
  if (linkError || !tokenHash) {
    throw new HttpError(500, "SESSION_EXCHANGE_FAILED", "Unable to create session exchange.");
  }

  return jsonResponse({
    success: true,
    data: {
      tokenHash,
      verificationType: "email",
      activeTenantId: activeChurchId,
      requiresTenantSelection: memberships.length > 1 && !activeChurchId,
      tenants: memberships.map((item) => ({
        tenantId: item.church_id,
        slug: item.churches.slug,
        name: item.churches.name,
      })),
    },
  }, 200, headers);
});
