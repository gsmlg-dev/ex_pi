function elapsedParts(timestamp, now) {
  const parsed = Number(timestamp)

  if (!Number.isFinite(parsed)) return null

  const seconds = Math.max(0, Math.floor((now - parsed) / 1000))
  const minutes = Math.floor(seconds / 60)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)

  return { seconds, minutes, hours, days }
}

export function formatRelativeTime(timestamp, now = Date.now()) {
  const elapsed = elapsedParts(timestamp, now)

  if (!elapsed) return "started: unknown"
  if (elapsed.seconds < 60) return `started ${elapsed.seconds}s ago`
  if (elapsed.minutes < 60) return `started ${elapsed.minutes}m ago`
  if (elapsed.hours < 24) return `started ${elapsed.hours}h ago`
  return `started ${elapsed.days}d ago`
}

export function formatElapsedTime(timestamp, now = Date.now()) {
  const elapsed = elapsedParts(timestamp, now)

  if (!elapsed) return "running"
  if (elapsed.seconds < 60) return `running ${elapsed.seconds}s`
  if (elapsed.minutes < 60) return `running ${elapsed.minutes}m ${elapsed.seconds % 60}s`
  return `running ${elapsed.hours}h ${elapsed.minutes % 60}m`
}
