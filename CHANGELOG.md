## 0.1.3

* `OCBrowseFiles.showActions`: the photo and video rows now honour
  `OCBrowseFilesOptions.onCameraTap` like the sheet's camera tile does — the host camera
  runs after the menu closes and the call resolves to `OCBrowseFilesResult.empty`. They used
  to open the system camera regardless of the callback.

## 0.1.2

* `requestCameraPermission(type:)`: checks — and prompts for — camera access without opening
  the camera, answering an `OCCameraPermission` (`granted`, `denied`, `permanentlyDenied`).
  The sheet's camera tile and the `showActions` photo/video rows call it before
  `captureMedia`, so a refused camera is the `cameraPermissionDenied` string in the sheet
  (or a `permissionDenied` exception from the menu) rather than a dead tap.
* Android: a host app that declares `CAMERA` in its own manifest makes the capture intent
  require it; `captureMedia` now prompts for it in that case instead of failing with
  `permissionDenied` straight away. The plugin still declares no permission of its own, and
  without the host declaration nothing is asked.
* iOS: recording a video also prompts for the microphone ahead of the picker; a refused
  microphone does not block the capture.

## 0.1.1

* Android 13+: the Photo Picker allows more than one item again. Multi-select was requested
  through an extra the picker does not know; it now sends `EXTRA_PICK_IMAGES_MAX`. A single
  media kind is filtered through the intent `type`, which Android 13's picker honours where it
  ignored `EXTRA_MIME_TYPES`.
* Android: picked videos carry their duration, so the tile badge no longer reads `0:00`. Item
  metadata is read in one best-effort query — a provider without a width or date column no
  longer drops the item from the result.
* Android: cache copies never overwrite; a second file of the same name lands as `name (1).ext`,
  as on iOS and as documented. A copy that fails midway is deleted rather than handed back.
* Android below 10, and any provider without thumbnails of its own: thumbnails are decoded
  sub-sampled to the tile and turned upright, instead of the whole photo being inflated in
  memory; videos get a frame.
* iOS: `PHPicker` hands over the file as it is (`.current`) rather than transcoding a long clip
  first.
* The sheet's File tab opens the document picker in single-pick mode when `maxSelection` is
  `1`, as the gallery already did.

## 0.1.0

* `captureMedia(type:)`: the system camera, for a photo or a video. Android runs
  `ACTION_IMAGE_CAPTURE` / `ACTION_VIDEO_CAPTURE` into the app cache through a `FileProvider`
  the plugin declares itself; iOS runs `UIImagePickerController` with the camera source. No
  `CAMERA` or storage permission is declared — iOS only needs `NSCameraUsageDescription` (and
  `NSMicrophoneUsageDescription` for video), which the plugin checks for before opening the
  camera rather than letting iOS kill the app. The capture comes back as an `OCMediaItem`
  whose id is already a file, or `null` when the user backed out.
* `OCBrowseFiles.showActions`: a short menu — take photo · record video · select photos &
  videos · select files. The menu closes before the camera or picker opens and resolves to the
  same `OCBrowseFilesResult` as the sheet. `OCBrowseFilesAction` names the rows.
* The sheet's camera cell now opens the built-in camera by default (a photo/video choice when
  both kinds are allowed) and the shot lands in the selection. `onCameraTap` still replaces it
  with the host app's camera; the new `showCamera: false` hides it.
* iOS caught up with the permissionless design: `pickMedia` is `PHPickerViewController`
  (iOS 14+, `UIImagePickerController` on iOS 13), picks are copied into the cache and their
  ids are paths, and the dead `permissionStatus` / `fetchMedia` / `fetchDocuments` handlers
  are gone. Cache copies no longer overwrite an earlier file of the same name.
* New strings: `actionsTitle`, `takePhotoLabel`, `recordVideoLabel`, `selectMediaLabel`,
  `selectFilesLabel`, `cameraErrorTitle`.
