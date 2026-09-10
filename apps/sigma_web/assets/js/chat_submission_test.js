import { describe, expect, test } from "bun:test"

import { shouldClearComposer } from "./chat_submission.js"

describe("shouldClearComposer", () => {
  test("clears only after the runtime accepts or queues the prompt", () => {
    expect(shouldClearComposer({ status: "accepted" })).toBe(true)
    expect(shouldClearComposer({ status: "queued_as_steering" })).toBe(true)
    expect(shouldClearComposer({ status: "queued_as_follow_up" })).toBe(true)
  })

  test("preserves the draft when the server rejects the operation", () => {
    expect(shouldClearComposer({ status: "rejected" })).toBe(false)
    expect(shouldClearComposer({ status: "busy" })).toBe(false)
    expect(shouldClearComposer(undefined)).toBe(false)
  })
})
