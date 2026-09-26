/** Null-prototype record for provider-controlled string keys. */
export type OwnStringKeyRecord<T> = Record<string, T>;

export function createOwnRecord<T>(): OwnStringKeyRecord<T> {
  return Object.create(null) as OwnStringKeyRecord<T>;
}

export function ownKeys(record: OwnStringKeyRecord<unknown>): string[] {
  return Object.keys(record);
}

export function ownHas(
  record: OwnStringKeyRecord<unknown> | Record<string, unknown>,
  key: string,
): boolean {
  return Object.hasOwn(record, key);
}

export function ownGetString(
  record: OwnStringKeyRecord<string> | Record<string, string>,
  key: string,
): string | undefined {
  if (!Object.hasOwn(record, key)) return undefined;
  const v = record[key];
  return typeof v === "string" ? v : undefined;
}

const RESERVED_MAP_KEYS = new Set(["__proto__", "constructor", "prototype"]);

function isPlainTokenMapObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const proto = Object.getPrototypeOf(value);
  return proto === null || proto === Object.prototype;
}

/** Every own key must map to a non-empty string (garment UUID). */
export function isOwnStringToStringMap(
  record: Record<string, unknown>,
): record is OwnStringKeyRecord<string> {
  if (!isPlainTokenMapObject(record)) return false;
  for (const key of Object.keys(record)) {
    if (!Object.hasOwn(record, key)) continue;
    if (RESERVED_MAP_KEYS.has(key)) return false;
    const v = record[key];
    if (typeof v !== "string" || v.length === 0) return false;
  }
  return true;
}
