# Sigma Skills: Activation, Completion, and Backplane Sharing

## Product Requirements Document

| Item | Value |
| --- | --- |
| Status | Proposed implementation contract; not a statement of implemented behavior |
| Date | 2026-09-09 |
| Primary repository | `gsmlg-opt/sigma` |
| Integration repository | `gsmlg-opt/backplane` |
| Companion | [Implementation Plan](sigma-skills-plan.md) |
| Reviewed Sigma baseline | `4d4a10802d44f5cf5b3a340678eb77c0610937ea` |
| Sigma branch observed during handoff | `22d39dfa05f3a718fb506d348f537c35279a9b0f` |
| Backplane integration baseline | `bd5bc83005fded6f67beefe3fa8abac31eae506a` |

## 1. Product objective and evidence boundary

Make a skill a discoverable, explicitly selectable, reproducible instruction package that Sigma can activate locally, obtain from Backplane, and deliberately share back to Backplane.

The complete user journey is: discover a skill, select the intended source, supply arguments, prepare a verified package, activate its instructions, execute through the existing Agent runtime, and inspect the result.

This document develops the accepted Sigma skills review. The observations below are source-derived; subsequent requirements are proposed product decisions. No claim is made that the repositories have been compiled, tested, or integration-tested during this handoff. Implementation must reconcile the pinned baseline with the checkout before editing.

### 1.1 Source-supported baseline

| Existing capability or gap | Evidence and implication |
| --- | --- |
| Local discovery | `Sigma.Session.Skills` discovers `~/.agents/skills` and repository `.agents/skills`; its descriptor contains name, description, path, source, enabled state, and the model-invocation flag. Preserve these roots and existing installations. [S1] |
| Automatic discovery | `SessionContext` exposes enabled, model-invocable skill metadata and asks the model to read the skill file. There is no structured activation in this path. [S2] |
| Manual invocation gap | The generic `SlashCommands.expand/1` implementation expands `/init`, not arbitrary skill names. Its setup prompt already mentions manual-only skills and `$ARGUMENTS`. Other LiveView control commands must be inventoried rather than assumed absent. [S3] |
| Existing completion shell | `ChatInputHook` provides a slash-command menu and keyboard handling. Extend it rather than replacing the composer or DuskMoon components. [S4] |
| Scope merging | Session options concatenate global and repository lists without a source-aware name resolver. [S5] |
| Resource boundary gap | External read access is granted by the filename `SKILL.md`, not by an authorized package root. Package references outside the workdir are not covered by that exception. [S6] |
| Runtime foundation | `PublicRuntime` and the Agent WebSocket already exist. Skills need an extension of the public boundary, not another execution engine. [S7, S8] |
| Backplane distribution | Existing `/skills` routes search, retrieve details, download archives, ingest uploads, and import/export collections. Search defaults to 20 results and caps the requested limit at 100; the reviewed router exposes no pagination cursor. [B1, B2] |
| Backplane artifact semantics | Ingest hashes the exact compressed archive bytes with SHA-256. A changed archive for an existing archive-backed slug is upserted, and an unreferenced previous blob may be removed. Do not assume immutable history or safe create-only publishing. [B3] |
| Backplane package format | Archive validation requires one non-root skill directory containing the unique `SKILL.md`; `meta.json` is optional. Sigma must verify all extracted resources, not only entry-file metadata. [B4] |
| Umbrella boundaries | `sigma_session` depends on `sigma_agent` only in tests; `sigma_agent` has no production dependency on `sigma_session`. Do not introduce a production dependency cycle. [S9, S10] |

## 2. Scope and release boundary

### 2.1 Required for feature V1

V1 includes reliable local parsing and discovery; a source-aware effective catalog; deterministic manual invocation; dynamic skill completion; structured model activation; verified package resources; Backplane search, download, and offline cache; explicit upload/share; and a thin Sigma API for catalog access and session-scoped invocation.

A local-only milestone can ship before remote integration. The complete feature is not accepted merely because slash-command completion works. Safe publishing depends on the small Backplane conditional-write extension described in section 8; it must remain unavailable against legacy servers that do not support that contract.

### 2.2 Explicit non-goals

This work does not build a marketplace, plugin runtime, autonomous skill author, dependency installer, workflow scheduler, or new agent executor. It does not introduce Synapsis daemon behavior, Samgita orchestration, or Agent Note as an application dependency. It does not implement a new authentication product, rewrite generic MCP retry handling, promise full compatibility with every vendor's frontmatter extensions, or add immutable Backplane release history.

