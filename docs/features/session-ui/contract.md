# Session UI Observability V2 Contract

Date: 2026-09-09
Baseline HEAD: `6d1e64f547bd71962b3aed4fb1655733c75ae2a6`
Branch: `main`

This contract was rechecked against the current working tree based on the HEAD
above. Session UI V2 changes are still uncommitted, so HEAD alone does not
contain the interfaces below. Completion and executed-gate evidence belong in
`implementation-report.md`, not in this contract.

## Current Boundaries

| Area | Current source and symbols | Frozen contract | Compatibility boundary |
| --- | --- | --- | --- |
| Identity | Stable `session_id`, `turn_id`, `request_id`, message/tool/compaction IDs; request facts include ownership and retry relation | Corrections replace by identity + revision; title/path never define ownership | Legacy facts with missing IDs/timing remain partial/unknown rather than guessed |
| Provider usage | `Sigma.Ai.ProviderRequest` and `ProviderUsage` emit normalized request facts | Input/output totals do not re-add cache/reasoning subsets; monotonic durations are persisted as elapsed values | Hidden provider retries remain outside observable coverage |
| Journal | `EntryEncoder`/`EntryDecoder`, `Writer`, `Journal`, and `Metrics` persist and fold versioned operational facts | Writer remains the append boundary; metrics do not enter model context or advance active leaf | Unknown metrics facts are ignored; old messages and unknown non-message entries remain readable |
| Runtime snapshot | `PublicRuntime.runtime_snapshot/4` exposes phase, model, context/policy, metrics, and watermark | Top-level metrics are durable; `runtimeSnapshot.metrics.activeRequest` is a transient overlay | No PID/ref/secret or internal OTP name crosses the protocol boundary |
| Subscription | `ProtocolSubscription` creates an atomic attach snapshot and ordered cursor | Gap/overflow emits `resync_required`; client replaces projection from owned subscription snapshot | `metrics.changed` requires explicit `metrics.v1`; omitted capability preserves legacy closed event enums |
| Retry / Resend | `session.retry` uses `Runtime.retry_turn` and a persisted checkpoint; Resend is current-leaf `prompt.submit` | Retry makes one replacement branch/turn; Resend is never labeled Retry | Missing attachments/model replacement, busy state, or stale checkpoint fail explicitly |
| Fork | `session.fork` uses serialized repository operation and selected lineage | Child own usage starts at zero; selected origin facts are inherited; parent totals do not change | Shared workdir/files/Git/external side effects are not rolled back or isolated |
| Operation admission | `RepositoryProcess` owns busy guard, flush, operation ID, source revision/leaf checks | Retry/Fork/Compact are idempotent for the same operation ID/fingerprint | Reusing an ID with different input or acting on stale source is a conflict |
| Context / compaction | Runtime `ContextSnapshot`/policy and durable compaction facts replace historical-max UI inference | Current estimate may decrease; only committed compaction increments success count | Unknown model window stays unknown; failed compaction usage remains attributable |
| Privacy | `Sigma.Protocol.Metrics.sanitize_request_fact/1` is used at journal and protocol boundaries | Request metrics use a fixed field allowlist and semantic provenance allowlist | Credentials, headers, raw payloads, and arbitrary adapter metadata are excluded |

## Frozen Ownership and Integration Rules

1. `sigma_protocol` owns versioned, I/O-free DTOs and closed event/command
   schemas. `sigma_ai` owns provider adapter facts and usage normalization.
2. `sigma_session` owns durable operational records and a pure metrics fold;
   `Sigma.Session.Writer` remains the only append commit boundary. Metrics
   records are not model messages and do not advance the conversation leaf.
3. `sigma_agent` owns runtime phase, context/policy, operation admission, and
   the live projection restored from journal facts. `sigma_web` renders the
   projection and does not calculate cumulative usage or thresholds.
4. Session own usage, active-lineage usage, and inherited usage remain distinct.
   Fork copies origin references but starts own usage at zero. A usage correction
   replaces the prior revision for one request.
5. `SessionLive` is the SUI-07/SUI-09 integrator. `Sigma.Agent` runtime-path
   changes are integrated by SUI-04. Writer/encoder/log format changes belong
   to SUI-03. SUI-06 must use fixtures and independent components.
6. Existing v3 logs, sidecars, active-leaf replay, and fork behavior remain
   readable. Metrics facts use schema version 1 inside the existing v3 journal;
   Protocol V1 metrics delivery is gated by `metrics.v1`.

## Version and Compatibility Decision

The wire envelope stays at Protocol version 1. Snapshots advertise
`metrics.v1`, `subscription.cursor.v1`, and `subscription.resync.v1`.
`subscription.attach.requiredCapabilities` is validated and returned as
`enabledCapabilities`; omitting `metrics.v1` guarantees that the subscription
does not receive `metrics.changed`. Unsupported capabilities and non-V1
envelopes fail explicitly.

Metrics operational records use schema version 1 in the existing v3 journal.
They are not messages, are excluded from model context, and cannot become the
conversation active leaf. The current reader ignores unknown metrics facts and
preserves unknown non-message branch entries. This current-reader guarantee is
not a blanket safe-write promise for arbitrary old binaries: stop writers and
back up JSONL before downgrade, and do not write in place with an unverified
older binary.

Request facts cross journal and wire boundaries only through the metrics
allowlist. Credentials, authorization headers, raw provider payloads, and
unrecognized provenance metadata are discarded.

## Fixture Checklist

These fixtures are the shared minimum for SUI-01 through SUI-04 and SUI-11.
They should be represented as pure maps/JSONL lines, not provider calls.

- one session header, one turn, and multiple requests (main, compaction,
  auxiliary) with stable `session_id`, `turn_id`, and `request_id`;
- input `40_000` containing `30_000` cache and output `1_000` containing `400`
  reasoning, proving totals are not double-counted;
- weighted throughput: `10/100ms` plus `1000/20_000ms` => `50.25 tok/s`;
- a 30-second tool interval outside provider requests, proving it does not
  change LLM request throughput;
- duplicate terminal delivery, late usage correction, and request revisions;
- usage missing, partial, unknown, zero output, zero/negative elapsed, failed,
  cancelled, interrupted, tool-only, and usage-only terminal requests;
- visible transport retry as a new request related to the same turn, while a
  hidden gateway retry remains uncovered/unknown;
- fork parent/child ownership: inherited origin facts, child own usage zero,
  parent total unchanged, and old sibling branch excluded from active lineage;
- compaction start, committed, failed, and committed correction, with before /
  after context values and summary entry ID; only committed counts as success;
- context epoch invalidation after compaction, model change, and leaf change;
- malformed/truncated JSONL, duplicate IDs, forward parents, unknown entry
  types, legacy missing timing/usage fields, and legacy double-header fork;
- subscription cursor gap, repeated event, snapshot watermark, and restart
  recovery with an in-flight request marked interrupted/unknown;
- operation idempotency and revision conflict for Retry/Fork/Compact while
  idle, running, waiting for approval, and cancelling;
- a 10,000-record journal fixture proving incremental folding and no token-level
  persistence.

## Current Interface Status

The current working tree contains the P0 interfaces described above: versioned
durable metrics, bounded runtime/protocol snapshots, context and compaction
projection, checkpoint Retry, current-leaf Resend, and controlled Fork. SUI-10
Inspector/prediction remains optional and outside this contract. Consult
`implementation-report.md` for actual test commands, browser evidence, and the
overall completion decision; this document does not turn source presence into a
release claim.
