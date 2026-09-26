/**
 * Shared RFC 3339 consent timestamp rule (#36). Used by the Worker, Swift mirror,
 * and evaluated via fixtures/image-guard/corpus.json (Worker vitest).
 */
export const WARDROBE_IMAGES_ACCEPTED_AT_RFC3339 =
  /^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$/;

export const WARDROBE_IMAGES_ACCEPTED_AT_MAX_LENGTH = 64;

/** Longest values matching {@link WARDROBE_IMAGES_ACCEPTED_AT_RFC3339} are ~35 chars; 64-char valid timestamps are not buildable under this rule. */

export function consentTimestampHasControlCharacter(value: string): boolean {
  for (const char of value) {
    const code = char.codePointAt(0)!;
    if (code <= 0x1f || code === 0x7f || code === 0x2028 || code === 0x2029) return true;
  }
  return false;
}

/** Calendar date in the string must be real (no 2026-02-31 rollover). */
export function rfc3339CalendarDateValid(year: number, month: number, day: number): boolean {
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const probe = new Date(0);
  probe.setUTCFullYear(year, month - 1, day);
  return (
    probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day
  );
}

export function isAllowedWardrobeImagesAcceptedAtRfc3339(value: string): boolean {
  if (value.length === 0 || value.length > WARDROBE_IMAGES_ACCEPTED_AT_MAX_LENGTH) return false;
  if (consentTimestampHasControlCharacter(value)) return false;
  const match = WARDROBE_IMAGES_ACCEPTED_AT_RFC3339.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  return rfc3339CalendarDateValid(year, month, day);
}

export function isAllowedWardrobeImagesAcceptedAtValue(value: unknown): boolean {
  if (typeof value !== 'string') return false;
  return isAllowedWardrobeImagesAcceptedAtRfc3339(value);
}
