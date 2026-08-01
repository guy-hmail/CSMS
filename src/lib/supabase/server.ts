import { createServerClient, type CookieOptions } from '@supabase/ssr';
import type { Cookies } from '@sveltejs/kit';
import { env } from '$env/dynamic/public';

export function isSupabaseServerConfigured(): boolean {
  return Boolean(env.PUBLIC_SUPABASE_URL && env.PUBLIC_SUPABASE_ANON_KEY);
}

export function getSupabaseServerClient(cookies: Cookies) {
  const url = env.PUBLIC_SUPABASE_URL;
  const key = env.PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) {
    throw new Error('Supabase public environment variables are not configured.');
  }
  return createServerClient(url, key, {
    cookies: {
      getAll: () => cookies.getAll(),
      setAll: (items: { name: string; value: string; options: CookieOptions }[]) => {
        for (const { name, value, options } of items) {
          cookies.set(name, value, { ...options, path: '/' });
        }
      }
    }
  });
}