Backplane is the distribution and sharing service. Sigma remains the execution environment. A remote package is not a command to execute a remote script.

## 3. Architecture and ownership

Keep the existing umbrella structure. Prefer pure functions for parsing, policy, merging, resolution, argument expansion, and rendering. Restrict filesystem, network, persistence, and process coordination to explicit adapters.

| Boundary | Responsibility |
| --- | --- |
| `sigma_session` | Skill descriptors, parser, discovery, effective catalog, source adapters, artifact preparation/cache, installation settings, publication service |
| `sigma_agent` | Invocation orchestration, prompt admission, current-turn activation, read-grant lifetime, cancellation, invocation outcome |
| `sigma_protocol` | Serializable skill references, invocation commands, result/error payload validation, negotiated feature definitions |
| `sigma_tools` / existing dispatcher | Activation tool adapter and propagation of trusted, turn-scoped resource grants to reads |
| `sigma_coding` | Shared canonical-path and resource-boundary enforcement used by read implementations |
| `sigma_web` | Thin HTTP/LiveView adapters, source configuration UI, composer completion, picker, activation/publication status |
| Backplane | Existing skill storage/distribution plus bounded conditional archive publication |

The Agent runtime receives trusted catalog/prepare callbacks and plain resolved data through runtime composition. It must not import Session structs or fetch remote skills from provider serialization. The headless and web entry points must use the same skill-context builder. Do not fix web behavior while leaving stdio with a second discovery policy.

Only existing supervisors, or narrowly scoped supervised children, should own asynchronous preparation and publication. Do not create one GenServer per skill or hold a session process inside an HTTP download.

## 4. Domain model and invariants

| Record | Required meaning |
| --- | --- |
| `SkillSource` | Stable source ID, kind (`repository`, `global`, `backplane`), display alias, configured location, credential reference where needed, enabled state and scope |
| `SkillDescriptor` | Stable logical `skill_id`, source ID, source-local key, name, description, preserved metadata, diagnostics, capability/policy summary; no public absolute paths |
| `SkillBinding` | Repository/global activation choice, explicit source selection, enabled state, optional content pin, and provenance |
| `SkillSnapshot` | Verified immutable package location, package manifest, digest scheme/value, entry body, and provenance; internal-only filesystem paths |
| `SkillInvocation` | Invocation/request IDs, principal/trigger, repository/session IDs, requested reference and arguments, resolved snapshot, admission/message/turn IDs, state and typed outcome |
| `SkillPublication` | Publication/request IDs, immutable upload digest, selected local package, destination, create/replace precondition, state and result |

**Logical identity and content identity are different.** A `skill_id` identifies an entry within a source; a snapshot identifies exact content. A local edit must not silently create an unrelated logical skill. Display names are not primary keys.

Remote archive digests use `sha256-archive`: hash the downloaded `.tar.gz` bytes before extraction. Local snapshots use a separately named `sha256-tree-v1` scheme over a canonical sorted manifest of relative paths, file-byte digests, and executable bits. Never compare those two schemes as though they were equivalent. A human-readable version is descriptive metadata, not proof of immutability.

Core invariants:

1. Every supported activation resolves to one source and one immutable snapshot.
2. Selection, activation, and sharing are separate actions. Loading never installs dependencies or executes package scripts automatically.
3. Explicit invocation can bypass the automatic-selection prohibition, but never a disabled binding or runtime permissions.
4. Runtime authority comes from trusted configuration and the authenticated/delegated caller, never from package metadata or a client-supplied `trigger` field.
5. Active/queued work never silently switches to newer content. Disabling a pending skill prevents it from starting.
6. A catalog, download, parse, or policy failure ends that operation explicitly; it is not converted into a prompt asking the model to keep retrying.

## 5. Local catalog and invocation requirements

### FR-01 — Discovery and parsing

Preserve current local roots and configuration overrides. Discover relative to the session's effective workdir, including worktrees. Do not silently fall back to another checkout's skills when the current worktree lacks them.

Use a maintained YAML parser behind a bounded frontmatter adapter; choose and pin the dependency in the implementation contract. Support LF/CRLF, quoted strings, comments, literal/folded scalars, and nested metadata. Preserve unknown fields without treating them as executable instructions or privileges. Reject duplicate keys and malformed types for supported policy fields. In particular, `disable-model-invocation: true # manual only` must produce the boolean value `true`.

