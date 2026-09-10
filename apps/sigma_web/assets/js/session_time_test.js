import { describe, expect, test } from "bun:test"
import { formatElapsedTime, formatRelativeTime } from "./session_time.js"

describe("session time formatting", () => {
  const now = 2_000_000

  test("formats relative start time at stable units", () => {
    expect(formatRelativeTime(now - 8_000, now)).toBe("started 8s ago")
    expect(formatRelativeTime(now - 125_000, now)).toBe("started 2m ago")
    expect(formatRelativeTime(now - 7_200_000, now)).toBe("started 2h ago")
    expect(formatRelativeTime(now - 172_800_000, now)).toBe("started 2d ago")
  })

  test("formats active request elapsed time", () => {
    expect(formatElapsedTime(now - 8_000, now)).toBe("running 8s")
    expect(formatElapsedTime(now - 125_000, now)).toBe("running 2m 5s")
    expect(formatElapsedTime(now - 7_500_000, now)).toBe("running 2h 5m")
  })

  test("keeps invalid timestamps explicit", () => {
    expect(formatRelativeTime("not-a-time", now)).toBe("started: unknown")
    expect(formatElapsedTime(undefined, now)).toBe("running")
  })
})
