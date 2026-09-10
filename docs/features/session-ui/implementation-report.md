# Session UI Observability V2 Implementation Report

Date: 2026-09-09
Base HEAD: `6d1e64f547bd71962b3aed4fb1655733c75ae2a6`
Branch: `main`

The required V2 scope in `implement-plan.md` and `prd.md` is implemented in the
current uncommitted working tree. SUI-00 through SUI-09, SUI-11, and SUI-12 are
complete. The optional SUI-10 Inspector and compaction-turn prediction remain
deferred.

## Work Order Status

| Work order | Status | Evidence |
| --- | --- | --- |
| SUI-00 | Complete | `contract.md` freezes the baseline, ownership, schemas, compatibility boundary, and fixture list. |
| SUI-01 | Complete | Versioned DTOs and the pure `Sigma.Session.Metrics` reducer cover revision replacement, scopes, coverage, and weighted throughput. |
| SUI-02 | Complete | Provider and tool boundaries emit sanitized request/tool facts with monotonic timing and normalized usage. |
| SUI-03 | Complete | Versioned operational facts round-trip through writer, JSONL replay, restart, and fork ownership without advancing the conversation leaf. |
| SUI-04 | Complete | Runtime/PublicRuntime expose bounded snapshots, cursor/watermark updates, capability negotiation, and resync. |
| SUI-05 | Complete | Runtime-owned context/policy projections, hard-budget admission, and committed/failed manual and automatic compaction are integrated. |
| SUI-06 | Complete | Message/turn/session/context components cover complete, partial, unknown, legacy, failed, and responsive states. |
| SUI-07 | Complete | `SessionLive` consumes runtime metrics and context state without recomputing cumulative usage or thresholds. |
| SUI-08 | Complete | Retry uses a persisted checkpoint; Fork and Retry have serialized admission, revision/leaf checks, and durable operation idempotency. |
| SUI-09 | Complete | Retry, Resend, Fork, conflict feedback, no-rollback warnings, and preserved alternatives are exposed in the UI. |
| SUI-10 | Deferred | Optional Inspector, detailed history, and turn prediction are not required by the V2 acceptance gate. |
| SUI-11 | Complete | Scoped, umbrella, performance, compatibility, privacy, and real-browser validation passed. |
| SUI-12 | Complete | Contract, protocol/runtime integration, usage, index, compatibility, and this completion report are updated. |

## Delivered

- Stable request, turn, message, tool, compaction, operation, and origin-session
  identity with revisioned, replayable facts.
- Canonical usage accounting that does not re-add cache/reasoning subdivisions;
  own, inherited, and active-lineage scopes remain distinct.
- Weighted provider throughput, request/turn/tool timing, explicit coverage, and
  unknown/partial/interrupted states.
- Bounded runtime snapshots, atomic attach snapshots, monotonic cursors,
  capability-gated metrics events, and explicit resync after a gap.
- Runtime-owned context estimates and compaction policy, hard-budget checks,
  metered compaction, and durable committed/failed lifecycle records.
- True checkpoint Retry, current-leaf Resend, controlled Fork, busy/conflict
  feedback, and idempotent recovery without workspace rollback claims.
- Message metrics, turn totals, desktop rail, responsive drawer, branch
  alternatives, manual Compact, accessible controls, reconnect-safe drafts, and
  non-disruptive transcript scrolling.

## Acceptance Evidence