A non-empty description remains required. Preserve the existing directory-name fallback for missing names as a diagnosed compatibility path; do not silently rename installed skills. Recognize `disable-model-invocation` as an invocation-control field. An optional string `argument-hint` can inform the picker. Preserve other vendor-specific fields with an unsupported-field diagnostic where their semantics might otherwise be misleading; this release does not claim to execute those extensions.

Scanning must be bounded, cancellation-aware, and deduplicated by canonical root. Report unreadable files, malformed metadata, duplicate names, cyclic links, and limit violations without failing unrelated skills. A configured local root may itself be a symlink; resolve and authorize its real root, do not follow links indefinitely.

### FR-02 — One effective catalog

Use one catalog revision and resolver for the UI, API, prompt metadata, and activation tool. Their views differ by policy filters, not independent discovery logic.

Unqualified resolution order is an explicit valid binding first, then repository, global, and enabled Backplane bindings. Multiple matches within the winning scope produce `ambiguous_skill`. An explicit disabled binding or a disabled matching higher-priority entry must not silently fall through to another source. A malformed discoverable entry should produce a diagnostic rather than an invisible replacement.

Qualified references use `repo:<name>`, `global:<name>`, or `backplane/<source-alias>:<name>`. These are selectors, not paths or arbitrary URLs. API callers use opaque `skill_id` values where possible. Built-in command names remain reserved; conflicting skills remain reachable through `/skill <qualified-reference>`.

Catalog refresh, source changes, and enable/disable updates become visible without restarting Sigma. A running turn retains its prepared snapshot. UI updates carry a catalog revision; stale results must not overwrite a newer selection.

Legacy name-based global disable entries migrate only to the global source. Disable all ambiguous matching global entries and report the ambiguity rather than accidentally enabling one or disabling a remote skill with the same name.

### FR-03 — Invocation policy

| Effective state | Manual picker | Automatic metadata/tool | Explicit invocation |
| --- | --- | --- | --- |
| Enabled, automatic allowed | Visible | Allowed | Allowed |
| Enabled, `disable-model-invocation: true` | Visible, marked manual-only | Hidden; model activation denied | Allowed for a human request or explicitly authorized delegated caller |
| Disabled source/binding/skill | Disabled status in management; not executable | Hidden and denied | Denied |
| Invalid or unsupported package | Diagnostic only | Hidden and denied | Typed error, no fallback |
| Remote result not yet enabled | Visible in remote search, not in normal command list | Not automatically selected | Requires explicit enable/install action before invocation |

The manual-only field governs Sigma's discovery/activation behavior. It is not a filesystem security boundary that makes text already readable in a repository unknowable to a model. Generic reading of repository files remains governed by ordinary file permissions.

### FR-04 — Deterministic manual invocation

Support `/skill <reference> <arguments>` as the unambiguous form and `/<skill-name> <arguments>` only when it does not conflict with built-ins. Both go through the same activation service as the picker and API; the model does not decide which skill was meant.

Parse the reference token and preserve the remaining argument text, including newlines. Replace literal `$ARGUMENTS` tokens once, without recursive expansion, shell interpolation, environment-variable expansion, or command substitution. When the placeholder is absent, append arguments in a separate labeled data block. Do not inject the arguments twice. An empty argument string is valid unless a future explicitly supported contract says otherwise.

Prepare the package and its entry body before invoking the provider. Inject instructions into the owning turn, not into the historical first user message or a permanent global prompt. Display a concise skill/source badge and argument summary instead of rendering the entire internal expansion as ordinary chat text.

The initial policy is `next_turn`: start when idle; otherwise queue as a follow-up. Skill invocation is never implicitly steering. Preserve normal chat's existing admission behavior. Switching browser sessions must not retarget an accepted invocation.

### FR-05 — Structured model activation

Add a bounded `activate_skill` tool adapter backed by the same resolver, preparation, and policy functions. It activates an allowed skill inside the existing turn and returns its instructions/resource base; it must not recursively submit another turn or launch another Agent.

Replace the automatic skill reminder's generic activation guidance with the structured path. Preserve normal `read` behavior for files. Remove the global filename-only privilege exception only after the replacement path and compatibility tests are in place.

