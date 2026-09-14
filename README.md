# browse_files_flutter

A Telegram-style attachment sheet for Flutter: **select photos & videos**, **select files** or
**take a photo / record a video**, from a short menu or from a draggable sheet with ordered
multi-selection.

Everything goes through the system UIs — the Photo Picker / `PHPickerViewController`, the
Storage Access Framework / `UIDocumentPickerViewController`, and the system camera app — so the
plugin declares **no** `READ_MEDIA_*`, `READ_EXTERNAL_STORAGE` or `CAMERA` permission and needs no
photo library access on iOS. No third-party gallery or picker dependency.

Every public name is prefixed `OC`.

## Install

The package is not on pub.dev (`publish_to: none`); depend on it by git or by path:

```yaml
dependencies:
  browse_files_flutter:
    git:
      url: https://github.com/kedtec/browse_files_flutter.git
```

## Platform setup

**Android** — nothing. The `<queries>` entries and the `FileProvider` the camera writes through
are declared in the plugin's manifest and merged into the app's. Do not add `CAMERA` to the
manifest: once it is declared, the camera intent starts requiring it.

**iOS** — the camera needs purpose strings in `ios/Runner/Info.plist`; without them iOS kills the
app when the camera opens (the plugin checks for them and fails with `unsupported` instead):

```xml
<key>NSCameraUsageDescription</key>
<string>Opens the camera so you can take a photo or video to attach.</string>
<!-- only if you record video -->
<key>NSMicrophoneUsageDescription</key>
<string>Records sound with the videos you attach.</string>
```

No `NSPhotoLibraryUsageDescription` is needed: the picker runs out of process.

## Usage

All three entry points hand back the same `OCBrowseFilesResult` — `media` (photos and videos) and
`documents` (cached file paths) — and `null` when the user dismissed the UI.

### The menu

Four rows — take photo · record video · select photos & videos · select files. The menu closes
before the camera or picker opens:

```dart
import 'package:browse_files_flutter/browse_files_flutter.dart';

final result = await OCBrowseFiles.showActions(context);
if (result != null && result.isNotEmpty) {
  for (final item in result.media) {
    final path = await OCBrowseFilesFlutter.instance.resolveFile(item.id);
  }
  for (final path in result.documents) {
    // already a cached file
  }
}
```

`result` is `OCBrowseFilesResult.empty` when the user opened the camera or a picker and backed
out, and `null` when they dismissed the menu. Pick the rows with `actions:`; by default the camera
rows follow `OCBrowseFilesOptions.types`. A platform failure is thrown as `OCBrowseFilesException`
— there is no sheet left to show it in.

### The sheet

The Telegram layout: a draggable sheet with a camera cell, a 3-column grid of what has been
picked so far with numbered selection, and the Gallery · File tab row. The camera cell opens the
system camera (asking photo or video first when both are allowed) and the shot lands in the
selection.

```dart
final result = await OCBrowseFiles.show(context);
```

Both calls need a context **below** a `Navigator`. A `State` that builds `MaterialApp` itself sits
above the one it creates — call from a widget inside `MaterialApp`, or wrap the call site in a
`Builder`.

### The full-screen browser

Same result, for browsing rather than grabbing the last photo taken:

```dart
final result = await OCBrowseFiles.showPage(context, title: 'Attach');
```

### Options

Every option has a Telegram-shaped default:

```dart
await OCBrowseFiles.show(
  context,
  options: OCBrowseFilesOptions(
    types: {OCMediaType.image, OCMediaType.video},  // what the picker and camera offer
    maxSelection: 10,          // taps past the cap are refused; counts media + documents
    allowMultipleMedia: true,
    crossAxisCount: 3,         // grid columns
    thumbnailSize: 256,        // square, in pixels; also the cache key
    peekSize: 0.55,            // fraction of the screen before the sheet is dragged up
    strings: const OCBrowseFilesStrings(),  // every word the sheet draws
    confirmLabel: 'Send',      // shortcut for strings.confirmLabel; the count is appended
    documentMimeTypes: ['application/pdf', 'image/*'],
    allowMultipleDocuments: true,
    showCamera: true,          // false hides the camera cell and the camera menu rows
    onCameraTap: null,         // set it to replace the built-in camera with your own
    backgroundColor: Colors.black,  // recolours the sheet chrome, not the app theme
    accentColor: Colors.blue,
  ),
);
```

