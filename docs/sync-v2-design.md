# Sync v2: server-ordered operation log + on-demand snapshot

Status: proposal · 2026-10-27

## 0. Why v1 fails

v1 is state-based: replicas exchange whole `Deck` documents and merge them with
per-card last-writer-wins on device wall-clock `updatedAt`. Verified defects:

| # | Defect | Where | Effect |
|---|--------|-------|--------|
| D1 | Seed decks use random `uuid.v4()`; native builds start with sync off and seed locally | `lib/data/seed_data.dart:39,48`, `DecksNotifier.build` | Every device that enables sync uploads its own copy of the sample decks → duplicates |
| D2 | `applyRemote` snapshots `_current()`, awaits a `saveDeck` per deck, then assigns `state` from the stale snapshot | `lib/state/decks_notifier.dart:40-68` | A rating/edit made during those awaits vanishes from memory; the next edit on that deck writes the stale deck over disk → permanent lost update |
| D3 | Conflict resolution compares timestamps from different device clocks | `merge.dart:10,19` | Skewed device's *older* rating wins → FSRS scheduling regresses. `Deck.updatedAt` is bumped by every rating, so deck name/tombstone resolution is decided by unrelated activity |
| D4 | "Pending" = `stamp >= lastPushAt` on the local clock | `sync_service.dart:137` | Clock stepping backwards (NTP, manual change) makes edits invisible to push forever; data pulled from a fast-clock device is re-pushed every sync |
| D5 | Postgres cursor/`synced_at` = `clock_timestamp()`, no monotonic guard | `postgres_sync_store.dart:117,153,191` | Server clock step or DB failover → `synced_at > since` skips rows permanently (the memory server guards this, Postgres does not) |
| D6 | Unit of transfer is the whole deck incl. unbounded `removedCards` | `sync_payload.dart`, server `decks.body` | One rating ⇒ full deck rewrite on server and full deck download on every other device; `reviews.jsonl` fully re-read each sync |

D2–D5 share a root cause: correctness depends on timestamps and on read-modify-write
of shared in-memory state without serialization. The redesign removes clocks from
the correctness path entirely.

## 1. Requirements

Functional
- Mutations: create/rename/delete deck; add/edit/remove card; review card.
- Offline-first: every mutation applies locally immediately, syncs later.
- Any number of devices converge to identical state after they all sync.
- No mutation acknowledged by the UI is ever lost (except by explicit domain rule, e.g. edit-after-remove).
- New/reset device obtains the full current collection in one request.

Non-functional (assumed)
- 1 user per account, ≤ 5 devices, ≤ 50k cards, ≤ 500 reviews/day (~150k ops/year).
- Sync latency target: < 1 s on a warm connection; snapshot < 5 s for 50k cards (gzip).
- Single Dart server + Postgres; no new infrastructure.

Constraints
- Shared `anki_core` package already used by app and server → the reducer lives there.
- Web build is served by the server (upgrades in lockstep); native builds may lag.

## 2. High-level design

```
 ┌──────────────── Client ─────────────────┐          ┌─────────────── Server ────────────────┐
 │ UI ──dispatch(op)──▶ CollectionStore    │          │                                        │
 │                      (single writer)    │          │  POST /api/v2/sync                     │
 │   base  (server state @ seq N, on disk) │  ops ──▶ │   ├ dedupe by op_id                     │
 │   outbox (unacked ops, jsonl, durable)  │          │   ├ assign seq = ++users.head_seq       │
 │   view = reduce(base, outbox)  ──▶ UI   │ ◀── ops  │   ├ reduce into materialized tables     │
 │                                         │  seq>N   │   └ return ops with seq > since         │
 │ SyncService: push outbox, pull, rebase  │          │                                        │
 │                                         │ ◀─ snap  │  GET /api/v2/collection  (snapshot@seq) │
 └─────────────────────────────────────────┘          └────────────────────────────────────────┘
                       anki_core: Op, Collection, reduce()  — identical on both sides
```

Principle: the server imposes a **total order** (`seq`) on operations. Every replica
computes state as `reduce(snapshot, ops in seq order)`. Clients show
`base + pending outbox` optimistically and **rebase** when server ops arrive.
This is the Replicache/Linear model, not a CRDT: simpler, and sufficient because
the server is always the ordering authority.

## 3. Deep dive

### 3.1 Operations (`anki_core`)

Envelope: `{opId: uuid, clientId: uuid, issuedAt: ts (informational only), type, ...}`.