The dispatcher supplies the caller origin, active session/turn, and available grants. Tool arguments cannot override those values. Repeating the same successful activation in one turn must not inject its body again. The runtime must suppress repeated identical failed activation attempts and enforce a total activation budget, without relying on a prompt warning to stop a loop.

### FR-06 — Completion and skill picker

Extend `ChatInputHook` and its existing menu. `/` shows built-ins and enabled manual candidates grouped by kind; name and description filtering is deterministic. `/skill ` opens source-aware selection. Rows show name, description, source, manual-only state, argument hint, and cache/unavailable status when relevant.

Arrow keys navigate; Tab and Enter select an open candidate without executing it; Escape dismisses it. A later explicit send submits the invocation. Do not consume Enter during IME composition. Preserve surrounding arguments, focus, clipboard behavior, and existing attachments behavior; do not expand attachment support as part of this feature.

The in-session picker inserts a selection rather than immediately running it. Management-page actions must require a target session. Expose unknown-name, ambiguity, disabled, loading, empty, offline, and stale-selection states. Remote search is explicit, debounced, cancellable, and metadata-only; a response to an older query cannot replace newer results. Do not download packages while merely filtering commands.

## 6. Package preparation and resource access

### FR-07 — Immutable snapshots and read grants

A preparation operation captures the entry file and package resources in a private, immutable cache snapshot. Local source directories are never rewritten to install a remote skill. Snapshot creation detects concurrent source changes using a verified manifest/recheck; allow one bounded retry and then return `source_changed` rather than combining changing inputs without notice.

For local packages, allow a symlinked configured root after resolving it. Inside that root, only materialize links whose canonical targets remain inside it; reject escaping or cyclic links. For downloaded archives, reject symlink/hardlink entries, special files, absolute paths, traversal, duplicate normalized paths, and ambiguous skill roots. Enforce compressed-byte, total-expanded-byte, entry-count, and per-entry limits while reading, not only after extraction. The Backplane format's single enclosing directory must be retained on upload and safely normalized on download. [B4]

Verify the remote archive digest before extraction. Extract into a private staging directory and publish the snapshot atomically only after validation. Concurrent requests for the same source/digest should share preparation; cancellation by one waiter must not delete a snapshot used by another.

Grant read-only access to the verified package root for the owning turn. Relative resource paths resolve against the snapshot root, while ordinary project edits and shell commands retain the session workdir. Reading a script is not permission to execute it. Package metadata cannot increase shell, filesystem-write, network, or approval privileges.

Public skill references and model tool parameters cannot supply a trusted cache root. Both read implementations and dispatcher validation must use the same resource-boundary rules. Keep original input and canonical path checks where relevant; do not replace the current exception with an unrestricted external directory allowlist.

Active and queued snapshots are retained. Historical activation records keep the resolved identity/digest; retained snapshots allow explicit replay. Missing historical artifacts return `artifact_unavailable`, never a silent download of the current slug. Context compaction must preserve the structured reference and rehydrate required active instructions within budget; it must not depend on a mutable `SKILL.md` read later.

## 7. Consuming skills from Backplane

### FR-08 — Remote source adapter

Configure each Backplane source by a stable alias, operator-approved base URL, credential reference, and enablement policy. Secrets stay in the existing secret/configuration boundary and never enter skill metadata, prompts, browser candidate data, archives, or telemetry. Source settings can be configured without copying credentials into a repository.

Use the existing routes:

| Existing Backplane route | Sigma behavior |
| --- | --- |
| `GET /skills?q=...&limit=...` | Search metadata only; treat the response as a limited result set, not a complete registry |
| `GET /skills/:slug` | Resolve source kind, description, advertised digest, and metadata before preparation |
| `GET /skills/:slug/archive` | Download the archive-backed package and verify the exact compressed-byte SHA-256 |
| `GET /skills/export`, `POST /skills/import` | Existing collection tools; not required on the interactive activation path |

These routes and their current limitations are observed behavior. The pagination, version pinning, cache semantics, and policies described here are Sigma requirements, not claims that Backplane already implements them. [B1–B3]

A remote search result is not automatically trusted or enabled. Explicit selection into a repository/global binding approves one verified digest for use. A manual-only field is enforced from the verified package, not assumed from the search payload, which does not currently expose all invocation policy. Unknown remote policy may be shown as “inspect to enable”; it must not enter automatic discovery before validation.

