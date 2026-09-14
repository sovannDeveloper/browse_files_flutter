import 'browse_files_options.dart';
import 'media_type.dart';

/// One row of the short attachment menu that `OCBrowseFiles.showActions`
/// opens: what the user can do next.
///
/// Each row hands off to a system UI — the camera, the media picker or the
/// document picker — and the menu closes before that UI opens, so it never
/// sits underneath one.
enum OCBrowseFilesAction {
  /// Open the camera and take a photo.
  takePhoto,

  /// Open the camera and record a video.
  recordVideo,

  /// Open the system media picker: photos and videos.
  gallery,

  /// Open the system document picker.
  files;

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
}
