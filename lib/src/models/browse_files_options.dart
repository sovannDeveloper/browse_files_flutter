import 'package:flutter/widgets.dart';

import 'attachment_tab.dart';
import 'browse_files_strings.dart';
import 'media_type.dart';

/// How the attachment sheet should behave when it opens.
@immutable
class OCBrowseFilesOptions {
  /// Creates a set of sheet options; every one of them has a Telegram-shaped
  /// default.
  const OCBrowseFilesOptions({
    this.types = const <OCMediaType>{OCMediaType.image, OCMediaType.video},
    this.maxSelection = 10,
    this.tabs = OCAttachmentTab.defaults,
    this.initialTabId = OCAttachmentTab.galleryId,
    this.crossAxisCount = 3,
    this.thumbnailSize = 256,
    this.peekSize = 0.55,
    this.strings = const OCBrowseFilesStrings(),
    this.confirmLabel,
    this.documentMimeTypes = const <String>[],
    this.allowMultipleDocuments = true,
    this.allowMultipleMedia = true,
    this.showCamera = true,
    this.onCameraTap,
    this.backgroundColor,
    this.accentColor,
  }) : assert(maxSelection >= 1, 'maxSelection must allow at least one item'),
       assert(crossAxisCount >= 1, 'the grid needs at least one column'),
       assert(
         peekSize > 0 && peekSize <= 1,
         'peekSize is a fraction of the screen',
       );

  /// Which media kinds the gallery picker shows.
  ///
  /// Passed straight to the system picker (Photo Picker on Android 13+,
  /// `ACTION_GET_CONTENT` below that, PHPickerViewController on iOS) as the
  /// MIME filter — only items of these kinds appear in the picker.
  final Set<OCMediaType> types;

  /// How many items may be selected before further taps are refused.
  ///
  /// Counts across both the gallery and the file tab.
  final int maxSelection;

  /// The bottom row of attachment kinds, left to right.
  ///
  /// An empty list leaves the sheet on the gallery with no tab row.
  final List<OCAttachmentTab> tabs;

  /// Which of [tabs] opens first, by [OCAttachmentTab.id].
  final String initialTabId;

  /// Columns in the picked-media grid. Telegram uses three.
  final int crossAxisCount;

  /// The pixel size thumbnails are requested at, square.
  ///
  /// Tiles are small and the cache is keyed by this, so asking for one modest
  /// size everywhere is what keeps memory flat.
  final int thumbnailSize;

  /// The fraction of the screen the sheet snaps to before being dragged up.
  final double peekSize;

  /// Every string the sheet draws, for host apps that localise or reword it.
  final OCBrowseFilesStrings strings;

  /// The label on the confirm button; the selection count is appended to it.
  ///
  /// A shortcut for the one string most apps change: when set it wins over
  /// [OCBrowseFilesStrings.confirmLabel], and `null` leaves that one alone.
  final String? confirmLabel;

  /// The strings the sheet actually draws — [strings], with [confirmLabel]
  /// folded in when the caller set it.
  OCBrowseFilesStrings get text {
    final label = confirmLabel;
    return label == null ? strings : strings.copyWith(confirmLabel: label);
  }

  /// MIME types the Files tab and its picker are restricted to; empty means
  /// any.
  ///
  /// These are MIME types, not extensions — `image/jpeg`, not `jpg`. A family
  /// wildcard works (`image/*`, `video/*`), and `*/*` is the same as passing
  /// nothing.
  final List<String> documentMimeTypes;

  /// Whether the File tab lets the user pick more than one document.
  final bool allowMultipleDocuments;

  /// Whether the system media picker lets the user pick more than one item.
  ///
  /// False means the picker forces a single pick — what `BrowseFiles.show`
  /// does when [maxSelection] is `1` regardless.
  final bool allowMultipleMedia;

  /// The sheet's background, or `null` to follow the app's theme.
  ///
  /// Telegram's attach sheet is dark whatever the app around it looks like;
  /// setting this recolours the sheet's chrome to match, so the tab row and
  /// labels stay readable.
  final Color? backgroundColor;

  /// The colour of the selection numbers and the active tab, or `null` for the
  /// theme's primary.
  final Color? accentColor;

  /// Whether the sheet offers the camera at all.
  ///
  /// When true the sheet's camera tile — and the camera rows of
  /// `OCBrowseFiles.showActions` — open the system camera through
  /// `captureMedia`: a photo if [types] holds [OCMediaType.image], a video if
  /// it holds [OCMediaType.video], and a choice of the two when it holds
  /// both. The capture lands in the selection like any picked item.
  ///
  /// The live camera preview tile Telegram draws is out of this package's
  /// scope; this is the system camera app.
  final bool showCamera;

  /// Replaces the built-in camera with the host app's own.
  ///
  /// When set, tapping the camera tile calls this instead of `captureMedia`
  /// and the host app is expected to open whatever camera it already uses.
  /// Ignored when [showCamera] is false.
  final VoidCallback? onCameraTap;

  /// Which kinds the built-in camera can capture, in the order they are
  /// offered: empty when [showCamera] is false or [types] holds neither.
  List<OCMediaType> get cameraTypes => <OCMediaType>[
    if (showCamera && types.contains(OCMediaType.image)) OCMediaType.image,
    if (showCamera && types.contains(OCMediaType.video)) OCMediaType.video,
  ];

  /// Whether the camera tile should be drawn.
  bool get hasCamera =>
      showCamera && (onCameraTap != null || cameraTypes.isNotEmpty);
}