| AC | Status | Direct evidence |
| --- | --- | --- |
| AC-01 | Pass | `metrics_test.exs` groups multiple requests/tools by turn; `session_live_test.exs` renders matching message and turn totals. |
| AC-02 | Pass | Reducer fixture proves 40k input including 30k cache plus 1k output including 400 reasoning totals 41k. |
| AC-03 | Pass | Weighted fixture proves `(10 + 1000) / (0.1 + 20) = 50.25 tok/s`. |
| AC-04 | Pass | A 30-second tool interval changes turn/tool time without changing LLM throughput. |
| AC-05 | Pass | Context/compaction tests and UI fixtures show 100k to 25k while durable request and compaction usage remain. |
| AC-06 | Pass | JSONL replay/runtime restart restore usage and committed compactions; legacy omissions remain unknown. |
| AC-07 | Pass | Fork tests preserve parent totals and provenance while child own usage starts at zero and inherited lineage remains visible. |
| AC-08 | Pass | Runtime/LiveView tests exclude the old answer and later turns from replacement context, preserve the original branch, and execute once. |
| AC-09 | Pass | Runtime performs no filesystem rollback; Retry/Fork confirmation names files, commands, Git, external requests, and shared workspaces. |
| AC-10 | Pass | Revisioned corrections replace prior facts; concurrent same-ID Fork/Retry and repeated UI submission execute once. |
| AC-11 | Pass | Failed, cancelled, interrupted, tool-only, usage-only, and missing-usage fixtures render without NaN, fake zero, or infinite running state. |
| AC-12 | Pass | Unknown model windows remain unknown; model, leaf, and compaction changes invalidate stale estimates; hard overflow is checked before dispatch. |
| AC-13 | Pass | PublicRuntime tests cover atomic attach, active request overlay, slow consumers, cursor gaps, resync, reconnect, and terminal convergence. |
| AC-14 | Pass | Real Chrome validation covered 390/1024/1440 in sunshine/moonlight, keyboard/focus, local long-code scrolling, draft/reconnect retention, scroll retention, and Jump to latest. |
| AC-15 | Pass | 10,000 mixed facts fold incrementally; 100 snapshots add zero full-history scans, historical items visited stay zero, memory growth stays below 2.2x, and token deltas are not persisted. |
| AC-16 | Pass | Failed compaction does not increment success; known usage remains; manual compaction uses busy admission, expected revision/leaf, and operation ID. |
| AC-17 | Pass | Journal/protocol tests prove operational facts do not enter model context or move active leaf; unknown facts are atom-safe and legacy clients have explicit capability behavior. |

## Browser Evidence

The fixture session used 28 turns plus a long unbroken code identifier. Chrome
reported exact document/client widths in all six viewport/theme combinations.
At 390px the sidebar and rail were hidden and the 352px observability drawer was
keyboard-openable; at 1024px the sidebar plus drawer were used; at 1440px the
sidebar and rail were visible.

The long code block had `scrollWidth=5936` and `overflow-x:auto` while the page
remained bounded. A transcript scrolled to `scrollTop=1200` retained its position
and composer draft through a LiveView patch and explicit disconnect/reconnect.
The repaired Jump action remained visible and returned `bottomDelta=0`. Fork and
Retry double-submission each produced one durable operation, and reconnect did
not repeat either operation. Chrome reported zero console errors, warnings, or
issues; all 23 navigation resources returned 2xx, 204, or 304.

- [390 sunshine](screenshots/ac14-390-sunshine.png)
- [390 moonlight](screenshots/ac14-390-moonlight.png)
- [390 observability drawer](screenshots/ac14-390-moonlight-drawer.png)
- [390 long code](screenshots/ac14-390-moonlight-long-code.png)
- [1024 sunshine](screenshots/ac14-1024-sunshine.png)
- [1024 moonlight](screenshots/ac14-1024-moonlight.png)
- [1440 sunshine](screenshots/ac14-1440-sunshine.png)
- [1440 moonlight](screenshots/ac14-1440-moonlight.png)

## Validation

Final commands and results:

- `mix compile --warnings-as-errors --no-deps-check`: passed.
- `mix test --no-deps-check apps/sigma_ai/test`: 51 passed.
- `mix test --no-deps-check apps/sigma_protocol/test`: 13 passed.
- `mix test --no-deps-check apps/sigma_session/test`: 218 passed.
- `mix test --no-deps-check apps/sigma_agent/test`: 134 passed.
- `mix test --no-deps-check apps/sigma_web/test`: 178 passed, 1 assets-tagged test excluded by the default filter.
- `mix test --no-deps-check`: 864 passed across 8 umbrella apps, 1 assets-tagged test excluded.
- `mix assets.build`: passed.
- `bun test apps/sigma_web/assets/js/*_test.js`: 15 passed.
- `mix format --check-formatted`: passed.
- `git diff --check`: passed.

The environment intermittently printed `erl_child_setup: failed with error 32`
and one temporary-directory `Could not cd` message. Both isolated and umbrella
test runs exited zero with the counts above. Corrupt-line warnings came from
fixtures that intentionally exercise damaged JSONL recovery.

## Compatibility and Privacy

- Metrics use an explicit schema-version-1 allowlist inside existing v3 journal
  files. They are non-message entries and cannot advance active leaf.
- Protocol V1 clients opt into `metrics.v1`; legacy clients retain the previous
  event set, while unsupported capabilities and versions fail explicitly.
- Provider provenance, journal, writer-failure metadata, and public protocol
  projections discard credentials, authorization headers, raw payloads, and
  arbitrary adapter metadata.
- Existing logs remain readable. Missing legacy usage, timing, identity, and
  compaction detail remain partial or unknown rather than being guessed.

There are no unresolved required-scope issues. SUI-10 remains the only deferred
item and is explicitly optional in the plan and PRD.
