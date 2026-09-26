/**
 * Pinned model slug match (ADR §7.1.3): exact slug or slug plus dated snapshot suffix.
 */
export function modelSlugMatches(
  actual: string,
  expectedSlug: string,
): boolean {
  if (actual === expectedSlug) return true;
  const suffix = /^(.+)-(\d{8})$/.exec(actual);
  if (!suffix) return false;
  return suffix[1] === expectedSlug;
}