* The example app drops its own camera channel and drives the menu, the sheet and
  `captureMedia` directly.

## 0.0.1

* Initial scaffold: plugin skeleton, method channel wiring and example app.
* Dart API: media models, platform interface, method-channel implementation and the
  `BrowseFilesFlutter` facade. Native implementations are still stubs.
* Native permission handling on Android and iOS: `permissionStatus`, `requestPermission`,
  `presentLimitedPicker` and `openSettings` are live, including the partial grant
  (`READ_MEDIA_VISUAL_USER_SELECTED` / `PHAuthorizationStatus.limited`). Enumeration,
  thumbnails, `resolveFile` and `pickDocuments` are still stubs.
* Example app: a permission panel that reports the current access level and drives those
  four calls, re-checking the level whenever the app resumes, plus the Android and iOS
  permission declarations the prompt needs.
* The attachment sheet: `BrowseFiles.show(context, options)` opens a draggable, dismissible
  bottom sheet with a paged 3-column media grid, ordered selection capped by `maxSelection`,
  video duration badges, per-tile thumbnails through a bounded LRU cache, a permission panel
  covering the limited grant, and the Gallery/File tab row. Other tabs are host-app
  extension points (`AttachmentTab.custom`).
* Native media enumeration: `fetchAlbums`, `fetchMedia`, `loadThumbnail`, `resolveFile` and
  `pickDocuments` on both platforms — MediaStore paged with LIMIT/OFFSET on Android,
  `PHFetchResult` windows on iOS, both off the main thread, with SAF and
  `UIDocumentPickerViewController` behind the File tab.
* Telegram's sheet chrome: the camera cell leads the grid two rows tall (a custom
  `SliverGridDelegate`, no staggered-grid dependency), unselected tiles carry an empty white
  ring, video badges are a play glyph and time with a drop shadow rather than a pill, and the
  tab row is a floating bar with the open tab in a tinted pill.
* `AttachmentTab.location`, `.article`, `.poll` and `.contact` presets carry Telegram's labels
  and icons for tabs the host app still builds itself, and any tab can carry a `badge`.
* `BrowseFilesOptions.backgroundColor` and `accentColor` recolour the sheet — including its
  labels and tab bar — without touching the app's own theme.
* The live camera preview tile stays out of scope: the camera cell appears only when
  `BrowseFilesOptions.onCameraTap` is supplied, and the host app opens its own camera. The
  example app shows what that looks like — a channel of its own onto ACTION_IMAGE_CAPTURE and
  `UIImagePickerController`, saving the shot into the library so it comes back as an ordinary
  asset id.
* The grid re-reads the first page when the app resumes, so a photo taken while the sheet was
  in the background shows up; an unchanged library leaves the grid and the selection alone.
* `BrowseFiles.showPage` opens a full-screen browser split by kind: photos and videos in one
  tab, every other file in the next, one selection cap across both, and the same
  `BrowseFilesResult` the sheet returns. Documents still held as platform handles are resolved
  to paths on confirm.
* `fetchDocuments` on both platforms, with `DocumentItem` / `DocumentPage`. It lists what the
  OS actually allows: `MediaStore` rows that are neither image nor video on Android, this app's
  own storage on iOS. `DocumentPage.enumerable` reports when a device-wide listing is
  impossible — Android 11+ scoped storage and iOS always — and the Files tab says so and puts
  the system picker one tap away instead of showing an empty list.
* `documentMimeTypes` accepts family wildcards: `image/*` and `video/*` become LIKE clauses on
  Android and prefix matches plus `UTType` supertypes on iOS, and `*/*` means no filter.
* `BrowseFiles.show` and `showPage` assert when handed a context with no Navigator above it —
  the trap a `State` that builds `MaterialApp` itself falls into — and say what to do instead.
  The example app was doing exactly that; its screen now sits below `MaterialApp`, with tests
  that open both entry points.