V1 activates `source_kind=archive` entries with a valid archive/digest. Generated/non-archive results are shown as unsupported for installation, with a reason. Do not fabricate missing resource files from `content`, treat generated content as an archive, or publish over a generated slug. Generated-skill materialization is deferred until a separate complete package contract exists.

A binding pins content. Updates show an available change and require an explicit update action; a running or queued invocation remains pinned. When the current slug no longer serves a requested digest and the old artifact is not cached, return `artifact_unavailable`. A version label alone is insufficient because the reviewed server upserts and can clean up old blobs. [B3]

If metadata and download disagree because the slug changed, return `remote_changed`; do not transparently run the replacement. With Backplane offline, enabled verified cached bindings continue working. Uncached content fails clearly. Mark search/catalog data stale and disclose the last successful refresh; there is no promise of immediate remote revocation while disconnected. A locally disabled binding is still denied offline.

Only read operations retry transient failures, within the bounds in section 11. Permanent errors, hash mismatches, invalid archives, and disabled states do not retry. Build request URLs from the configured source and validated/encoded slug; do not follow an untrusted arbitrary URL or forward credentials across origins. Keep discovery and provider-context rendering free of network side effects.

## 8. Sharing skills back to Backplane

### FR-09 — Explicit, conditional publication

Sharing starts with an explicit user action or an authorized API request identifying an existing local skill, destination source, and create/replace intent. It is never a consequence of loading a skill. Preview the file manifest, destination slug, digest, and whether an existing artifact would be replaced. Require explicit approval for replacement.

Publish the complete selected package, not just `SKILL.md` and never the surrounding repository. Preserve relative resources, supported metadata, license information, and normalized executable bits. Block credential/private-key files and expose excluded paths; arbitrary embedded secrets cannot be guaranteed detectable, so preview/approval remains required. If exclusions break a declared package resource, fail preparation rather than presenting the package as complete.

Use deterministic archive construction: stable entry order, normalized owner/timestamps, and stable compression metadata. Persist the exact upload bytes/digest until the outcome is resolved. Two retries of one publication must never rebuild subtly different archives.

**Legacy Backplane `POST /skills` is an upsert, not a safe conditional publication endpoint.** Checking existence before calling it does not solve concurrent writers. [B3] Add the following narrow Backplane extension, reusing existing validation and blob/storage code:

| Proposed Backplane extension | Contract |
| --- | --- |
| `GET /skills/_capabilities` | Advertise `conditional_archive_publish_v1`; register this reserved route before the dynamic slug route |
| `PUT /skills/:slug/archive` with `If-None-Match: *` | Create only; an existing slug fails the precondition without changing it |
| `PUT /skills/:slug/archive` with a strong `If-Match` archive ETag | Replace only the exact existing archive digest; missing or changed targets fail the precondition |
| Archive ETag | `"sha256:<lowercase-hex-of-compressed-archive>"`; attach it to archive responses and use that representation for writes |

The PUT body is `application/x-tar+gzip`; the package-resolved slug must equal the route slug. Missing preconditions return 428, false preconditions 412, unsupported/generated conflicts 409, and invalid packages 422. Creation returns 201 and replacement 200. Evaluate conditions atomically with the database insert/update; use a unique constraint plus an appropriate atomic update/locking strategy, not only application-side lookup. Blob cleanup must remain correct for competing writers and unsuccessful conditional writes.

Keep legacy reads/uploads compatible for existing clients. Sigma publishing requires the advertised extension and must not downgrade to unsafe POST. Against legacy servers, local export and remote consumption remain available, while network publishing reports `publish_precondition_unsupported`.

Reserve a local publication ID and request key before upload. A lost response produces `outcome_unknown`, not an automatic new upload. Reconcile through the remote digest when possible: matching uploaded bytes can be reported as current content; mismatching state requires inspection and must not silently overwrite again. Do not claim exactly-once remote side effects without a server idempotency ledger. A later Backplane history/idempotency feature is independent of this V1 contract.

## 9. Public API and protocol

### FR-10 — Thin transport adapters

All routes below are **proposed Sigma endpoints**, not existing routes. Public JSON uses camelCase to align with the existing Protocol payload convention; Backplane's existing snake_case metadata is translated in the source adapter. Public repository IDs resolve through Sigma's registered-repository boundary; requests cannot inject filesystem workdirs or cache paths.

