# RankIt — Product & Technical Spec

## What this app is

A movie diary and tracking app, structured like Letterboxd (log what you watch,
write reviews, see friends' activity), but ratings work like Beli: instead of a
star rating, you rank a movie against movies you've already logged via
head-to-head comparisons. Over time this produces a precise, constantly
refined, fully-ordered list of every movie you've seen — no ties, no mushy
4-star pileups.

It also includes a "Discover" reels-style feed for browsing movies you
haven't seen yet via official trailers (see legal constraints below —
this is trailers only, never re-hosted scene clips).

## Tech stack

- SwiftUI, iOS 17+ deployment target
- SwiftData for local persistence
- MVVM: Models/, Views/, ViewModels/, Services/, Resources/
- TMDb API for all movie metadata, search, trending, and trailer video keys
- YouTube embed (WKWebView or a YouTube player SPM package) for trailer
  playback in Discover — never AVPlayer with a direct video file, since we
  don't host any video ourselves

## Core mechanic: tiered binary insertion ranking

This is the most important part of the app and should be built as a
standalone, unit-testable `RankingEngine` type, fully decoupled from any UI.

Flow when a user logs a movie:

1. **Tier selection** — user picks one of three tiers first:
   - 🟢 Loved
   - 🟡 Liked
   - 🔴 Disliked
2. **Binary search within that tier only** — the engine picks the middle-ranked
   movie in that tier and asks "this or [new movie] — which did you like more?"
   Based on the answer, it recurses into the upper or lower half of that tier's
   list, repeating until the new movie's exact slot is found.
3. The new movie is inserted at that precise `rank_position` within its tier.

Rules:
- Comparisons only happen within a tier — never ask a user to compare a movie
  they loved to one they disliked, that comparison is meaningless and annoying.
- For N previously-ranked movies in a tier, this takes ~log2(N) comparisons.
- The engine must be pure/testable: given a list of ranked items and a stream
  of "A vs B" answers, it deterministically produces the correct insertion
  index. Write unit tests for this before wiring up any UI.
- Support an "undo last comparison" action — users will misclick.

## Data model (SwiftData)

**User**
- id, username, displayName, avatarURL, bio, joinedDate

**Movie** (cached TMDb data, not authored content)
- tmdbID, title, year, posterURL, runtimeMinutes, director, genres

**LoggedMovie** (core object — one per user per watch)
- id, userID, movieID (→ tmdbID)
- watchedDate
- tier: enum { loved, liked, disliked }
- rankPosition: Int (unique per user+tier — maintained by RankingEngine)
- isRewatch: Bool
- reviewText: String?
- isLiked: Bool (separate heart, independent of tier/rank)
- containsSpoilers: Bool

**ComparisonEvent** (for undo + analytics)
- id, userID, movieAID, movieBID, winnerID, timestamp

**Watchlist**
- userID, movieID, addedDate

**Follow**
- followerID, followeeID

**ActivityFeedItem** (denormalized for feed performance)
- userID, type: enum { logged, reviewed, followed }, refID, timestamp

**Trailer** (cached reference only, never hosted video)
- movieID (→ tmdbID)
- youtubeKey (from TMDb `videos` endpoint)
- type: enum { trailer, teaser }
- official: Bool — only ever surface entries where this is true

**DiscoverInteraction**
- id, userID, movieID, action: enum { watchlisted, skipped, logged }, timestamp
- Used to avoid resurfacing skipped movies; skip twice → deprioritize heavily

## Screens

1. **Feed** — friends' recent logs/reviews, Letterboxd-style
2. **Discover (Reels)** — full-screen vertical swipe of official trailers for
   movies the user hasn't logged yet
   - Swipe up → next trailer
   - Swipe right / double-tap → add to Watchlist
   - Swipe left → skip, record DiscoverInteraction
   - "I've seen this" button → jumps straight into Log flow (tier picker)
   - Autoplay muted by default, tap for sound
   - Source: TMDb `videos` endpoint filtered to `official: true`,
     `type: Trailer` or `Teaser`, embedded via the cached `youtubeKey`
   - Exclude movies already in the user's LoggedMovie table
   - Weight toward genres the user ranks highly + TMDb trending
3. **Search / Add movie** — TMDb search, tap result to start Log flow
4. **Log flow** — tier picker → binary comparison sequence
5. **Profile** — full ranked list, stats (total watched, by year, by genre),
   poster grid
6. **Movie detail page** — synopsis, user's tier/rank, friends' ranks
7. **Ranked list view** — full scrollable ranked list, filterable by
   year/genre/tier
8. **Watchlist**

## Legal / content constraints (must follow exactly)

- **Never re-host, download, cache, or serve actual movie video/audio.**
  Everything video-related is an embed pointing at an official YouTube upload,
  sourced only via TMDb's `videos` endpoint with `official: true`.
- Do not build any feature that lets users upload or share movie clips —
  that shifts liability onto us and is a common source of DMCA takedowns.
- Movie metadata (title, poster, synopsis, cast, genres) comes from TMDb's
  licensed API, not scraped from other sites.
- App name, icon, and UI must be original — no Letterboxd or Beli branding,
  color schemes, or logos.

## Build order (recommended sequence for Claude Code sessions)

1. SwiftData models (Movie, LoggedMovie, User, Trailer, DiscoverInteraction, etc.)
2. TMDbClient service (search, movie details, trending, videos endpoint) —
   API key read from a gitignored config, never hardcoded
3. RankingEngine (standalone, unit tested)
4. Log flow UI wired to RankingEngine
5. Discover/Reels screen (YouTube embed player)
6. Feed, Profile, Watchlist, Movie detail (mostly CRUD against SwiftData)

## Open questions to resolve during build

- Which YouTube embed approach: WKWebView with the iframe player API, or a
  SPM package like youtube-ios-player-helper? Evaluate both for reliability
  and App Store review risk before committing.
- Final app name/branding (must be clearly distinct from both source apps)
- Social graph model: public profiles, follow requests, or fully open?
