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

## Layout

```
lib/
  domain/       Deck, Flashcard, Rating, ReviewEntry
  scheduler/    FSRS wrapper
  data/         DeckRepository over a FileStore, seed decks
  storage/      FileStore implementations: local files, localStorage, in-memory
  state/        Riverpod notifiers and providers
  features/     shell, inbox, deck, add, search, statistics
  theme/        dark warm-monochrome theme
```

## Test

```sh
flutter analyze
flutter test
```
