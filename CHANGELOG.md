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
