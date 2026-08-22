const allowedNotificationRoutes = [
  '/app/approval',
  '/app/dashboard',
  '/app/organization',
  '/app/reports',
  '/app/settings',
  '/app/submissions'
] as const;

export function safeNotificationDeepLink(value: string | null | undefined): string | null {
  const candidate = value?.trim();
  if (!candidate || !candidate.startsWith('/app/') || candidate.startsWith('//') || candidate.includes('://')) {
    return null;
  }

  let parsed: URL;
  try {
    parsed = new URL(candidate, 'https://csms.invalid');
  } catch {
    return null;
  }

  if (parsed.origin !== 'https://csms.invalid' || parsed.username || parsed.password) return null;
  return allowedNotificationRoutes.some(
    (route) => parsed.pathname === route || parsed.pathname.startsWith(`${route}/`)
  )
    ? `${parsed.pathname}${parsed.search}${parsed.hash}`
    : null;
}
