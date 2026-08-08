const LIFF_ID_PATTERN = /^[0-9]+-[A-Za-z0-9_-]+$/;

export function normalizeLiffId(value: string | null | undefined): string {
  const input = value?.trim() ?? '';
  if (!input) return '';
  try {
    const url = new URL(input);
    if (url.hostname === 'liff.line.me') return url.pathname.split('/').filter(Boolean)[0] ?? '';
  } catch {
    // The input is already an ID rather than a URL.
  }
  return input.replace(/^https?:\/\/liff\.line\.me\//i, '').split(/[/?#]/)[0] ?? '';
}

export function isValidLiffId(value: string): boolean {
  return value.length <= 100 && LIFF_ID_PATTERN.test(value);
}

function valueFromState(value: string, key: string): string {
  let state = value;
  for (let attempt = 0; state && attempt < 3; attempt += 1) {
    const queryStart = state.indexOf('?');
    const query = queryStart >= 0 ? state.slice(queryStart + 1) : state.replace(/^#?\/?/, '');
    const found = new URLSearchParams(query).get(key)?.trim();
    if (found) return found;
    try {
      const decoded = decodeURIComponent(state);
      if (decoded === state) break;
      state = decoded;
    } catch {
      break;
    }
  }
  return '';
}

export function extractRuntimeLiffId(search: string): string {
  const parameters = new URLSearchParams(search.replace(/^\?/, ''));
  const direct = normalizeLiffId(parameters.get('liffId'));
  if (direct && isValidLiffId(direct)) return direct;
  const fromState = normalizeLiffId(valueFromState(parameters.get('liff.state') ?? '', 'liffId'));
  return fromState && isValidLiffId(fromState) ? fromState : '';
}

export function buildLiffUrl(
  configuredId: string | null | undefined,
  route = ''
): URL | null {
  const liffId = normalizeLiffId(configuredId);
  if (!liffId || !isValidLiffId(liffId)) return null;
  const suffix = route ? `/${route.replace(/^\/+/, '')}` : '';
  const url = new URL(`https://liff.line.me/${liffId}${suffix}`);
  url.searchParams.set('liffId', liffId);
  return url;
}
