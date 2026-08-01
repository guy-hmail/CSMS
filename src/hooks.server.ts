import type { Handle } from '@sveltejs/kit';
import { getSupabaseServerClient, isSupabaseServerConfigured } from '$lib/supabase/server';

export const handle: Handle = async ({ event, resolve }) => {
  if (isSupabaseServerConfigured()) {
    event.locals.supabase = getSupabaseServerClient(event.cookies);
    const { data } = await event.locals.supabase.auth.getUser();
    event.locals.user = data.user;
  }
  return resolve(event);
};
