import 'package:flutter/widgets.dart';

import 'attachment_tab.dart';
import 'media_type.dart';

/// How the attachment sheet should behave when it opens.
@immutable
class BrowseFilesOptions {
  /// Creates a set of sheet options; every one of them has a Telegram-shaped
  /// default.
  const BrowseFilesOptions({
    this.types = const <MediaType>{MediaType.image, MediaType.video},
    this.maxSelection = 10,
    this.tabs = AttachmentTab.defaults,
    this.initialTabId = AttachmentTab.galleryId,
    this.crossAxisCount = 3,
    this.pageSize = 50,
    this.thumbnailSize = 256,
    this.peekSize = 0.55,
    this.confirmLabel = 'Select',
    this.documentMimeTypes = const <String>[],
    this.allowMultipleDocuments = true,
    this.onCameraTap,
    this.backgroundColor,
    this.accentColor,
  }) : assert(maxSelection >= 1, 'maxSelection must allow at least one item'),
       assert(crossAxisCount >= 1, 'the grid needs at least one column'),
       assert(pageSize > 0, 'pageSize must be positive'),
       assert(
         peekSize > 0 && peekSize <= 1,
         'peekSize is a fraction of the screen',
       );

  /// Which media the gallery grid shows.
  final Set<MediaType> types;

  /// How many items may be selected before further taps are refused.
  final int maxSelection;

  /// The bottom row of attachment kinds, left to right.
  ///
  /// An empty list leaves the sheet on the gallery with no tab row.
  final List<AttachmentTab> tabs;

  /// Which of [tabs] opens first, by [AttachmentTab.id].
  final String initialTabId;

  /// Columns in the media grid. Telegram uses three.
  final int crossAxisCount;

  /// How many items each page of the grid asks the platform for.
  ///
  /// The grid asks for the next page a few rows before the last one is
  /// reached, so this is the size of a scroll-ahead batch, not of the library:
  /// a device holding twenty thousand photos is read fifty at a time.
  final int pageSize;

  /// The pixel size thumbnails are requested at, square.
  ///
  /// Tiles are small and the cache is keyed by this, so asking for one modest
  /// size everywhere is what keeps memory flat.
  final int thumbnailSize;

  /// The fraction of the screen the sheet snaps to before being dragged up.
  final double peekSize;

  /// The label on the confirm button; the selection count is appended to it.
  final String confirmLabel;

  /// MIME types the Files tab and its picker are restricted to; empty means
  /// any.
  ///
  /// These are MIME types, not extensions — `image/jpeg`, not `jpg`. A family
  /// wildcard works (`image/*`, `video/*`), and `*/*` is the same as passing
  /// nothing.
  final List<String> documentMimeTypes;

  /// Whether the File tab lets the user pick more than one document.
  final bool allowMultipleDocuments;

  /// The sheet's background, or `null` to follow the app's theme.
  ///
  /// Telegram's attach sheet is dark whatever the app around it looks like;
  /// setting this recolours the sheet's chrome to match, so the tab row and
  /// labels stay readable.
  final Color? backgroundColor;

  /// The colour of the selection numbers and the active tab, or `null` for the
  /// theme's primary.
  final Color? accentColor;

  /// Called when the camera tile is tapped.
  ///
  /// The live camera preview tile is out of this package's scope, so the tile
  /// only appears when the host app supplies this and is expected to open
  /// whatever camera it already uses.
  final VoidCallback? onCameraTap;
}
