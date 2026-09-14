/// A Telegram-style attachment bottom sheet for browsing device photos, videos
/// and documents.
///
/// Three ways in, all returning the same [OCBrowseFilesResult]:
///
/// * [OCBrowseFiles.showActions] — a short menu: take a photo, record a
///   video, select photos & videos, select files.
/// * [OCBrowseFiles.show] — the Telegram-style draggable sheet with a camera
///   tile, the picked-media grid and the Gallery/File tab row.
/// * [OCBrowseFiles.showPage] — a full-screen browser split by kind.
///
/// Underneath sits [OCBrowseFilesFlutter.instance]: [pickMedia] (the system
/// Photo Picker on Android 13+, GET_CONTENT below that, PHPicker on iOS),
/// [captureMedia] (the system camera), [pickDocuments] (SAF / the document
/// picker) and [loadThumbnail]/[resolveFile]. None of them needs a media
/// permission, so the plugin ships with **no** `READ_MEDIA_*` or
/// `READ_EXTERNAL_STORAGE` declaration, which is what Google Play now requires
/// to avoid the Permissions Declaration Form.
///
/// The id of every item [pickMedia] returns is a content URI on Android or a
/// cached file path on iOS. Treat it as opaque: pass it to
/// [OCBrowseFilesFlutter.loadThumbnail] for a grid tile and to
/// [OCBrowseFilesFlutter.resolveFile] when the host app needs bytes on disk.
library;

import 'dart:typed_data';

import 'src/browse_files_flutter_platform_interface.dart';
import 'src/models/media_item.dart';
import 'src/models/media_type.dart';

export 'src/browse_files_flutter_method_channel.dart';
export 'src/browse_files_flutter_platform_interface.dart';
export 'src/models/attachment_tab.dart';
export 'src/models/browse_files_action.dart';
export 'src/models/browse_files_exception.dart';
export 'src/models/browse_files_options.dart';
export 'src/models/browse_files_result.dart';
export 'src/models/browse_files_strings.dart';
export 'src/models/document_item.dart';
export 'src/models/media_item.dart';
export 'src/models/media_type.dart';
export 'src/ui/browse_files_page.dart' show OCBrowseFilesPage;
export 'src/ui/browse_files_actions.dart' show OCBrowseFilesActionsSheet;
export 'src/ui/browse_files_sheet.dart' show OCBrowseFiles;
export 'src/ui/thumbnail_cache.dart';

/// Entry point of the plugin.
///
/// A thin facade over [OCBrowseFilesFlutterPlatform]; every call here fails with
/// a [BrowseFilesException] and nothing else.
class OCBrowseFilesFlutter {
  OCBrowseFilesFlutter._();

  /// The instance to call the plugin through.
  static final OCBrowseFilesFlutter instance = OCBrowseFilesFlutter._();

  OCBrowseFilesFlutterPlatform get _platform =>
      OCBrowseFilesFlutterPlatform.instance;

  /// Opens the system media picker and returns what the user chose.
  ///
  /// On Android 13+ this is the Photo Picker (`ACTION_PICK_IMAGES`), below
  /// that the legacy `ACTION_GET_CONTENT` — neither requires a permission.
  /// On iOS the PHPickerViewController is used. Resolves to an empty list
  /// when the user dismissed the picker.
  ///
  /// The id of every returned [OCMediaItem] is a content URI on Android or an
  /// asset identifier on iOS. It is **not** a file path: pass it to
  /// [loadThumbnail] for a grid tile and to [resolveFile] when the host app
  /// needs bytes on disk.
  Future<List<OCMediaItem>> pickMedia({
    Set<OCMediaType> types = kAllMediaTypes,
    bool allowMultiple = true,
  }) => _platform.pickMedia(types: types, allowMultiple: allowMultiple);

  /// A JPEG thumbnail for one asset, or `null` if none could be produced.
  ///
  /// Does no caching — the caller owns that.
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) => _platform.loadThumbnail(
    id,
    width: width,
    height: height,
    quality: quality,
  );

  /// Copies an asset into the app cache and returns its path.
  Future<String> resolveFile(String id) => _platform.resolveFile(id);

  /// Opens the system document picker and returns cached paths for the chosen
  /// files, empty if the user dismissed it.
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) => _platform.pickDocuments(
    mimeTypes: mimeTypes,
    allowMultiple: allowMultiple,
  );

  /// Opens the system camera to take a photo or record a video.
  ///
  /// Resolves to the capture, already copied into the app cache, or `null` if
  /// the user backed out. No library permission is involved; iOS needs
  /// `NSCameraUsageDescription` (and `NSMicrophoneUsageDescription` for
  /// video) in the host's Info.plist.
  Future<OCMediaItem?> captureMedia({OCMediaType type = OCMediaType.image}) =>
      _platform.captureMedia(type: type);
}
