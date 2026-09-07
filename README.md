# browse_files_flutter

A Telegram-style attachment bottom sheet for Flutter — browse the device's photos, videos and
documents in a draggable sheet with ordered multi-selection.

> **Status: Dart API only.** The models, platform interface and method channel are in place and
> tested; the native implementations are stubs, so every call currently fails with
> `BrowseFilesErrorCode.unimplemented`. See [CLAUDE.md](CLAUDE.md) for the design.

## Planned


- Draggable bottom sheet with snap points, over a dimmed scrim.
- Three-column media grid, newest first, with play glyph + duration badge on videos and an ordered
  circular selection control per tile.
- Native, paged enumeration — Android `MediaStore`, iOS `PHAsset` — with per-tile thumbnails.
- Full handling of partial photo access (Android 14 `READ_MEDIA_VISUAL_USER_SELECTED`, iOS
  `PHAuthorizationStatus.limited`).
- A **File** tab backed by the system pickers (SAF / `UIDocumentPickerViewController`).
- Extension points so the host app can add its own tabs (Location, Poll, Contact, …).

## Development

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter run   # required to verify the grid, permissions and thumbnails
```

## License

MIT — see [LICENSE](LICENSE).
