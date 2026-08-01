import { browser } from '$app/environment';
import { get, writable, type Writable } from 'svelte/store';
import {
  getMyProfile,
  getMyPreferences,
  listMyTenants,
  type MyProfile,
  type MyPreferences,
  type TenantSummary
} from '$lib/api/identityApi';
import { switchLineTenant } from '$lib/auth/lineAuth';
import { getSupabaseBrowserClient } from '$lib/supabase/browser';

export type TenantContextState = {
  status: 'idle' | 'loading' | 'ready' | 'error';
  activeTenant: TenantSummary | null;
  tenants: TenantSummary[];
  permissions: MyProfile['permissions'];
  userName: string;
  preferences: MyPreferences | null;
  error: string;
};

const initialState: TenantContextState = {
  status: 'idle',
  activeTenant: null,
  tenants: [],
  permissions: [],
  userName: '',
  preferences: null,
  error: ''
};

type TenantContextBrowserGlobal = typeof globalThis & {
  __csmsTenantContext?: Writable<TenantContextState>;
};

const browserGlobal = globalThis as TenantContextBrowserGlobal;

// Keep one store instance across Vite HMR updates. Without this, the shell can
// retain the old store while a newly updated route subscribes to a fresh one.
export const tenantContext = browser
  ? (browserGlobal.__csmsTenantContext ??= writable<TenantContextState>(initialState))
  : writable<TenantContextState>(initialState);

let initialization: Promise<TenantContextState> | null = null;

function readableError(error: unknown): string {
  const message = error instanceof Error ? error.message : 'ไม่สามารถโหลด Tenant context ได้';
  if (message.includes('AUTH_REQUIRED') || message.includes('JWT')) {
    return 'Session หมดอายุ กรุณาเข้าสู่ระบบด้วย LINE อีกครั้ง';
  }
  return message;
}

export function initializeTenantContext(force = false): Promise<TenantContextState> {
  if (initialization && !force) return initialization;
  if (!force) {
    const currentState = get(tenantContext);
    if (currentState.status === 'ready') return Promise.resolve(currentState);
  }

  initialization = (async () => {
    tenantContext.update((state) => ({ ...state, status: 'loading', error: '' }));
    try {
      const client = getSupabaseBrowserClient();
      const { data, error } = await client.auth.getSession();
      if (error) throw error;
      if (!data.session?.user) throw new Error('AUTH_REQUIRED');

      let tenants = await listMyTenants(client);
      let activeTenant = tenants.find((tenant) => tenant.is_current) ?? null;

      if (!activeTenant) {
        const restoreTarget =
          tenants.find((tenant) => tenant.is_last_active) ??
          (tenants.length === 1 ? tenants[0] : null);
        if (restoreTarget) {
          await switchLineTenant(client, restoreTarget.tenant_id);
          tenants = await listMyTenants(client);
          activeTenant =
            tenants.find((tenant) => tenant.is_current) ??
            tenants.find((tenant) => tenant.tenant_id === restoreTarget.tenant_id) ??
            null;
        }
      }

      if (!activeTenant) {
        throw new Error(
          tenants.length > 1
            ? 'กรุณากลับไปหน้า Login เพื่อเลือก Tenant'
            : 'บัญชีนี้ยังไม่มี Tenant ที่เปิดใช้งาน'
        );
      }

      const [profile, preferences] = await Promise.all([getMyProfile(client), getMyPreferences(client)]);
      if (profile.currentTenant?.id !== activeTenant.tenant_id) {
        throw new Error('TENANT_CONTEXT_MISMATCH');
      }
      const userName =
        profile.user.displayName ||
        (data.session.user.user_metadata?.display_name as string | undefined) ||
        (data.session.user.user_metadata?.name as string | undefined) ||
        data.session.user.email ||
        'LINE User';
      const readyState: TenantContextState = {
        status: 'ready',
        activeTenant,
        tenants,
        permissions: profile.permissions,
        userName,
        preferences,
        error: ''
      };
      tenantContext.set(readyState);
      return readyState;
    } catch (error) {
      const failedState: TenantContextState = {
        ...initialState,
        status: 'error',
        error: readableError(error)
      };
      tenantContext.set(failedState);
      throw error;
    } finally {
      initialization = null;
    }
  })();

  return initialization;
}

export async function selectActiveTenant(tenantId: string): Promise<void> {
  tenantContext.update((state) => ({ ...state, status: 'loading', error: '' }));
  try {
    await switchLineTenant(getSupabaseBrowserClient(), tenantId);
    await initializeTenantContext(true);
  } catch (error) {
    tenantContext.update((state) => ({
      ...state,
      status: 'error',
      error: readableError(error)
    }));
    throw error;
  }
}

export function clearTenantContext(): void {
  initialization = null;
  tenantContext.set(initialState);
}
