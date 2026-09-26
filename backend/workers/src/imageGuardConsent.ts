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

/** Calendar date in the string must be real (no 2026-02-31 rollover). Years before 0001 are rejected (fail-closed; aligns with ISO 8601 / proleptic Gregorian usage). */
export function rfc3339CalendarDateValid(year: number, month: number, day: number): boolean {
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  const probe = new Date(0);
  probe.setUTCFullYear(year, month - 1, day);
  return (
    probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day
  );
}

export function rfc3339TimeComponentsValid(hour: number, minute: number, second: number): boolean {
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 && second >= 0 && second <= 60;
}

export function rfc3339NumericOffsetValid(offset: string): boolean {
  if (offset.length !== 6 || (offset[0] !== '+' && offset[0] !== '-')) return false;
  if (offset[3] !== ':') return false;
  const hour = Number(offset.slice(1, 3));
  const minute = Number(offset.slice(4, 6));
  return Number.isInteger(hour) && Number.isInteger(minute) && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

export function isAllowedWardrobeImagesAcceptedAtRfc3339(value: string): boolean {
  if (value.length === 0 || value.length > WARDROBE_IMAGES_ACCEPTED_AT_MAX_LENGTH) return false;
  if (consentTimestampHasControlCharacter(value)) return false;
  const match = WARDROBE_IMAGES_ACCEPTED_AT_RFC3339.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (!rfc3339CalendarDateValid(year, month, day)) return false;
  if (!rfc3339TimeComponentsValid(hour, minute, second)) return false;
  const offset = match[8];
  if (offset === 'Z') return true;
  return rfc3339NumericOffsetValid(offset);
}

export function isAllowedWardrobeImagesAcceptedAtValue(value: unknown): boolean {
  if (typeof value !== 'string') return false;
  return isAllowedWardrobeImagesAcceptedAtRfc3339(value);
}