| Op | Payload | Reducer semantics |
|----|---------|-------------------|
| `DeckCreated` | deckId, name | No-op if deck exists or is deleted |
| `DeckRenamed` | deckId, name | Set name (server order decides concurrent renames) |
| `DeckDeleted` | deckId | Terminal. Cards become removed |
| `CardAdded` | cardId, deckId, front, back | No-op if card exists/removed or deck missing/deleted |
| `CardEdited` | cardId, front, back | Set fields; no-op on removed card |
| `CardRemoved` | cardId | Terminal |
| `CardReviewed` | cardId, rating, reviewedAt | Insert into card's review set keyed by `opId`; scheduling re-derived (3.2). Review kept for stats even if card is removed |

**Invariant: every op is idempotent under `reduce`** (`reduce(reduce(s, op), op) == reduce(s, op)`).
This is what makes resend-after-crash, snapshot + outbox overlap and at-least-once
delivery safe. Entity IDs are UUIDs and never reused, so "remove wins" is terminal
and needs no tombstone timestamps.

### 3.2 Scheduling is derived, not replicated

`card.scheduling = fold(FSRS.review, card.reviews sorted by (reviewedAt, opId))`.

- Reviews form a grow-only set → concurrent reviews from two devices both count; no LWW,
  no regression (fixes D3 for scheduling).
- Fast path: new review with `reviewedAt ≥ last` → one incremental step. Out-of-order
  arrival → refold that one card (typically < 50 reviews).
- Determinism hazard: `fsrs.Scheduler` fuzzing uses an unseeded `Random()`
  (`fsrs-2.0.1/lib/fsrs.dart:447`). Fold with fuzzing disabled and apply fuzz ourselves
  from `Random(hash(cardId, opId))`, or use `Scheduler.customRandom` (`@visibleForTesting`).
  Client and server must produce bit-identical results; covered by test.
- `Flashcard.scheduling` and `updatedAt` leave the wire format.

### 3.3 Protocol

`POST /api/v2/sync`
```json
→ {"clientId": "…", "since": 1041, "ops": [ {opId, type, …}, … ≤ 500 ]}
← 200 {"head": 1057, "ops": [ {"seq": 1042, "op": {…}}, … ≤ 2000 ], "more": false}
← 410 {"floor": 1500}          // since < compaction floor → fetch snapshot
```
Server transaction (per user):
1. `SELECT … FROM users WHERE email=@u FOR UPDATE` (serializes the user, as today).
2. For each op: `INSERT INTO ops … ON CONFLICT (user_email, op_id) DO NOTHING RETURNING`;
   if inserted → `seq = ++head_seq`, apply `reduce` to the touched entity rows.
3. `SELECT seq, body FROM ops WHERE user_email=@u AND seq > @since ORDER BY seq LIMIT 2000`.

Own ops are echoed back; the client uses their `opId`s as acks. `seq` is a per-user
integer counter under the row lock → dense, monotonic, clock-free (fixes D5).

`GET /api/v2/collection` → `{"seq": 1057, "decks": […], "cards": […], "reviews": […]}`
read under the same row lock (`FOR SHARE`) so `seq` matches the rows exactly. gzip.

### 3.4 Server storage

```sql
users       (email PK, head_seq bigint NOT NULL DEFAULT 0, floor_seq bigint NOT NULL DEFAULT 0)
ops         (user_email, seq bigint, op_id uuid, client_id uuid, body jsonb, received_at timestamptz,
             PRIMARY KEY (user_email, seq), UNIQUE (user_email, op_id))
decks       (user_email, id, name, deleted bool, seq bigint,        PRIMARY KEY (user_email, id))
cards       (user_email, id, deck_id, front, back, removed bool,
             scheduling jsonb, seq bigint,                          PRIMARY KEY (user_email, id))
reviews     (user_email, op_id uuid, card_id, deck_id, rating smallint, reviewed_at timestamptz,
             PRIMARY KEY (user_email, op_id))
```
Every op touches ≤ 1 deck + 1 card; the server loads that slice, runs the shared
`reduce`, writes it back. No reducer logic duplicated in SQL.

### 3.5 Client

```
CollectionStore (all access through one async lock)
  dispatch(op):  append outbox.jsonl (durable) → view = reduce(view, op) → emit
  sync:          lock: take outbox ops + since          (list of ops, not a timestamp)
                 unlock: POST /v2/sync                   (user keeps dispatching)
                 lock: base = reduce(base, serverOps); seq = head
                       outbox.removeWhere(opId ∈ serverOps)
                       view = reduce(base, outbox); persist base+seq+outbox; emit
  410 / new device: GET /v2/collection → base, then same rebase
```
- All mutations go through `dispatch`; `DecksNotifier` becomes a read-only projection
  of `view` (fixes D2: no stale snapshot can overwrite state).