| Method and route | Purpose |
| --- | --- |
| `GET /api/v1/capabilities` | Report supported skills features and whether configured destinations support safe publication |
| `GET /api/v1/skills` | Effective catalog or explicit remote search; accepts `repositoryId`, optional `sessionId`, `view`, `q`, `sourceId`, and bounded pagination |
| `GET /api/v1/skills/:skillId` | Descriptor, source, policy, digest/cache status and safe diagnostics in the authorized repository scope |
| `POST /api/v1/sessions/:sessionId/skill-invocations` | Reserve and prepare an explicit invocation, then submit through existing Agent admission |
| `GET /api/v1/sessions/:sessionId/skill-invocations/:invocationId` | Poll preparation, queue, execution, and terminal outcome |
| `POST /api/v1/sessions/:sessionId/skill-invocations/:invocationId/cancel` | Cancel preparation or queue entry; delegate running work to existing turn cancellation |
| `POST /api/v1/skill-publications` | Reserve a bounded publication operation for an authorized local skill |
| `GET /api/v1/skill-publications/:publicationId` | Poll upload/reconciliation outcome |

A repository ID is required on session-scoped requests because a bare session ID must not accidentally resolve in a different repository. When supplied, `sessionId` selects the effective worktree context. List results contain `catalogRevision`, `items`, `nextCursor`, `partial`, and source diagnostics. Local effective-catalog pagination is complete; a legacy remote search is explicitly a partial search window, not a fake cursor over the entire server registry.

Invocation request fields are `repositoryId`, `skillId` or a qualified `reference` (exactly one), `arguments` (string), optional `expectedDigest` (scheme/value), and `mode=next_turn`. Require `Idempotency-Key` for external invocation/publication writes; UI and protocol adapters generate a request ID with the same semantics. The server supplies principal, trigger origin, and grants.

A new valid invocation/publication returns 202 with its ID and current state. This means the operation was recorded, not that the provider or skill has run. A duplicate request with the same key and same request fingerprint returns the same operation/result; the same key with different content returns 409. Invocation keys are scoped to principal, repository, and session, and retained for the session record's lifetime. Publication keys are scoped to principal, repository, and destination source and retained with the publication record; unresolved records must not expire or be compacted away. The resolved digest is persisted separately from the submitted-request fingerprint so replay cannot resolve a new “latest” version.

Use typed errors: `skill_not_found`, `ambiguous_skill`, `skill_disabled`, `manual_invocation_required`, `unsupported_skill_kind`, `invalid_skill_metadata`, `source_changed`, `remote_unavailable`, `remote_changed`, `digest_mismatch`, `unsafe_archive`, `resource_denied`, `artifact_unavailable`, `context_budget_exceeded`, `queue_full`, `idempotency_conflict`, `publish_precondition_unsupported`, and `publish_conflict`. Include a stable code, safe explanation, retryability, and correlation ID; never leak tokens or server paths.

For direct/stdio/WebSocket clients, introduce `skill.invoke`, `skill.invocation.status`, and `skill.invocation.cancel` commands through the existing public runtime. Declare the extension as `skills.v1`. Use a single skill-invocation update payload plus existing prompt/turn events; include correlation IDs, not duplicate progress systems. Negotiate before emitting new closed-enum event types. Legacy subscriptions must continue receiving their existing event types; do not silently widen a closed Protocol V1 contract without compatibility tests. Catalog reads can call the shared service without starting an Agent.

Remote callers require a trusted caller resolver/delegation policy at the existing deployment boundary. Manual-only invocation and publication are separate explicitly delegated capabilities; callers cannot self-assert that an LLM request was a human action. Local development may use an explicitly configured loopback principal. Deny remote use when that trust boundary is unconfigured. This is an integration requirement, not a new account/login/RBAC application.

## 10. Lifecycle, durability, and observability

### FR-11 — Admission and recovery

An accepted invocation transitions through `preparing`, optionally `queued`, `running`, and one of `completed`, `failed`, `cancelled`, or `interrupted`. Validation failures before reservation return a typed rejection. Model activation inside a running turn is a correlated activation record, not a second invocation queue.

Serialize request-key reservation and prompt admission through the session's existing persistence/coordination boundary. Preserve admission order even when preparation tasks finish in a different order. Write the invocation-to-message/turn mapping with the durable admission record before acknowledging that admission; no crash gap may admit a duplicate prompt on retry.

Recheck binding/policy before starting queued work. Cancellation during preparation must stop further admission; late download/task completions are ignored. Cancelling one queued invocation must not cancel another turn. Reuse the existing running-turn cancellation and approval behavior.

