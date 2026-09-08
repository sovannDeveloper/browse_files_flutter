# browse_files_flutter

A Telegram-style attachment bottom sheet for Flutter — browse the device's photos, videos and
documents in a draggable sheet with ordered multi-selection.

Enumeration is native and paged (Android `MediaStore`, iOS `PHAsset`), with per-tile thumbnails
and no third-party gallery dependency.

## Install

The package is not on pub.dev (`publish_to: none`); depend on it by git or by path:

```yaml
dependencies:
  browse_files_flutter:
    git:
      url: https://github.com/kedtec/browse_files_flutter.git
```

## Platform setup

**Android** — declare the media permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<!-- Android 14+: the partial grant reported as MediaPermissionStatus.limited -->
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

**iOS** — add a purpose string to `ios/Runner/Info.plist`; without it the prompt crashes the app:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Browses your photos and videos so you can attach them.</string>
```

## Usage

### The sheet

One call, one result. `show` resolves to `null` when the user dismisses the sheet — by tapping the
scrim, dragging it down or pressing back.

```dart
import 'package:browse_files_flutter/browse_files_flutter.dart';

final result = await BrowseFiles.show(context);
if (result != null && result.isNotEmpty) {
  // Media are descriptions, not files: resolve the ones you actually need.
  for (final item in result.media) {
    final path = await BrowseFilesFlutter.instance.resolveFile(item.id);
    // ... upload or read `path`
  }
  // Documents were picked *as* files and are already cached paths.
  for (final path in result.documents) {
    // ... upload or read `path`
  }
}
```

`BrowseFiles.show` needs a context **below** a `Navigator`. A `State` that builds `MaterialApp`
itself sits above the one it creates — call from a widget inside `MaterialApp`, or wrap the call
site in a `Builder`.

### The full-screen browser

Same result, for browsing rather than grabbing the last photo taken. Photos and videos live in one
tab, every other file in the next, with one selection cap across both:

```dart
final result = await BrowseFiles.showPage(context, title: 'Attach');
```

### Options

Every option has a Telegram-shaped default:

```dart
await BrowseFiles.show(
  context,
  options: BrowseFilesOptions(
    types: {MediaType.image, MediaType.video},
    maxSelection: 10,          // taps past the cap are refused
    crossAxisCount: 3,         // grid columns
    pageSize: 50,              // items per platform request, not per library
    thumbnailSize: 256,        // square, in pixels; also the cache key
    peekSize: 0.55,            // fraction of the screen before the sheet is dragged up
    confirmLabel: 'Select',    // the selection count is appended
    documentMimeTypes: ['application/pdf', 'image/*'],
    allowMultipleDocuments: true,
    backgroundColor: Colors.black,  // recolours the sheet chrome, not the app theme
    accentColor: Colors.blue,
    onCameraTap: _openCamera,  // the camera cell appears only when this is supplied
  ),
);
```

### Tabs

Only **Gallery** and **File** are this package's business — the rest of Telegram's row are
extension points the host app fills in. Presets carry Telegram's label and icon; you supply the
body:

```dart
options: BrowseFilesOptions(
  tabs: [
    AttachmentTab.gallery,
    AttachmentTab.file,
    AttachmentTab.location(builder: (context) => MyMapPicker()),
    AttachmentTab.contact(builder: (context) => MyContactPicker()),
    AttachmentTab.custom(
      id: 'sticker',
      label: 'Sticker',
      icon: Icons.emoji_emotions_outlined,
      badge: const Icon(Icons.star, size: 10, color: Colors.amber),
      builder: (context) => MyStickerPicker(),
    ),
  ],
  initialTabId: AttachmentTab.galleryId,
),
```

An empty `tabs` list leaves the sheet on the gallery with no tab row.

### Permissions

Photo access is not a yes/no on either platform. `MediaPermissionStatus.limited` is a **grant**,
not a refusal — the user shared a subset of their library, and the sheet renders that subset with
an affordance to widen it. The sheet handles this itself; check it directly only if you gate the
sheet behind your own UI:

```dart
final api = BrowseFilesFlutter.instance;

var status = await api.permissionStatus();
if (status == MediaPermissionStatus.notDetermined) {
  status = await api.requestPermission();
}

if (status.canBrowse) {          // true for granted *and* limited
  if (status == MediaPermissionStatus.limited) {
    await api.presentLimitedPicker();   // let the user share more
  }
} else if (status.needsSettings) {      // permanentlyDenied or restricted
  await api.openSettings();             // prompting again would do nothing
}
```

### Using the API without the sheet

The platform calls are public, so you can build your own grid:

```dart
final api = BrowseFilesFlutter.instance;

final albums = await api.fetchAlbums();          // synthetic "all media" album first
final page = await api.fetchMedia(               // newest first
  albumId: albums.first.id,                      // that album's id, or null, means everything
  offset: 0,
  limit: 50,
);

for (final item in page.items) {
  final jpeg = await api.loadThumbnail(item.id, width: 256, height: 256);
  // item.id is a MediaStore id / PHAsset localIdentifier — never a file path.
}
```

Prefer `ThumbnailCache` over calling `loadThumbnail` per rebuild: it is a bounded LRU keyed by
asset id plus requested size, and it de-duplicates in-flight requests.

```dart
final cache = ThumbnailCache(capacity: 256);     // or ThumbnailCache.shared
cache.prefetch(page.items.map((i) => i.id), width: 256, height: 256);
final bytes = await cache.load(id, width: 256, height: 256);  // null = no thumbnail exists
```

Documents follow the same shape, with one caveat: the OS decides what may be listed at all.
`DocumentPage.enumerable` is `false` on iOS and on Android 11+, where scoped storage keeps
everything but this app's own files behind the system picker — so fall back to the picker rather
than showing an empty list:

```dart
final page = await api.fetchDocuments(mimeTypes: ['application/pdf']);
final paths = page.enumerable
    ? <String>[]
    : await api.pickDocuments(mimeTypes: ['application/pdf'], allowMultiple: true);
```

`pickDocuments` returns paths already copied into the app cache — a SAF URI and an iOS
security-scoped URL cannot be handed to the host app as they are — and an empty list if the user
dismissed the picker.

### Errors

Every call throws `BrowseFilesException` and nothing else; a raw `PlatformException` or
`MissingPluginException` never reaches the caller.

```dart
try {
  final path = await api.resolveFile(item.id);
} on BrowseFilesException catch (e) {
  if (e.isCancellation) return;               // a dismissed picker is a normal outcome
  switch (e.code) {
    case BrowseFilesErrorCode.permissionDenied:
    case BrowseFilesErrorCode.notFound:       // deleted, or on an unmounted volume
    case BrowseFilesErrorCode.ioError:
    case BrowseFilesErrorCode.unsupported:    // the OS predates the API involved
    default:
      // e.message and e.details are for logs
  }
}
```

## Out of scope

- **The live camera preview tile.** The camera cell appears only when `onCameraTap` is supplied,
  and the host app opens whatever camera it already uses. The example app shows one way to do it:
  its own channel onto `ACTION_IMAGE_CAPTURE` / `UIImagePickerController`, saving the shot into the
  library so it comes back as an ordinary asset id.
- **Location, Article, Poll and Contact tabs.** Presets exist for the label and icon; the body is
  the host app's.

## Development

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter run   # required to verify the grid, permissions and thumbnails
```

The grid, permissions and thumbnails cannot be verified in a simulator with an empty media
library — run the example on a device with real photos.

## License

MIT — see [LICENSE](LICENSE).
