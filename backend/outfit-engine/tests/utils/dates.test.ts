import { describe, expect, it } from "vitest";
import { parseCalendarDay, daysBetween } from "../../src/utils/dates.js";

describe("Date utilities (fix #39)", () => {
  describe("parseCalendarDay", () => {
    it("parses local calendar dates (YYYY-MM-DD)", () => {
      const result = parseCalendarDay("2026-09-19");
      expect(result).not.toBeNull();
      expect(result).toBe(Date.UTC(2026, 8, 19)); // month is 0-indexed
    });

    it("extracts date portion from ISO timestamp without UTC conversion", () => {
      // Evening in California: 2026-09-19T23:30:00-07:00
      // Should be treated as 2026-09-19, NOT 2026-09-20
      const result = parseCalendarDay("2026-09-19T23:30:00-07:00");
      expect(result).toBe(Date.UTC(2026, 8, 19));
    });

    it("extracts date portion from UTC timestamp", () => {
      const result = parseCalendarDay("2026-09-19T12:00:00Z");
      expect(result).toBe(Date.UTC(2026, 8, 19));
    });

    it("handles midnight timestamps", () => {
      const result = parseCalendarDay("2026-09-19T00:00:00Z");
      expect(result).toBe(Date.UTC(2026, 8, 19));
    });

    it("returns null for invalid date strings", () => {
      expect(parseCalendarDay("yesterday")).toBeNull();
      expect(parseCalendarDay("not-a-date")).toBeNull();
      expect(parseCalendarDay("2026-13-01")).toBeNull(); // invalid month
      expect(parseCalendarDay("2026-02-31")).toBeNull(); // invalid day
      expect(parseCalendarDay("")).toBeNull();
    });

    it("returns null for null/undefined inputs", () => {
      expect(parseCalendarDay(null as any)).toBeNull();
      expect(parseCalendarDay(undefined as any)).toBeNull();
    });

    it("returns null for malformed dates", () => {
      expect(parseCalendarDay("2026/09/19")).toBeNull(); // wrong separator
      expect(parseCalendarDay("19-09-2026")).toBeNull(); // wrong order
      expect(parseCalendarDay("2026-9-19")).toBeNull(); // missing leading zero
    });
  });

  describe("daysBetween", () => {
    it("calculates days between calendar dates", () => {
      expect(daysBetween("2026-09-19", "2026-09-15")).toBe(4);
      expect(daysBetween("2026-09-19", "2026-09-19")).toBe(0);
    });

    it("handles timestamps without UTC conversion issues", () => {
      // Same day in different timezones should be 0 days apart
      expect(
        daysBetween("2026-09-19T23:30:00-07:00", "2026-09-19T01:00:00+01:00")
      ).toBe(0);
    });

    it("correctly calculates across local midnight in California", () => {
      // PRD scenario: garment worn today, checked same evening in California
      // 2026-09-19T23:30:00-07:00 and lastWornOn "2026-09-19" should be 0 days
      expect(daysBetween("2026-09-19T23:30:00-07:00", "2026-09-19")).toBe(0);
      
      // Should not be treated as yesterday (which would give 1 day)
      expect(daysBetween("2026-09-19T23:30:00-07:00", "2026-09-18")).toBe(1);
    });

    it("returns non-negative values only", () => {
      // Earlier date as first arg should clamp to 0
      expect(daysBetween("2026-09-15", "2026-09-19")).toBe(0);
    });

    it("returns null when either date is invalid", () => {
      expect(daysBetween("yesterday", "2026-09-19")).toBeNull();
      expect(daysBetween("2026-09-19", "invalid")).toBeNull();
      expect(daysBetween("not-a-date", "also-not-a-date")).toBeNull();
    });

    it("handles long time spans", () => {
      expect(daysBetween("2026-09-19", "2025-09-19")).toBe(365);
      expect(daysBetween("2027-01-01", "2026-01-01")).toBe(365);
    });
  });

  describe("NaN prevention", () => {
    it("invalid dates never produce NaN in scoring chain", () => {
      const result1 = parseCalendarDay("yesterday");
      expect(result1).toBeNull();
      expect(Number.isNaN(result1 as any)).toBe(false);

      const result2 = daysBetween("2026-09-19", "yesterday");
      expect(result2).toBeNull();
      expect(Number.isNaN(result2 as any)).toBe(false);
    });
  });
});
