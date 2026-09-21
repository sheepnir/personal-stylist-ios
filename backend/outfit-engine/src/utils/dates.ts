/**
 * Shared date utilities for deterministic day arithmetic.
 * 
 * All functions treat dates as local calendar dates (YYYY-MM-DD) without
 * timezone conversion. Invalid dates are handled gracefully, never producing NaN.
 */

/**
 * Parse a date string to a calendar day timestamp.
 * 
 * Accepts:
 * - Local calendar dates: "YYYY-MM-DD"
 * - ISO 8601 timestamps: extracts the date portion without UTC conversion
 * 
 * For ISO timestamps, we extract the date portion directly from the string
 * to avoid UTC conversion issues. This ensures "2026-09-19T23:30:00-07:00"
 * is treated as day 2026-09-19, not 2026-09-20.
 * 
 * @returns milliseconds since epoch for the date at 00:00:00 local time,
 *          or null if the date is invalid
 */
export function parseCalendarDay(dateString: string): number | null {
  if (!dateString || typeof dateString !== "string") return null;

  // Extract YYYY-MM-DD portion
  let datePart: string;
  if (dateString.includes("T")) {
    // ISO timestamp: extract date portion before 'T'
    datePart = dateString.split("T")[0];
  } else {
    datePart = dateString;
  }

  // Validate format YYYY-MM-DD
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(datePart);
  if (!match) return null;

  const year = parseInt(match[1], 10);
  const month = parseInt(match[2], 10);
  const day = parseInt(match[3], 10);

  // Basic validation
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;

  // Use Date.UTC for consistent behavior, treating the input as local calendar date
  const timestamp = Date.UTC(year, month - 1, day);
  
  // Check for invalid date (e.g., Feb 31)
  const d = new Date(timestamp);
  if (
    d.getUTCFullYear() !== year ||
    d.getUTCMonth() !== month - 1 ||
    d.getUTCDate() !== day
  ) {
    return null;
  }

  return timestamp;
}

/**
 * Calculate days between two dates, treating both as calendar dates.
 * 
 * @param asOfDate - The later date (typically "today" or request time)
 * @param earlierDate - The earlier date (typically lastWornOn or suggestedAt)
 * @returns Number of days between dates, or null if either date is invalid.
 *          Always returns non-negative values (clamped to 0 minimum).
 */
export function daysBetween(
  asOfDate: string,
  earlierDate: string,
): number | null {
  const a = parseCalendarDay(asOfDate);
  const b = parseCalendarDay(earlierDate);

  if (a === null || b === null) return null;

  return Math.max(0, Math.floor((a - b) / 86_400_000));
}
