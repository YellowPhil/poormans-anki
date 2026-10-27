# Poormans Anki

Local-first spaced-repetition flashcards. One codebase, three surfaces: a sidebar layout on desktop, a tab-bar layout on phones, and a web build that picks whichever fits the viewport.

Scheduling uses [FSRS](https://github.com/open-spaced-repetition) via the `fsrs` package. Cards are Markdown. Decks and the review log are plain files, so the data stays readable without the app.

## Features

- Inbox review across all decks or a single deck, with `space` to reveal and `1`–`4` to rate
- Deck grid with search, card detail, inline edit and remove
- Dashboard with review statistics
- Desktop: sidebar, `⌘K` search, `N` new card, `⌘1`/`⌘2`/`⌘3…` to jump between dashboard, inbox and decks (`Ctrl` on Linux, Windows and in browsers)
- Phone: bottom tab bar, drawer sidebar, tap-to-reveal card with four rating buttons
- Storage: JSON files in the platform's application-support directory; `localStorage` on the web
- Optional sync across devices through the bundled server (see below)

## Run

```sh
flutter pub get
flutter run -d macos      # or: -d chrome, -d <ios device id>
```

Web release build:

```sh
flutter build web --release
python3 -m http.server 8000 -d build/web
```

## Sync

Every device keeps a full local copy and syncs on launch, on resume, every five minutes, and about 1.5 s after each edit. Edits are recorded as operations (deck created or renamed, card added, edited, removed or reviewed) and appended to a local outbox before they show in the UI, so nothing is lost offline or across restarts. The server gives every accepted operation the next number in a per-user log and de-duplicates resends by operation id; devices pull the log from their last position and fold it with the same reducer the server uses. Order on the server, not device clocks, decides concurrent edits; removals are final; every review is kept and the FSRS schedule is recomputed from the full review history, so all devices show the same due dates. A device that is new, was offline past a server compaction, or switches server downloads the whole collection once. Design: `docs/sync-v2-design.md`.

Sync is configured from the **Sync** item at the bottom of the sidebar (server URL, and an email for development). The web build is served by the same server and syncs against its own origin out of the box.

**Identity.** The server does not authenticate. It trusts the `Remote-Email` header (configurable via `USER_HEADER`) and expects an authenticating reverse proxy in front of it, such as oauth2-proxy, Cloudflare Access or Pomerium, that sets the header after login and strips any client-supplied value. Never expose the server without such a proxy. During development the app can send the header itself: fill in the email field in the Sync dialog.

## Server

`server/` is a Dart `shelf` service backed by Postgres: an `ops` log plus materialized `decks`, `cards` and `reviews` tables. Migrations run at start-up; v1 data is imported into the v2 tables.

| Endpoint | Purpose |
| --- | --- |
| `GET /healthz` | Liveness and database check, public |
| `GET /api/v1/me` | Echo the identity the proxy supplied |
| `POST /api/v2/sync` | Push up to 500 ops after `since`; returns `head`, `acked` op ids and up to 2000 ops after `since` (`more` when truncated). `410 {floor}` when `since` was compacted |
| `GET /api/v2/collection` | The whole collection at `seq` |
| `/api/v1/sync` | `410`: retired protocol |

Environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `DATABASE_URL` | `memory` | `postgres://user:pass@host:5432/db?sslmode=disable`, or `memory` for an in-process store |
| `PORT` | `8080` | Listen port |
| `USER_HEADER` | `Remote-Email` | Header carrying the user's email |
| `WEB_ROOT` | unset | Directory with a `flutter build web` output to serve at `/` |
| `CORS_ORIGIN` | unset | Allow a separate web origin; unnecessary when `WEB_ROOT` serves the app |
| `MAX_BODY_BYTES` | 32 MiB | Request body limit |
| `LOG_LEVEL` | `INFO` | `logging` level name |

Run locally without Postgres:

```sh
cd server && dart run bin/server.dart
curl -H 'Remote-Email: you@example.com' localhost:8080/api/v1/me
```

Tests (the Postgres contract test runs when `TEST_DATABASE_URL` is set; the app's `test/sync/end_to_end_test.dart` honours the same variable and wipes that database's `public` schema):

```sh
cd server
TEST_DATABASE_URL=postgres://postgres:pw@localhost:5432/anki?sslmode=disable dart test
```

## Deploy

The Dockerfile builds the web app and the server and ships both in one image from `scratch` (server binary plus the Dart runtime libraries; the web build is served from `/web`).

```sh
POSTGRES_PASSWORD=change-me docker compose up -d --build
curl localhost:8080/healthz
```

Put the authenticating proxy in front of port 8080. Native apps point their Sync settings at the proxy's public URL and sign in through it; the proxy must forward the `Remote-Email` header on API requests.

## Layout

```
packages/anki_core/   Shared pure-Dart package: Deck, Flashcard, Rating, ReviewEntry,
                      sync ops, Collection reducer, FSRS fold, reference sync server
server/               shelf API, Postgres and in-memory stores, Dockerfile entrypoint
lib/
  data/         CollectionStore (base + outbox over a FileStore), v1 import, seeds
  storage/      FileStore implementations: local files, localStorage, in-memory
  sync/         settings, HTTP client, SyncService (push outbox, pull log)
  state/        Riverpod notifiers and providers
  features/     shell, inbox, deck, add, search, statistics, sync
  theme/        dark warm-monochrome theme
```

## Test

```sh
flutter analyze && flutter test
(cd packages/anki_core && dart test)
(cd server && dart test)
```