- Pending = "in outbox", independent of any clock (fixes D4).
- Persistence: `sync/base/…` (existing per-deck JSON layout reused), `sync/outbox.jsonl`,
  `sync/state.json {clientId, seq}`. Writes ordered: outbox append before emit; base+seq
  before outbox truncation (crash ⇒ resend ⇒ server dedupes).
- Debounce/loop from `SyncService`/`SyncBootstrap` stays; loop while `more == true`.

### 3.6 Bootstrap and seeding (fixes D1)

- Seed IDs become deterministic: `uuidV5(ns, deckName)` / `uuidV5(ns, deckName + front)`.
  `DeckCreated`/`CardAdded` with an existing ID are no-ops → N devices seeding converge to one copy.
- Sync enabled on a device with local v1 data: convert local decks/cards/reviews into ops
  (`DeckCreated`, `CardAdded`, `CardReviewed` from `reviews.jsonl` with deterministic opIds
  `uuidV5(cardId@reviewedAt)` so v1 duplicates collapse) and push.
- Fresh device: snapshot first; seed only if snapshot is empty.

### 3.7 Error handling

| Failure | Behaviour |
|---------|-----------|
| Network error / 5xx | Outbox untouched; exponential backoff (1.5 s → 5 min) |
| Crash after server commit, before client persists | Resend; `ON CONFLICT (op_id)` dedupes; idempotent reduce |
| `since < floor_seq` | 410 → snapshot → rebase outbox → resend |
| Op invalid for current state (edit removed card) | Accepted, logged, reduces to no-op on every replica — never rejected, so outbox never wedges |
| Malformed op | 400 for the batch; client quarantines the op to `sync/rejected.jsonl` and continues |
| Client on v1 protocol | 410 on `/api/v1/sync` with upgrade message |

## 4. Scale and reliability

- 150k ops/year × ~250 B ≈ 40 MB/user/year in `ops`. Compaction: delete ops older
  than 90 days, set `floor_seq`; reviews survive in `reviews`. Offline > 90 days ⇒ snapshot.
- Snapshot for 50k cards ≈ 8–12 MB JSON, ≈ 1–2 MB gzip. Paginate only if this grows 10×.
- Per-user row lock serializes one user's devices only; users are independent.
- Monitoring: `/healthz` (existing); log per sync `{pushed, deduped, pulled, head, ms}`;
  client surfaces outbox length and last error in the sync status.

## 5. Trade-offs

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Keep v1, patch D1–D6 | Small diff | Clock-based LWW is inherent; D3 unfixable without logical clocks per field | Rejected |
| Full CRDT (Automerge/Yjs, HLC per field) | Peer-to-peer, no server authority | Heavy dependency, tombstone/GC complexity, opaque debugging; unnecessary with a central server | Rejected |
| **Server-ordered op log + snapshot** | Clock-free correctness, small payloads, auditable log, shared reducer testable as a pure function | Requires server for ordering (already true); concurrent text edits resolve by arrival order, not intent | **Chosen** |
| Snapshot-only (pull whole collection, push ops) | Simplest client | 1–2 MB per sync; battery/bandwidth | Fallback path only |

## 6. Verification

- `anki_core` property test: K simulated clients, random ops, random interleavings of
  sync/offline/crash-before-ack/410 → after quiescence all `view`s == server snapshot ==
  `reduce(∅, ops by seq)`.
- Reducer laws: idempotence per op type; FSRS fold determinism (client vs server, fuzz on).
- Store contract (`server/test/store_contract.dart`) re-targeted to v2, run against Memory and Postgres.
- Regression tests for D1 (two devices seed → one copy) and D2 (dispatch during rebase).

## 7. Rollout

1. `anki_core`: `Op`, `Collection`, `reduce`, deterministic FSRS fold, property tests.
2. Server: v2 schema migration; migrate v1 `decks`/`reviews` rows into materialized tables,
   `head_seq = floor_seq = 1` (all clients start with a snapshot); v2 endpoints; v1 → 410.
3. Client: `CollectionStore` + outbox; `DecksNotifier` mutations → `dispatch`; v2 `SyncService`;
   local v1 → ops migration; deterministic seed IDs.
4. Delete v1 code (`merge.dart`, `SyncRequest/Response`, `MemorySyncServer`, `removedCards`).

Existing duplicate seed decks from D1 are not auto-merged (different random IDs);
a one-off "merge duplicate decks by name" tool is optional.

## 8. Revisit as it grows

- Live updates: SSE/long-poll on `head` instead of 5-min polling.
- Deck sharing/multi-user: per-deck ACL and per-deck seq streams.
- Field-level merge for concurrent text edits if arrival-order wins proves annoying.
- Snapshot pagination/ETag once collections exceed ~100k cards.