* Thumbnails arrive far sooner. Android ran every library call on one thread, so each tile
  waited behind every tile before it — and behind any `resolveFile` copy that got queued
  first; library reads now share a small pool. iOS asked for `.highQualityFormat` with iCloud
  access allowed, which decodes the original (or waits on the network) per tile: a grid cell
  gets `.fastFormat` off the local rendition instead, and the JPEG encode moved off the main
  thread, where `requestImage` had been calling back. The grid also builds a couple of rows
  past the viewport so their thumbnails are requested before they scroll in.
* Paging is fifty at a time everywhere (`BrowseFilesOptions.pageSize`, the platform-interface
  `limit` and both native defaults), and both the grid and the Files tab end in a spinner cell
  while the next page is being read, so a big library says it is still loading instead of
  looking finished. A page whose rows overlap one already shown — what a library that grows
  mid-scroll hands back — is deduplicated by id rather than throwing on the grid's keys, and a
  short page ends the paging whatever total the platform reported.
* Android counted the whole selection again for every page whenever the provider did not
  volunteer `EXTRA_TOTAL_COUNT` (which is every query below Android R): one scan per page while
  scrolling a large library. The count is now taken at the start of a browse and reused by the
  pages after it.
* A page's thumbnails are requested the moment the page arrives, rather than when each tile is
  first built (`ThumbnailCache.prefetch`). On a first open the OS has no thumbnail cached for
  any asset and has to generate one apiece — for a long video that is a seek and a decode — so
  the head start is most of the wait; the Android read pool is wider for the same reason.
* A tile that the platform answered about with no thumbnail now says so, instead of staying
  blank forever: blank means the request is still out, a glyph means there is nothing to show.
* Android returned an empty byte array instead of a thumbnail whenever the bitmap it got back
  was a hardware bitmap, whose pixels this process cannot read: `Bitmap.compress` fails on one
  and says so only through a return value nobody checked. Empty bytes cross the channel as
  bytes, so the tile painted nothing and reported no error — a blank cell with no way to tell
  it from one still loading. The bitmap is copied into readable memory first, the encode result
  is checked, and an empty result is now `null` (which the tile marks as "no thumbnail").
* The example harness gained a "Probe thumbnail" button: it asks for one asset's thumbnail and
  reports the byte count and how long it took, or the error — the way to tell a slow platform
  from a broken one without reading the grid's mind.
* The Files tab leads with an "Internal Storage / Browse your file system" row that opens the
  system picker, and lists what the platform can enumerate under a "Recent files" heading —
  the storage entry the user expects rather than a header with a Browse button beside it.
* The Gallery tab gained a group selector: a top bar naming the open album and its item count,
  with a menu of the albums `fetchAlbums` reports. Picking one repages the grid from that
  album (`fetchMedia(albumId:)`, which the grid had never passed). The bar stays hidden when
  the platform reports a single album, and a platform that cannot list albums quietly gets no
  bar instead of an error panel. Each entry in the menu carries its album's cover thumbnail —
  the `coverId` both platforms already reported and nothing drew — through the same bounded
  cache the tiles use.
* Every string the sheet draws is now overridable: `OCBrowseFilesOptions.strings` takes an
  `OCBrowseFilesStrings`, which carries each label, heading and empty-state line, plus three
  builders for the text that has numbers in it (`confirmButton`, `selectionSummary`,
  `albumItemCount`). Anything left out keeps the English default, so a host app that only
  wants to translate the confirm button says so and nothing else. The bottom row's captions
  stay on the tabs themselves — `OCAttachmentTab.gallery.withLabel('Galerie')` renames a
  built-in tab without changing its id, so this package still draws its body.
* `OCBrowseFilesOptions.confirmLabel` and `BrowseFiles.showPage(title:)` are now nullable and
  default to the matching string; passing one still wins, so existing calls are unaffected.
