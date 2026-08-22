const LINE_OA_BASIC_ID_PATTERN = /^@[A-Za-z0-9._-]{3,50}$/;

export function normalizeLineOaBasicId(value: string | null | undefined): string {
  const input = value?.trim() ?? '';
  if (!input || input.startsWith('replace-with-')) return '';
  return input.startsWith('@') ? input : `@${input}`;
}

export function buildLineOaAddFriendUrl(value: string | null | undefined): URL | null {
  const basicId = normalizeLineOaBasicId(value);
  if (!LINE_OA_BASIC_ID_PATTERN.test(basicId)) return null;
  return new URL(`https://line.me/R/ti/p/${encodeURIComponent(basicId)}`);
}
