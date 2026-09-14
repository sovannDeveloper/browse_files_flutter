# browse_files_flutter

A Flutter plugin that presents a **Telegram-style attachment bottom sheet**: select photos &
videos, select files, or take a photo / record a video — from a short menu
(`OCBrowseFiles.showActions`), a draggable sheet with a numbered selection grid
(`OCBrowseFiles.show`), or a full-screen browser (`OCBrowseFiles.showPage`).

The reference UX is Telegram's attach menu — match its behaviour when a detail is unspecified.
Every public name is prefixed `OC`.

## Status

**Permissionless by design, both platforms live.** There is no library enumeration any more:
media come from the system picker (`ACTION_PICK_IMAGES` on Android 13+, `ACTION_GET_CONTENT`
below, `PHPickerViewController` on iOS), documents from SAF / `UIDocumentPickerViewController`,
captures from the system camera app writing into the app cache. The plugin declares **no**
`READ_MEDIA_*`, `READ_EXTERNAL_STORAGE` or `CAMERA` permission — keep it that way; adding
`CAMERA` to a manifest makes the capture intent start requiring it.

Channel methods, all implemented on Android and iOS: `pickMedia`, `captureMedia`,
`loadThumbnail`, `resolveFile`, `pickDocuments`.

## Commands

```bash
flutter pub get
flutter analyze                 # must be clean before declaring work done
dart format .
flutter test                    # unit tests + method-channel tests
cd example && flutter run       # manual verification on a real device
```

The pickers and the camera **only exist on a device** (the simulator has no camera and an empty
library) — say so rather than claiming a native change works when only `flutter test` and a
build ran. `test/cache_isolation_test.dart` hits the real channel and hangs for 10 minutes;
skip it when iterating.

## Layout

Follows the sibling packages (`../nfc_flutter`, `../get_phone`):

```
lib/browse_files_flutter.dart          # the ONLY public barrel; nothing else re-exports lib/src/**
lib/src/browse_files_flutter_platform_interface.dart  # PlatformInterface (plugin_platform_interface)
lib/src/browse_files_flutter_method_channel.dart      # default MethodChannel impl
lib/src/models/                        # media_item, media_type, document_item, options, strings, result, action, tab, exception
lib/src/ui/                            # sheet, actions menu, page, grid, tiles, tab bar — talk to the platform interface only
example/lib/main.dart                  # harness: the menu, the sheet, the page, and each platform call
android/src/main/kotlin/com/kedtec/browse_files_flutter/BrowseFilesFlutterPlugin.kt   # channel + intents
android/src/main/kotlin/com/kedtec/browse_files_flutter/MediaStoreReader.kt           # describe/thumbnail/copy for content and file URIs
android/src/main/kotlin/com/kedtec/browse_files_flutter/BrowseFilesFileProvider.kt    # the camera's output target
ios/Classes/BrowseFilesFlutterPlugin.swift   # channel + pickers + camera
ios/Classes/MediaFiles.swift                 # cache copies, describe, thumbnails
test/
```

Rules:
- UI widgets in `lib/src/ui/` talk to the platform **only** through the platform interface, so the
  sheet can be widget-tested with a fake platform.
- Models are immutable, with explicit `fromMap`/`toMap` — the channel payload shape lives in the
  model, not scattered through the plugin class.
- Public API surface is small: `OCBrowseFilesFlutter.instance` forwards to the platform
  interface; `OCBrowseFiles.showActions/show/showPage` all return `OCBrowseFilesResult?` (`null`
  on dismiss). Resist growing top-level entry points.
- The channel is `com.kedtec.browse_files_flutter/methods`. Native errors come back as
  `code`/`message`/`details` where `code` is a `BrowseFilesErrorCode` name; anything else is
  flattened to `unknown`, and a `notImplemented` reply becomes `unimplemented`.
- Argument validation (`ArgumentError`) happens **before** the channel call, outside `_guard` —
  a programmer error must not come back disguised as a `BrowseFilesException`.

## Platform notes (the parts that bite)