On restart, reconstruct IDs, request mappings, and outcomes from existing session persistence. Reconcile already terminal turns. Mark unrecoverable in-flight/preparation/queued invocations `interrupted`; do not automatically rerun externally visible work. Repeating the original request returns that interrupted result. An explicit new request can replay a retained snapshot. This provides at-most-one admission for a request key, not exactly-once tools or side effects.

Store invocation metadata and required structured references using existing session-log conventions; use the existing configuration/state layout for bindings/cache/publication records. No new database service is required. Keep body/resource snapshots out of ordinary telemetry, and define retention/compaction rules before treating a cache entry as disposable.

### FR-12 — Operations and rollout

Show which skill/source/digest is preparing, queued, active, completed, or failed. Separate “instructions loaded” from “turn completed”; completion does not prove that a requested deployment or code change was correct.

Emit bounded events/metrics for parse diagnostics, catalog refresh duration, resolution conflicts, cache hit/miss, preparation latency, digest failure, activation outcome, retry count, and publication conflict. Use IDs/digests in default logs; arguments and skill bodies can contain private data and remain only in access-controlled session storage. Sanitize source errors before displaying them.

Ship local activation, Backplane consumption, API access, and publishing under independently controllable configuration switches. Default remote sources and publication to disabled until configured. Rolling back remote features must not delete local skills or the snapshots required by existing sessions.

## 11. Proposed operational defaults

These are acceptance targets and guardrail defaults, not measurements of the current implementation. Operators may tune documented limits, but disabling bounds is not a supported default.

| Area | V1 default/target |
| --- | --- |
| Discovery | Maximum depth 32; 2,000 candidate skills per configured root; bounded diagnostics |
| Package | At most 500 regular files, 10 MiB compressed, 20 MiB total expanded, 5 MiB per resource, and 256 KiB `SKILL.md`; enforce aggregate directory/header bounds too |
| Frontmatter and arguments | Frontmatter at most 64 KiB; arguments at most 16 KiB |
| Model context | Check the existing context/token budget before injection; fail rather than silently truncating mandatory instructions |
| Source I/O | At most 3 total attempts for eligible reads, a 30-second operation deadline, and bounded backoff; respect Retry-After only inside that deadline |
| Publication | One upload attempt per dispatch; reconcile uncertain outcomes rather than blindly retrying a mutating request |
| Preparation/queue concurrency | At most 4 preparation workers per runtime and 2 concurrent transfers per source; at most 32 pending invocations per session and 16 pending publications per runtime |
| Model activation | At most 8 distinct activations and 16 activation attempts per turn; a repeated identical permanent failure terminates skill continuation with an actionable error |
| Completion | In-memory filtering for 1,000 enabled skills, p95 under 100 ms on the documented test runner; no provider call or archive download |
| Catalog API | Default 20 and maximum 100 results per local page; explicit partial indication for legacy remote search |
| Cancellation | Local cancellation acknowledged within 1 second in deterministic tests; network abort is bounded by the underlying I/O deadline |

## 12. Acceptance and release gates

