import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';

export type OrganizationTreeNode = {
  id: string;
  parentId: string | null;
  code: string;
  name: string;
  description: string | null;
  ouTypeId: string;
  ouTypeName: string;
  level: number;
  path: string;
  sortOrder: number;
  allowDataEntry: boolean;
  children: OrganizationTreeNode[];
};

export type OrganizationMember = {
  assignmentId: string;
  ouId: string;
  churchMemberId: string;
  accountId: string;
  displayName: string;
  lineUserId: string;
  email: string | null;
  role: 'admin' | 'manager' | 'data_entry' | 'approver' | 'viewer';
  canOverride: boolean;
  assignedAt: string;
  canEdit: boolean;
  canRemove: boolean;
};

export type OuMembersResult = {
  items: OrganizationMember[];
  assignableRoles: OrganizationMember['role'][];
  canGrantOverride: boolean;
};

export type AssignableMember = {
  churchMemberId: string;
  accountId: string;
  displayName: string;
  lineUserId: string;
  email: string | null;
  existingRoles: OrganizationMember['role'][];
};

export function getAccessibleOuTree(client: SupabaseClient) {
  return callRpc<{ items: OrganizationTreeNode[] }>(client, 'get_accessible_ou_tree');
}

export function getOuMembers(client: SupabaseClient, ouId: string) {
  return callRpc<OuMembersResult>(client, 'get_ou_members', {
    p_ou_id: ouId
  });
}

export function updateOuMemberAssignment(
  client: SupabaseClient,
  payload: {
    assignmentId: string;
    permission: OrganizationMember['role'];
    canOverride: boolean;
  }
) {
  return callRpc<{ assignmentId: string; changed: boolean }>(
    client,
    'update_ou_member_assignment',
    { p_payload: payload }
  );
}

export function removeOuMember(
  client: SupabaseClient,
  payload: { assignmentId: string; reason: string }
) {
  return callRpc<{ assignmentId: string }>(client, 'remove_ou_member', {
    p_payload: payload
  });
}

export function searchAssignableMembers(
  client: SupabaseClient,
  ouId: string,
  query = ''
) {
  return callRpc<{ items: AssignableMember[] }>(client, 'search_assignable_members', {
    p_ou_id: ouId,
    p_query: query
  });
}

export function assignOuMember(
  client: SupabaseClient,
  payload: {
    ouId: string;
    churchMemberId: string;
    permission: OrganizationMember['role'];
    canOverride: boolean;
  }
) {
  return callRpc<{ assignmentId: string }>(client, 'assign_ou_member', {
    p_payload: payload
  });
}

export function createOrganizationUnit(client: SupabaseClient, payload: Record<string, unknown>) {
  return callRpc<{ ouId: string }>(client, 'create_organization_unit', { p_payload: payload });
}

export function updateOrganizationUnit(client: SupabaseClient, payload: Record<string, unknown>) {
  return callRpc<{ ouId: string }>(client, 'update_organization_unit', { p_payload: payload });
}

export function softDeleteOrganizationUnit(client: SupabaseClient, payload: Record<string, unknown>) {
  return callRpc<{ ouId: string }>(client, 'soft_delete_organization_unit', { p_payload: payload });
}
