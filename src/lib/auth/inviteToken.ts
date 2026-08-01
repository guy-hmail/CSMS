function inviteFromParameters(value: string): string {
  const queryStart = value.indexOf('?');
  const query = queryStart >= 0 ? value.slice(queryStart + 1) : value.replace(/^#?\/?/, '');
  return new URLSearchParams(query).get('invite')?.trim() ?? '';
}

/**
 * LINE redirects a LIFF deep link to the endpoint URL using `liff.state`.
 * Accept both that shape and a direct `?invite=` URL used during local tests.
 */
export function extractInviteToken(search: string): string {
  const parameters = new URLSearchParams(search.replace(/^\?/, ''));
  const directToken = parameters.get('invite')?.trim();
  if (directToken) return directToken;

  let state = parameters.get('liff.state')?.trim() ?? '';
  for (let attempt = 0; state && attempt < 3; attempt += 1) {
    const token = inviteFromParameters(state);
    if (token) return token;

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