### Tabs

Only **Gallery** and **File** are this package's business — the rest of Telegram's row are
extension points the host app fills in. Presets carry Telegram's label and icon; you supply the
body:

```dart
options: OCBrowseFilesOptions(
  tabs: [
    OCAttachmentTab.gallery,
    OCAttachmentTab.file,
    OCAttachmentTab.location(builder: (context) => MyMapPicker()),
    OCAttachmentTab.contact(builder: (context) => MyContactPicker()),
    OCAttachmentTab.custom(
      id: 'sticker',
      label: 'Sticker',
      icon: Icons.emoji_emotions_outlined,
      badge: const Icon(Icons.star, size: 10, color: Colors.amber),
      builder: (context) => MyStickerPicker(),
    ),
  ],
  initialTabId: OCAttachmentTab.galleryId,
),
```

An empty `tabs` list leaves the sheet on the gallery with no tab row.

### Text and localisation

Every string lives in `OCBrowseFilesStrings`. Pass one to `OCBrowseFilesOptions.strings` and
override only what you want:

```dart
strings: OCBrowseFilesStrings(
  confirmLabel: 'Envoyer',
  takePhotoLabel: 'Prendre une photo',
  recordVideoLabel: 'Filmer',
  selectMediaLabel: 'Photos et vidéos',
  selectFilesLabel: 'Fichiers',
  confirmButton: (label, count) => '$label · $count',
),
```

The bottom row's captions belong to the tabs: `OCAttachmentTab.gallery.withLabel('Galerie')`
renames one without touching its `id`.

## The API underneath

```dart
final api = OCBrowseFilesFlutter.instance;

final picked = await api.pickMedia(types: {OCMediaType.image});     // system picker
final shot = await api.captureMedia(type: OCMediaType.video);       // null = backed out
final docs = await api.pickDocuments(mimeTypes: ['application/pdf']); // cached paths

final jpeg = await api.loadThumbnail(picked.first.id, width: 256, height: 256);
final path = await api.resolveFile(picked.first.id);
```

An `OCMediaItem.id` is opaque: a content URI from the Photo Picker or a `file://` capture on
Android, a cached path on iOS. Hand it to `loadThumbnail` for a tile and to `resolveFile` for a
file the app owns; captures and iOS picks are already files, so `resolveFile` returns at once.
`OCThumbnailCache` is a bounded LRU keyed by id plus size that de-duplicates in-flight requests —
prefer it over calling `loadThumbnail` per rebuild.

### Errors

Every call throws `OCBrowseFilesException` and nothing else:

```dart
try {
  final shot = await api.captureMedia();
} on OCBrowseFilesException catch (e) {
  switch (e.code) {
    case OCBrowseFilesErrorCode.permissionDenied: // camera refused (iOS) — Settings can undo it
    case OCBrowseFilesErrorCode.unsupported:      // no camera, or a missing Info.plist string
    case OCBrowseFilesErrorCode.notFound:
    case OCBrowseFilesErrorCode.ioError:
    default:
      // e.message and e.details are for logs
  }
}
```

## Out of scope

- **A live camera preview tile.** The camera cell opens the system camera app; a host app with
  its own camera passes `onCameraTap`.
- **Location, Article, Poll and Contact tabs.** Presets exist for the label and icon; the body is
  the host app's.

## Development

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter run   # the pickers and the camera only exist on a device
```

## License

MIT — see [LICENSE](LICENSE).
