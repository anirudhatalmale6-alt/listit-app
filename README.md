# Listit App

The Isle of Man marketplace, as a native mobile app. Built with Flutter, powered
by the same live Listit API that runs [listit.im](https://listit.im).

## What's in Phase 1

This is the first slice - the discovery experience end to end, running against
real listings:

- **Home / category chooser** - a "Start discovering" call-to-action into the
  swipe deck, plus every marketplace section (Property, Cars & Motors, ...) as a
  tappable grid with live listing counts.
- **Swipe deck** - the headline feature. Tinder-style cards you swipe right to
  show interest, left to pass, up to save. Big photo, price, title, location and
  seller badges (Dealer / Reduced / Under offer). Cards stream in a page at a
  time and prefetch before you run out. Tap-to-undo included.
- **Listing detail** - full photo gallery, price (with was-price when reduced),
  description, seller card with verified badge, and a Save / Message contact bar.

Contact, saving and accounts light up in Phase 2 (they're wired but gated on the
login work); AI helpers, notifications, admin and payments follow in Phase 3.

## Architecture

```
lib/
  config/api_config.dart     Every endpoint + image URL resolution in one place
  models/                    Category, Ad - defensive JSON parsing
  services/api_service.dart  Thin HTTP client over the live API envelope
  screens/                   home, swipe, ad_detail
  widgets/                   swipe_card, network_photo (cached images)
  utils/format.dart          Price (GBP) + relative-time helpers
  theme.dart                 Listit brand colours + Material 3 theme
```

The app talks to the production API by default. Point it elsewhere at build time:

```bash
flutter run --dart-define=API_HOST=https://staging-api.listit.im
```

## Running it

```bash
flutter pub get
flutter run                 # on a connected device or simulator
```

Requires Flutter 3.9+ (Dart 3.9+). Targets Android and iOS.

## Backend endpoints used (Phase 1)

| Purpose        | Method | Path                        |
|----------------|--------|-----------------------------|
| Category tree  | GET    | `/admin/category-new`       |
| Search feed    | POST   | `/api/user/search`          |
| Listing detail | GET    | `/api/user/ads/:id`         |

All wrap the standard `{ status, message, data }` envelope.
