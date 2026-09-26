/**
 * Key-segment normalization for the image guard (#36).
 */

/** Substrings matched after {@link normalizeImageGuardKey}. */
export const FORBIDDEN_IMAGE_KEY_TOKENS = [
  'image',
  'imagedata',
  'imagebase64',
  'thumbnail',
  'thumb',
  'photo',
  'masterimage',
  'processedimage',
  'pixeldata',
  'bitmap',
  'imagery',
  'photography',
  'thumbsup',
] as const;

export function isDefaultIgnorableCodePoint(code: number): boolean {
  if (code === 0x00ad || code === 0x034f || code === 0x180e || code === 0xfeff) return true;
  if (code >= 0x200b && code <= 0x200f) return true;
  if (code >= 0x2060 && code <= 0x206f) return true;
  if (code >= 0xfe00 && code <= 0xfe0f) return true;
  return /\p{Cf}/u.test(String.fromCodePoint(code));
}

/** Lowercase ASCII A–Z; strip `_`, `-`, and default-ignorable code points before token match. */
export function normalizeImageGuardKey(key: string): string {
  let normalized = '';
  for (let i = 0; i < key.length; i++) {
    const code = key.charCodeAt(i);
    if (isDefaultIgnorableCodePoint(code)) continue;
    if (code >= 65 && code <= 90) normalized += String.fromCharCode(code + 32);
    else if (key[i] !== '_' && key[i] !== '-') normalized += key[i];
  }
  return normalized;
}

export function normalizedKeyContainsForbiddenImageToken(key: string): boolean {
  const normalized = normalizeImageGuardKey(key);
  return FORBIDDEN_IMAGE_KEY_TOKENS.some((token) => normalized.includes(token));
}
