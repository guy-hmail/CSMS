import type { Liff } from '@line/liff';
import type { SupabaseClient } from '@supabase/supabase-js';
import { env } from '$env/dynamic/public';
import { extractRuntimeLiffId, normalizeLiffId } from './liffConfig';

export type LineTenantOption = {
  tenantId: string;
  slug: string;
  name: string;
};

export type LineSessionResult = {
  activeTenantId: string | null;
  requiresTenantSelection: boolean;
  tenants: LineTenantOption[];
};

type LineAuthResponse = {
  success: boolean;
  data?: {
    tokenHash: string;
    verificationType: 'email';
    activeTenantId: string | null;
    requiresTenantSelection: boolean;
    tenants: LineTenantOption[];
  };
  error?: {
    code?: string;
    message?: string;
  };
};

let liffInstance: Liff | undefined;

export async function initializeLiff(): Promise<Liff> {
  const liffId = typeof window === 'undefined'
    ? normalizeLiffId(env.PUBLIC_LINE_LIFF_ID)
    : extractRuntimeLiffId(window.location.search) || normalizeLiffId(env.PUBLIC_LINE_LIFF_ID);
  if (!liffId || liffId === 'replace-with-line-liff-id') {
    throw new Error('ยังไม่ได้ตั้งค่า PUBLIC_LINE_LIFF_ID');
  }
  if (!liffInstance) {
    const module = await import('@line/liff');
    liffInstance = module.default;
    await liffInstance.init({ liffId });
  }
  return liffInstance;
}

async function functionErrorMessage(error: unknown): Promise<string> {
  if (
    error &&
    typeof error === 'object' &&
    'context' in error &&
    (error as { context?: unknown }).context instanceof Response
  ) {
    const response = (error as { context: Response }).context;
    const body = (await response.clone().json().catch(() => null)) as LineAuthResponse | null;
    const code = body?.error?.code;
    const message = body?.error?.message;
    if (code && message) return `${code}: ${message}`;
    return code || message || `LINE authentication failed (${response.status})`;
  }
  return error instanceof Error ? error.message : 'LINE authentication failed';
}

export async function exchangeLineSession(
  client: SupabaseClient,
  liff: Liff,
  inviteToken?: string
): Promise<LineSessionResult> {
  const idToken = liff.getIDToken();
  if (!idToken) throw new Error('LINE ไม่ได้ส่ง ID token กรุณาตรวจ scope openid');

  const { data, error } = await client.functions.invoke<LineAuthResponse>('line-auth', {
    body: { idToken, inviteToken }
  });
  if (error) throw new Error(await functionErrorMessage(error));
  if (!data?.success || !data.data?.tokenHash) {
    throw new Error(data?.error?.message || data?.error?.code || 'ผลตอบกลับจาก line-auth ไม่ถูกต้อง');
  }

  const { error: verifyError } = await client.auth.verifyOtp({
    token_hash: data.data.tokenHash,
    type: data.data.verificationType
  });
  if (verifyError) throw verifyError;

  return {
    activeTenantId: data.data.activeTenantId,
    requiresTenantSelection: data.data.requiresTenantSelection,
    tenants: data.data.tenants
  };
}

export async function switchLineTenant(
  client: SupabaseClient,
  tenantId: string
): Promise<void> {
  const { data, error } = await client.functions.invoke('switch-active-tenant', {
    body: { tenantId }
  });
  if (error) throw new Error(await functionErrorMessage(error));
  if (!(data as { success?: boolean } | null)?.success) {
    throw new Error('ไม่สามารถเลือก Tenant ได้');
  }
  const { error: refreshError } = await client.auth.refreshSession();
  if (refreshError) throw refreshError;
}
