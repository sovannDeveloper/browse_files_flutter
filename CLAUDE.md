# browse_files_flutter

A Flutter plugin that presents a **Telegram-style attachment bottom sheet**: a draggable sheet
over the current screen showing the device's photos and videos in a grid for multi-selection,
plus tabs for documents and other attachment kinds.

The reference UX is Telegram's attach menu — match its behaviour when a detail is unspecified.

## Status

**Dart API landed; native side is a stub.** `lib/` has the models, the platform interface, the
method-channel implementation and a facade (`BrowseFilesFlutter.instance`), all covered by tests.
Both native plugin classes register the channel and answer `notImplemented` to everything — the
method list they owe is in the TODO at the top of each file. The sheet UI does not exist yet.

So every call currently fails with `BrowseFilesErrorCode.unimplemented`; the example app is a
harness that shows that per method.

## Commands

```bash
flutter pub get
flutter analyze                 # must be clean before declaring work done
dart format .
flutter test                    # unit tests + method-channel tests
cd example && flutter run       # manual verification on a real device
```

The gallery grid, permissions and thumbnails **cannot be verified in a simulator/emulator with an
empty media library** — say so rather than claiming a UI change works when only `flutter test` ran.

## Layout

Follows the sibling packages (`../nfc_flutter`, `../get_phone`):

```
lib/browse_files_flutter.dart          # the ONLY public barrel; nothing else re-exports lib/src/**
lib/src/browse_files_flutter_platform_interface.dart  # PlatformInterface (plugin_platform_interface)
lib/src/browse_files_flutter_method_channel.dart      # default MethodChannel/EventChannel impl
lib/src/models/                        # media_item, media_album, media_page, media_type, media_permission, exception
lib/src/ui/                            # sheet, grid, tiles, tab bar — pure Dart, no channel calls (TODO)
example/lib/main.dart                  # harness: calls each platform method, shows the outcome
android/src/main/kotlin/com/kedtec/browse_files_flutter/BrowseFilesFlutterPlugin.kt
ios/Classes/BrowseFilesFlutterPlugin.swift
test/
```

Rules:
- UI widgets in `lib/src/ui/` talk to the platform **only** through the platform interface, so the
  sheet can be widget-tested with a fake platform.
- Models are immutable, with explicit `fromMap`/`toMap` — the channel payload shape lives in the
  model, not scattered through the plugin class.
- Public API surface is small: `BrowseFilesFlutter.instance` forwards to the platform interface,
  and the sheet will add roughly `show(context, options)` returning the selected `List<MediaItem>`
  (empty on dismiss). Resist growing top-level entry points.
- The channel is `com.kedtec.browse_files_flutter/methods`. Native errors come back as
  `code`/`message`/`details` where `code` is a `BrowseFilesErrorCode` name; anything else is
  flattened to `unknown`, and a `notImplemented` reply becomes `unimplemented`.
- Argument validation (`ArgumentError`) happens **before** the channel call, outside `_guard` —
  a programmer error must not come back disguised as a `BrowseFilesException`.

## Platform notes (the parts that bite)

**Enumeration must be native and paged.** Android: `ContentResolver` query over
`MediaStore.Files` filtered to `MEDIA_TYPE_IMAGE`/`MEDIA_TYPE_VIDEO`, sorted by `DATE_MODIFIED`.
iOS: `PHAsset.fetchAssets` with a `PHFetchOptions` sort. Never load the whole library into memory
or into a single channel reply — page it (offset/limit), and request thumbnails per visible tile.

**Thumbnails.** Android `ContentResolver.loadThumbnail` (API 29+); iOS `PHCachingImageManager`
with `deliveryMode = .opportunistic`. Decode off the platform main thread, return JPEG bytes, and
keep a bounded LRU cache on the Dart side keyed by asset id + requested size. Unbounded caching of
full-size images is the fastest way to OOM this plugin.

**Permissions are not binary — handle *limited* access.**
- Android 13+ (API 33): `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`; Android 14+ (API 34) adds
  `READ_MEDIA_VISUAL_USER_SELECTED` (partial grant) — the grid must then show only the shared
  subset plus an affordance to select more. Android ≤12: `READ_EXTERNAL_STORAGE`.
- iOS: `NSPhotoLibraryUsageDescription`; `PHAuthorizationStatus.limited` is a first-class state,
  not an error. Surface it as a distinct value in the permission model.

**Documents tab uses system pickers**, not a custom browser: Android `ACTION_OPEN_DOCUMENT` (SAF),
iOS `UIDocumentPickerViewController`. Copy the picked file into the app cache and return a path —
SAF URIs and iOS security-scoped URLs are not valid file paths.

**Content URIs / PHAsset ids are not file paths.** Anything handed back to the app must be either
a resolved cached file path or an explicit id the caller can re-resolve through the plugin.

## Sheet UI reference

Matching the Telegram attach sheet:
- Draggable sheet with snap points (peek ≈ half screen → full), drag handle, dimmed scrim,
  dismiss on scrim tap and on drag-down.
- 3-column media grid, newest first. Videos show a play glyph + duration badge (`1:32:48`) at the
  bottom-left; every tile has a circular selection control at the top-right that fills with the
  selection order when picked.
- First cell is a live camera preview tile that shoots straight into the selection.
  **Out of MVP scope** — leave a placeholder tile that opens the system camera, and note it.
- Bottom row of attachment tabs, horizontally scrollable, active tab highlighted:
  Gallery · File · Location · Article · Poll · Contact. Only **Gallery** and **File** ship in this
  package; the rest are extension points the host app fills in (custom tab + builder), not features
  we implement here.
- Selection is ordered and capped by an option (`maxSelection`); the confirm/send affordance shows
  the count.

## Conventions

- Dart SDK `^3.10.8`, Flutter `>=3.10.0`, `flutter_lints ^6.0.0`, `plugin_platform_interface ^2.0.2`.
- Android package `com.kedtec.browse_files_flutter`, plugin class `BrowseFilesFlutterPlugin`
  (Kotlin); iOS `BrowseFilesFlutterPlugin` (Swift).
- Errors cross the channel as a typed exception model (see `nfc_flutter`'s `NfcException`), never
  as bare `PlatformException` strings leaking to callers.
- Keep `CHANGELOG.md` and the `version:` in `pubspec.yaml` in step when behaviour changes.
- No third-party gallery/picker dependency — native enumeration is the point of this package.