| ID | Scenario and required result |
| --- | --- |
| AC-01 | Existing global/repository skills still discover; valid YAML comments, nested metadata, LF/CRLF, and block scalars parse consistently. Invalid policy types never default to automatic permission. |
| AC-02 | The same source-aware catalog powers UI, API, and Agent metadata. Duplicate names resolve deterministically or return ambiguity; disabled higher-priority entries do not silently fall through. |
| AC-03 | A manual-only skill appears in the picker and runs explicitly, but is absent from automatic metadata and rejected by model-origin activation. Disabled skills fail before any provider call. |
| AC-04 | Slash command, picker, and API produce equivalent pinned instructions and arguments. `$ARGUMENTS` expands once; a same-named built-in is not replaced. |
| AC-05 | Candidate selection does not send a message. IME Enter, Tab, Escape, focus, stale async results, and arguments are covered by browser-level tests. |
| AC-06 | Global and remote references/resources are readable inside the activated package; sibling directories, escaping links, arbitrary external `SKILL.md`, and write/execute privilege escalation are denied. |
| AC-07 | Corrupt, traversing, duplicate-path, oversized, cyclic, or interrupted packages never become usable cache entries. Local source mutation is detected or safely rejected. |
| AC-08 | Backplane archive-backed skill download verifies the exact compressed-byte hash; generated entries report unsupported status; limited search results are not presented as a complete registry. |
| AC-09 | Offline verified bindings work; uncached or unavailable historical content fails. Updating a source or slug does not change an active or queued snapshot. |
| AC-10 | Sharing preserves the full safe resource package. Legacy servers are not used for unsafe uploads. Competing create/replace operations cannot silently overwrite under the conditional contract. |
| AC-11 | Lost upload responses produce reconciliation/unknown state without a blind second write. Precondition failure retains the previous artifact and cleans up unreferenced staging blobs. |
| AC-12 | Concurrent duplicate invocation requests create one admission; mismatched keys fail. Restart returns the same outcome or `interrupted`, not another provider run. |
| AC-13 | Queue ordering and cancellation hold during preparation and execution. Disabling pending work blocks its start. No late task callback admits cancelled work. |
| AC-14 | Model activation stays inside the current turn, deduplicates repeated bodies, respects budgets, and exits repeated permanent failure without an unbounded loop. |
| AC-15 | Headless/direct/stdio/WebSocket/LiveView paths share semantics, and legacy Protocol clients retain their existing behavior. Public payloads contain no process terms, secrets, or absolute paths. |
| AC-16 | Session resume/compaction keeps the resolved references and required snapshot; missing content is reported rather than replaced. Local skills still work with all remote features disabled. |

A local-only release requires AC-01–07 and the applicable local portions of AC-12–16. Full feature V1 requires every acceptance criterion, including a real Backplane smoke test. Passing mocked integration tests alone does not establish deployment compatibility.

## 13. Deferred work and implementation decisions

Deferred: immutable remote version history, complete remote pagination, generated-skill materialization, package signatures, vendor-specific execution extensions, multi-skill composition UI, and general MCP loop recovery. None may be silently assumed by V1.

The implementation contract must freeze the exact YAML dependency, canonical local manifest format, durable record/event encoding, and negotiated Protocol compatibility mechanism after repository preflight. These are bounded engineering decisions, not reasons to postpone local activation or ask the model to infer missing behavior at runtime. Product semantics in this PRD remain authoritative unless an explicit design amendment records why they change.

## 14. Source register

Sources identify observed code, not evidence that the proposed features are implemented.

- [S1] Sigma local skills: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_session/lib/sigma_session/skills.ex
- [S2] Skill metadata/context injection: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_agent/lib/sigma_agent/session_context.ex
- [S3] Slash expansion and setup prompt: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_session/lib/sigma_session/slash_commands.ex
- [S4] Existing composer hook: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_web/assets/js/app.js
- [S5] Session composition: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_web/lib/sigma_web/protocol_session_options.ex
- [S6] Path checks: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_coding/lib/sigma_coding/utils/path_utils.ex
- [S7] Public runtime: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_agent/lib/sigma_agent/public_runtime.ex
- [S8] Agent socket registration: https://github.com/gsmlg-opt/sigma/blob/4d4a10802d44f5cf5b3a340678eb77c0610937ea/apps/sigma_web/lib/sigma_web/endpoint.ex
- [S9] Session dependencies: https://github.com/gsmlg-opt/sigma/blob/22d39dfa05f3a718fb506d348f537c35279a9b0f/apps/sigma_session/mix.exs
- [S10] Agent dependencies: https://github.com/gsmlg-opt/sigma/blob/22d39dfa05f3a718fb506d348f537c35279a9b0f/apps/sigma_agent/mix.exs
- [B1] Backplane Skills API: https://github.com/gsmlg-opt/backplane/blob/bd5bc83005fded6f67beefe3fa8abac31eae506a/apps/backplane_skills/lib/backplane/skills/api_router.ex
- [B2] Backplane API mount: https://github.com/gsmlg-opt/backplane/blob/bd5bc83005fded6f67beefe3fa8abac31eae506a/apps/backplane_api/lib/backplane/api/router.ex
- [B3] Backplane digest/upsert/cleanup: https://github.com/gsmlg-opt/backplane/blob/bd5bc83005fded6f67beefe3fa8abac31eae506a/apps/backplane_skills/lib/backplane/skills/ingest.ex
- [B4] Backplane archive format: https://github.com/gsmlg-opt/backplane/blob/bd5bc83005fded6f67beefe3fa8abac31eae506a/apps/backplane_skills/lib/backplane/skills/archive.ex
