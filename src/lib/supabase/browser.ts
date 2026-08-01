import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import { env } from '$env/dynamic/public';

let browserClient: SupabaseClient | undefined;

function browserSupabaseUrl(configuredUrl: string): string {
  if (
    typeof window !== 'undefined' &&
    window.location.protocol === 'https:' &&
    window.location.hostname === 'localhost' &&
    configuredUrl.startsWith('http://127.0.0.1:')
  ) {
    return `${window.location.origin}/supabase`;
  }
  return configuredUrl;
}

export function isSupabaseConfigured(): boolean {
  return Boolean(env.PUBLIC_SUPABASE_URL && env.PUBLIC_SUPABASE_ANON_KEY);
}

export function getSupabaseBrowserClient(): SupabaseClient {
  const url = env.PUBLIC_SUPABASE_URL;
  const key = env.PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) {
    throw new Error('Supabase public environment variables are not configured.');
  }
  browserClient ??= createBrowserClient(browserSupabaseUrl(url), key);
  return browserClient;
}
