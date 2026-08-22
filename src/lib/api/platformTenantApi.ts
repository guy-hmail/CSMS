import type { SupabaseClient } from '@supabase/supabase-js';
import { BackendError } from './rpc';

export type PlatformTenantStatus =
  | 'provisioning'
  | 'trial'
  | 'active'
  | 'suspended'
  | 'closed';

export type PlatformTenant = {
  id: string;
  name: string;
  slug: string;
  rootOuName: string;
  adminName: string;
  adminEmail: string;
  memberCount: number;
  ouCount: number;
  status: PlatformTenantStatus;
  approvalMode: 'auto_approve' | 'approval_required';
  createdAt: string;
};

type PlatformTenantRow = {
  id: string;
  name: string;
  slug: string;
  root_ou_name: string;
  admin_name: string;
  admin_email: string;
  member_count: number;
  ou_count: number;
  status: PlatformTenantStatus;
  approval_mode: 'auto_approve' | 'approval_required';
  created_at: string;
};

export type CreatePlatformTenantInput = {
  name: string;
  slug: string;
  rootOuName: string;
  adminName: string;
  adminEmail: string;
  timezone: string;
  weekEndsOn: 'sunday' | 'saturday';
  submissionDeadlineDaysAfterPeriodEnd: number;
  approvalMode: 'auto_approve' | 'approval_required';
};

export type PlatformAdminInvite = {
  tenantId: string;
  tenantName: string;
  invitationId: string;
  inviteToken: string;
  expiresAt: string;
};

export type PlatformTenantDetail = {
  id: string;
  code: string;
  name: string;
  slug: string;
  description: string | null;
  timezone: string;
  approvalMode: 'auto_approve' | 'approval_required';
  weekEndsOn: 'sunday' | 'saturday';
  submissionDeadlineDaysAfterPeriodEnd: number;
  status: PlatformTenantStatus;
  trialEndsAt: string | null;
  createdAt: string;
  updatedAt: string;
  provisioning: {
    rootOuCount: number;
    ouTypeCount: number;
    metricCount: number;
    memberCount: number;
    ready: boolean;
  };
};

export type PlatformTenantInvitation = {
  id: string;
  email: string | null;
  displayName: string | null;
  permission: string;
  status: 'pending' | 'accepted' | 'expired' | 'revoked';
  expiresAt: string;
  acceptedAt: string | null;
  revokedAt: string | null;
  createdAt: string;
};

