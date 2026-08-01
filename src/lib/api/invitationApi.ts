import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';

export type InviteRole = 'admin' | 'manager' | 'data_entry' | 'approver' | 'viewer';

export type CreateOuInviteLinkInput = {
  targetOuId: string;
  permission: InviteRole;
  canOverride: boolean;
  expiresInDays: number;
  displayName?: string;
};

export type CreatedOuInvite = {
  invitationId: string;
  inviteToken: string;
  expiresAt: string;
};

export type OuInvitation = {
  invitationId: string;
  displayName: string | null;
  permission: InviteRole;
  canOverride: boolean;
  status: 'pending' | 'accepted' | 'expired' | 'revoked';
  expiresAt: string;
  acceptedAt: string | null;
  createdAt: string;
};

export function createOuInviteLink(
  client: SupabaseClient,
  payload: CreateOuInviteLinkInput
) {
  return callRpc<CreatedOuInvite>(client, 'create_ou_invite_link', {
    p_payload: payload
  });
}

export function listOuInvitations(client: SupabaseClient, ouId: string) {
  return callRpc<{ items: OuInvitation[] }>(client, 'list_ou_invitations', {
    p_ou_id: ouId
  });
}

export function revokeOuInvitation(
  client: SupabaseClient,
  payload: { invitationId: string; reason: string }
) {
  return callRpc<{ invitationId: string }>(client, 'revoke_ou_invitation', {
    p_payload: payload
  });
}

export function reissueOuInvitation(
  client: SupabaseClient,
  payload: { invitationId: string; expiresInDays: number }
) {
  return callRpc<CreatedOuInvite>(client, 'reissue_ou_invitation', {
    p_payload: payload
  });
}