**Ids are opaque, not paths.** Android `pickMedia` returns Photo Picker content URIs; Android
captures are `file://` URIs into `cacheDir/browse_files`; every iOS id is a cached path. Anything
handed to the app is either a resolved cached path or an id it re-resolves through the plugin.

**Thumbnails.** Android: `ContentResolver.loadThumbnail` for content URIs (API 29+),
`ThumbnailUtils` / `MediaMetadataRetriever` for cache files. iOS: ImageIO's thumbnailer for
photos, `AVAssetImageGenerator` for clips. Decode off the platform main thread, return JPEG bytes,
keep the bounded LRU (`OCThumbnailCache`) on the Dart side keyed by id + size. Never cache
full-size images.

**Camera.** Android: `ACTION_IMAGE_CAPTURE` / `ACTION_VIDEO_CAPTURE` with `EXTRA_OUTPUT` from
`BrowseFilesFileProvider` (authority `<applicationId>.browse_files_flutter.provider`, declared in
the plugin manifest; a subclass so host apps' own FileProviders merge). Some camera apps ignore
`EXTRA_OUTPUT` for video and return `data.data` — that is copied into the target. There is no
combined photo+video intent, so the UI asks first when both kinds are allowed. iOS:
`UIImagePickerController` with `.camera`; the plugin refuses with `unsupported` when
`NSCameraUsageDescription` (or `NSMicrophoneUsageDescription` for video) is missing, because
iOS would otherwise kill the app; a refused camera is `permissionDenied`.

**Documents use system pickers**, not a custom browser: Android `ACTION_OPEN_DOCUMENT` (SAF),
iOS `UIDocumentPickerViewController`. Picked files are copied into the app cache and returned as
paths — SAF URIs and security-scoped URLs are not valid file paths. Cache copies never
overwrite: a second file of the same name lands as `name (1).ext`.

**Permissions.** None are requested. The Photo Picker, SAF and the camera intent need none on
Android; PHPicker and the document picker run out of process on iOS. Do not reintroduce
`READ_MEDIA_*` / `NSPhotoLibraryUsageDescription` flows.

## Sheet UI reference

Matching the Telegram attach sheet:
- Draggable sheet with snap points (peek ≈ half screen → full), drag handle, dimmed scrim,
  dismiss on scrim tap and on drag-down.
- 3-column media grid, newest first. Videos show a play glyph + duration badge (`1:32:48`) at the
  bottom-left; every tile has a circular selection control at the top-right that fills with the
  selection order when picked.
- First cell is the camera tile, two rows tall. Telegram's is a live preview — **out of scope**;
  ours opens the system camera (photo/video choice when both are allowed) and the shot lands in
  the selection. `onCameraTap` swaps in the host app's camera, `showCamera: false` hides it.
- Bottom row of attachment tabs, horizontally scrollable, active tab highlighted:
  Gallery · File · Location · Article · Poll · Contact. Only **Gallery** and **File** ship in this
  package; the rest are extension points the host app fills in (custom tab + builder), not features
  we implement here.
- Selection is ordered and capped by an option (`maxSelection`); the confirm/send affordance shows
  the count.
- `showActions` is the short form: take photo · record video · select photos & videos · select
  files. It pops before the system UI opens; a backed-out picker is `OCBrowseFilesResult.empty`,
  a dismissed menu is `null`, a platform error is thrown.

## Conventions

- Dart SDK `^3.10.8`, Flutter `>=3.10.0`, `flutter_lints ^6.0.0`, `plugin_platform_interface ^2.0.2`.
- Android package `com.kedtec.browse_files_flutter`, plugin class `BrowseFilesFlutterPlugin`
  (Kotlin), minSdk 24; iOS `BrowseFilesFlutterPlugin` (Swift), iOS 13+.
- Deleting or adding iOS source files needs `pod install` in `example/ios` before the example
  builds again — the Pods project lists them by name.
- Errors cross the channel as a typed exception model (see `nfc_flutter`'s `NfcException`), never
  as bare `PlatformException` strings leaking to callers.
- Keep `CHANGELOG.md` and the `version:` in `pubspec.yaml` in step when behaviour changes.
- No third-party gallery/picker dependency — native enumeration is the point of this package.