export type PlatformTenantActivity = {
  id: string;
  action: string;
  entityType: string;
  entityId: string | null;
  actorName: string;
  beforeData: Record<string, unknown> | null;
  afterData: Record<string, unknown> | null;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type PlatformNotificationOperations = {
  tenantId: string;
  windowHours: number;
  generatedAt: string;
  summary: {
    notificationsCreated: number;
    deliveriesCreated: number;
    pending: number;
    processing: number;
    retryableFailed: number;
    deadLetter: number;
    staleProcessing: number;
    oldestQueuedAt: string | null;
    sentInWindow: number;
    deadLetterInWindow: number;
    successRate: number;
    failureRate: number;
    retryableAttempts: number;
    permanentAttempts: number;
    staleRecoveries: number;
  };
  events: Array<{
    eventType: string;
    notificationCount: number;
    deliveryCount: number;
  }>;
  recentDeadLetters: Array<{
    deliveryId: string;
    notificationId: string;
    eventType: string;
    attemptCount: number;
    deliveryCycle: number;
    errorCode: string | null;
    updatedAt: string;
  }>;
};

export type UpdatePlatformTenantInput = Pick<PlatformTenantDetail,
  'name' | 'slug' | 'description' | 'timezone' | 'approvalMode' | 'weekEndsOn' | 'submissionDeadlineDaysAfterPeriodEnd'>;

function mapTenant(row: PlatformTenantRow): PlatformTenant {
  return {
    id: row.id,
    name: row.name,
    slug: row.slug,
    rootOuName: row.root_ou_name,
    adminName: row.admin_name,
    adminEmail: row.admin_email,
    memberCount: Number(row.member_count),
    ouCount: Number(row.ou_count),
    status: row.status,
    approvalMode: row.approval_mode,
    createdAt: row.created_at
  };
}

async function rawRpc<T>(
  client: SupabaseClient,
  functionName: string,
  parameters: Record<string, unknown> = {}
): Promise<T> {
  const { data, error } = await client.rpc(functionName, parameters);
  if (error) throw new BackendError(error.message, error.details || error.message, error);
  return data as T;
}

export async function listPlatformTenants(client: SupabaseClient): Promise<PlatformTenant[]> {
  const rows = await rawRpc<PlatformTenantRow[]>(client, 'list_platform_tenants');
  return rows.map(mapTenant);
}

export async function createPlatformTenant(
  client: SupabaseClient,
  input: CreatePlatformTenantInput
): Promise<string> {
  return rawRpc<string>(client, 'create_platform_tenant', { payload: input });
}

export async function setPlatformTenantStatus(
  client: SupabaseClient,
  tenantId: string,
  status: 'active' | 'suspended' | 'closed'
): Promise<void> {
  await rawRpc<null>(client, 'set_platform_tenant_status', {
    p_tenant_id: tenantId,
    p_status: status
  });
}

export function getPlatformTenantDetail(client: SupabaseClient, tenantId: string): Promise<PlatformTenantDetail> {
  return rawRpc<PlatformTenantDetail>(client, 'get_platform_tenant_detail', { p_tenant_id: tenantId });
}

export async function updatePlatformTenant(client: SupabaseClient, tenantId: string, input: UpdatePlatformTenantInput): Promise<void> {
  await rawRpc<null>(client, 'update_platform_tenant', { p_tenant_id: tenantId, payload: input });
}

type InvitationRow = {
  id: string; email: string | null; display_name: string | null; permission: string;
  status: PlatformTenantInvitation['status']; expires_at: string; accepted_at: string | null;
  revoked_at: string | null; created_at: string;
};

export async function listPlatformTenantInvitations(client: SupabaseClient, tenantId: string): Promise<PlatformTenantInvitation[]> {
  const rows = await rawRpc<InvitationRow[]>(client, 'list_platform_tenant_invitations', { p_tenant_id: tenantId });
  return rows.map((row) => ({ id: row.id, email: row.email, displayName: row.display_name, permission: row.permission,
    status: row.status, expiresAt: row.expires_at, acceptedAt: row.accepted_at, revokedAt: row.revoked_at, createdAt: row.created_at }));
}

export async function revokePlatformTenantInvitation(client: SupabaseClient, tenantId: string, invitationId: string): Promise<void> {
  await rawRpc<null>(client, 'revoke_platform_tenant_invitation', { p_tenant_id: tenantId, p_invitation_id: invitationId });
}

type ActivityRow = {
  id: string; action: string; entity_type: string; entity_id: string | null; actor_name: string;
  before_data: Record<string, unknown> | null; after_data: Record<string, unknown> | null;
  metadata: Record<string, unknown>; created_at: string;
};

export async function listPlatformTenantActivity(client: SupabaseClient, tenantId: string): Promise<PlatformTenantActivity[]> {
  const rows = await rawRpc<ActivityRow[]>(client, 'list_platform_tenant_activity', { p_tenant_id: tenantId, p_limit: 50 });
  return rows.map((row) => ({ id: row.id, action: row.action, entityType: row.entity_type, entityId: row.entity_id,
    actorName: row.actor_name, beforeData: row.before_data, afterData: row.after_data, metadata: row.metadata, createdAt: row.created_at }));
}

export function createPlatformAdminInviteLink(
  client: SupabaseClient,
  tenantId: string,
  expiresInDays = 7
): Promise<PlatformAdminInvite> {
  return rawRpc<PlatformAdminInvite>(client, 'create_platform_admin_invite_link', {
    p_tenant_id: tenantId,
    p_expires_in_days: expiresInDays
  });
}

export function getPlatformNotificationOperations(
  client: SupabaseClient,
  tenantId: string,
  windowHours = 24
): Promise<PlatformNotificationOperations> {
  return rawRpc<PlatformNotificationOperations>(client, 'get_platform_notification_operations', {
    p_tenant_id: tenantId,
    p_window_hours: windowHours
  });
}
