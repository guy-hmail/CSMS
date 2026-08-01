import type { SupabaseClient } from '@supabase/supabase-js';

export type TenantSummary = {
  tenant_id: string;
  slug: string;
  name: string;
  status: string;
  membership_status: string;
  is_current: boolean;
  is_last_active: boolean;
};

export type MyProfile = {
  user: {
    id: string;
    displayName: string;
    pictureUrl: string | null;
    globalRole: 'system_admin' | 'user';
  };
  currentTenant: {
    id: string;
    slug: string;
    name: string;
    status: string;
  } | null;
  permissions: {
    ouId: string;
    ouName: string;
    permission: 'admin' | 'manager' | 'data_entry' | 'approver' | 'viewer';
    canOverride: boolean;
  }[];
};

export type MyPreferences = {
  defaultOuId: string | null;
  language: 'th' | 'en';
  landingPage: '/app/dashboard' | '/app/organization' | '/app/submissions' | '/app/reports';
  notifyMissing: boolean;
  notifySubmitted: boolean;
  notifyApproval: boolean;
  notifyEmail: boolean;
  updatedAt: string | null;
};

export type MyProfileDetails = {
  userId: string;
  displayName: string;
  email: string | null;
  phone: string | null;
};

export async function listMyTenants(client: SupabaseClient): Promise<TenantSummary[]> {
  const { data, error } = await client.rpc('list_my_tenants');
  if (error) throw error;
  return (data ?? []) as TenantSummary[];
}

export async function getMyProfile(client: SupabaseClient): Promise<MyProfile> {
  const { data, error } = await client.rpc('get_my_profile');
  if (error) throw error;
  return data as MyProfile;
}

function unwrapRpc<T>(data: unknown): T {
  const response = data as { success?: boolean; data?: T } | null;
  if (!response?.success || !response.data) throw new Error('INVALID_RPC_RESPONSE');
  return response.data;
}

export async function getMyPreferences(client: SupabaseClient): Promise<MyPreferences> {
  const { data, error } = await client.rpc('get_my_preferences');
  if (error) throw error;
  return unwrapRpc<MyPreferences>(data);
}

export async function updateMyPreferences(client: SupabaseClient, payload: Omit<MyPreferences, 'updatedAt'>): Promise<MyPreferences> {
  const { data, error } = await client.rpc('update_my_preferences', { p_payload: payload });
  if (error) throw error;
  return unwrapRpc<MyPreferences>(data);
}

export async function updateMyProfile(
  client: SupabaseClient,
  payload: { displayName: string; email: string; phone: string }
): Promise<MyProfileDetails> {
  const { data, error } = await client.rpc('update_my_profile', { p_payload: payload });
  if (error) throw error;
  return unwrapRpc<MyProfileDetails>(data);
}
