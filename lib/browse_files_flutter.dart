/// A Telegram-style attachment bottom sheet for browsing device photos, videos
/// and documents.
///
/// Start with [BrowseFilesFlutter.instance]: check
/// [BrowseFilesFlutter.permissionStatus], prompt with
/// [BrowseFilesFlutter.requestPermission] — remembering that
/// [MediaPermissionStatus.limited] is a *grant* — then page the library with
/// [BrowseFilesFlutter.fetchMedia] and draw each tile from
/// [BrowseFilesFlutter.loadThumbnail].
///
/// A library id is not a path: call [BrowseFilesFlutter.resolveFile] on the
/// final selection to get a file the host app can read.
///
/// The sheet UI itself is not implemented yet — see `CLAUDE.md` for the
/// intended design.
library;

import 'package:flutter/foundation.dart';

import 'src/browse_files_flutter_platform_interface.dart';
import 'src/models/document_page.dart';
import 'src/models/media_album.dart';
import 'src/models/media_page.dart';
import 'src/models/media_permission.dart';
import 'src/models/media_type.dart';

export 'src/browse_files_flutter_method_channel.dart';
export 'src/browse_files_flutter_platform_interface.dart';
export 'src/models/attachment_tab.dart';
export 'src/models/browse_files_exception.dart';
export 'src/models/browse_files_options.dart';
export 'src/models/browse_files_result.dart';
export 'src/models/document_item.dart';
export 'src/models/document_page.dart';
export 'src/models/media_album.dart';
export 'src/models/media_item.dart';
export 'src/models/media_page.dart';
export 'src/models/media_permission.dart';
export 'src/models/media_type.dart';
export 'src/ui/browse_files_page.dart' show BrowseFilesPage;
export 'src/ui/browse_files_sheet.dart' show BrowseFiles, BrowseFilesSheet;
export 'src/ui/thumbnail_cache.dart';

/// Entry point of the plugin.
///
/// A thin facade over [BrowseFilesFlutterPlatform]; every call here fails with
/// a [BrowseFilesException] and nothing else.
class BrowseFilesFlutter {
  BrowseFilesFlutter._();

  /// The instance to call the plugin through.
  static final BrowseFilesFlutter instance = BrowseFilesFlutter._();

  BrowseFilesFlutterPlatform get _platform =>
      BrowseFilesFlutterPlatform.instance;

  /// The current access level, without prompting.
  Future<MediaPermissionStatus> permissionStatus({
    Set<MediaType> types = kAllMediaTypes,
  }) => _platform.permissionStatus(types: types);

  /// Prompts for library access and reports what the user granted.
  ///
  /// Treat [MediaPermissionStatus.limited] as success: the user shared part of
  /// their library rather than refusing.
  Future<MediaPermissionStatus> requestPermission({
    Set<MediaType> types = kAllMediaTypes,
  }) => _platform.requestPermission(types: types);

  /// Opens this app's page in system settings, for when prompting is no longer
  /// possible.
  Future<bool> openSettings() => _platform.openSettings();

  /// Shows the OS picker that widens a [MediaPermissionStatus.limited] grant.
  Future<MediaPermissionStatus> presentLimitedPicker() =>
      _platform.presentLimitedPicker();

  /// The albums holding at least one asset of the given [types], the synthetic
  /// "all media" album first.
  Future<List<MediaAlbum>> fetchAlbums({
    Set<MediaType> types = kAllMediaTypes,
  }) => _platform.fetchAlbums(types: types);

  /// One page of an album, newest first; a `null` [albumId] means the whole
  /// library.
  Future<MediaPage> fetchMedia({
    String? albumId,
    Set<MediaType> types = kAllMediaTypes,
    int offset = 0,
    int limit = 50,
  }) => _platform.fetchMedia(
    albumId: albumId,
    types: types,
    offset: offset,
    limit: limit,
  );

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

  /// One page of the files this platform will list — never the whole device;
  /// see [DocumentPage.enumerable].
  Future<DocumentPage> fetchDocuments({
    List<String> mimeTypes = const [],
    int offset = 0,
    int limit = 50,
  }) => _platform.fetchDocuments(
    mimeTypes: mimeTypes,
    offset: offset,
    limit: limit,
  );

  /// Opens the system document picker and returns cached paths for the chosen
  /// files, empty if the user dismissed it.
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) => _platform.pickDocuments(
    mimeTypes: mimeTypes,
    allowMultiple: allowMultiple,
  );
}
