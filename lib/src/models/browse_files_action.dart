import 'package:flutter/material.dart';

import 'browse_files_options.dart';
import 'browse_files_strings.dart';
import 'media_type.dart';

/// What a row of the short attachment menu does when tapped.
enum OCBrowseFilesActionKind {
  /// Open the camera and take a photo.
  takePhoto,

  /// Open the camera and record a video.
  recordVideo,

  /// Open the system media picker: photos and videos.
  gallery,

  /// Open the system document picker.
  files,
}

/// One row of the short attachment menu that `OCBrowseFiles.showActions`
/// opens: what the user can do next.
///
/// Each row hands off to a system UI — the camera, the media picker or the
/// document picker — and the menu closes before that UI opens, so it never
/// sits underneath one.
///
/// The four rows are the constants [takePhoto], [recordVideo], [gallery] and
/// [files]. Their text comes from [OCBrowseFilesStrings] unless a row is given
/// its own with [withLabel]:
///
/// ```dart
/// OCBrowseFiles.showActions(
///   context,
///   actions: <OCBrowseFilesAction>[
///     OCBrowseFilesAction.takePhoto.withLabel('Camera'),
///     OCBrowseFilesAction.gallery.withLabel('Photos'),
///     OCBrowseFilesAction.files,
///   ],
/// );
/// ```
@immutable
class OCBrowseFilesAction {
  const OCBrowseFilesAction._(this.kind, {required this.icon, this.label});

  /// Open the camera and take a photo.
  static const OCBrowseFilesAction takePhoto = OCBrowseFilesAction._(
    OCBrowseFilesActionKind.takePhoto,
    icon: Icons.photo_camera_outlined,
  );

  /// Open the camera and record a video.
  static const OCBrowseFilesAction recordVideo = OCBrowseFilesAction._(
    OCBrowseFilesActionKind.recordVideo,
    icon: Icons.videocam_outlined,
  );

  /// Open the system media picker: photos and videos.
  static const OCBrowseFilesAction gallery = OCBrowseFilesAction._(
    OCBrowseFilesActionKind.gallery,
    icon: Icons.photo_library_outlined,
  );

  /// Open the system document picker.
  static const OCBrowseFilesAction files = OCBrowseFilesAction._(
    OCBrowseFilesActionKind.files,
    icon: Icons.insert_drive_file_outlined,
  );

  /// The four rows, in menu order.
  static const List<OCBrowseFilesAction> values = <OCBrowseFilesAction>[
    takePhoto,
    recordVideo,
    gallery,
    files,
  ];

  /// The rows that make sense for [options], in menu order: the two camera
  /// rows for the kinds in [OCBrowseFilesOptions.types], then the gallery,
  /// then files.
  static List<OCBrowseFilesAction> defaultsFor(OCBrowseFilesOptions options) =>
      <OCBrowseFilesAction>[
        if (options.showCamera && options.types.contains(OCMediaType.image))
          takePhoto,
        if (options.showCamera && options.types.contains(OCMediaType.video))
          recordVideo,
        gallery,
        files,
      ];

  /// What tapping the row does.
  final OCBrowseFilesActionKind kind;

  /// The glyph at the start of the row.
  final IconData icon;

  /// The row's own text, or `null` to use the one in [OCBrowseFilesStrings].
  final String? label;

  /// The same row under another caption.
  ///
  /// [OCBrowseFilesStrings] words every row at once; this words one row, and
  /// wins over the strings for that row.
  OCBrowseFilesAction withLabel(String label) =>
      OCBrowseFilesAction._(kind, icon: icon, label: label);

  /// The same row behind another glyph.
  OCBrowseFilesAction withIcon(IconData icon) =>
      OCBrowseFilesAction._(kind, icon: icon, label: label);

  /// The text the row shows: [label] when set, otherwise the matching entry
  /// in [strings].
  String labelFor(OCBrowseFilesStrings strings) =>
      label ??
      switch (kind) {
        OCBrowseFilesActionKind.takePhoto => strings.takePhotoLabel,
        OCBrowseFilesActionKind.recordVideo => strings.recordVideoLabel,
        OCBrowseFilesActionKind.gallery => strings.selectMediaLabel,
        OCBrowseFilesActionKind.files => strings.selectFilesLabel,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OCBrowseFilesAction &&
          other.kind == kind &&
          other.icon == icon &&
          other.label == label;

  @override
  int get hashCode => Object.hash(kind, icon, label);

  @override
  String toString() =>
      'OCBrowseFilesAction(${kind.name}${label == null ? '' : ', $label'})';
}
