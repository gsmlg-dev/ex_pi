const ACCEPTED_STATUSES = new Set([
  "accepted",
  "queued_as_steering",
  "queued_as_follow_up"
])

export function shouldClearComposer(reply) {
  return ACCEPTED_STATUSES.has(reply?.status)
}
