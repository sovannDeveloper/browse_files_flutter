import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'browse_files_flutter_method_channel.dart';
import 'models/document_page.dart';
import 'models/media_album.dart';
import 'models/media_page.dart';
import 'models/media_permission.dart';
import 'models/media_type.dart';

/// Every media type the picker knows about — the default filter.
const Set<OCMediaType> kAllMediaTypes = {OCMediaType.image, OCMediaType.video};

/// The interface every platform implementation of `browse_files_flutter`
/// fulfils.
///
/// Platform implementations should extend this class rather than implement it,
/// so that new members can be added without breaking them.
///
/// Everything here is deliberately low-level: enumeration is paged, thumbnails
/// are fetched one asset at a time, and files are only materialised on demand.
/// The sheet UI is a consumer of this interface, never a peer of it.
abstract class OCBrowseFilesFlutterPlatform extends PlatformInterface {
  /// Constructs a platform implementation.
  OCBrowseFilesFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static OCBrowseFilesFlutterPlatform _instance =
      OCMethodChannelBrowseFilesFlutter();

  /// The default instance to use.
  ///
  /// Defaults to [OCMethodChannelBrowseFilesFlutter].
  static OCBrowseFilesFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [OCBrowseFilesFlutterPlatform] when
  /// they register themselves.
  static set instance(OCBrowseFilesFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// The current access level, without prompting.
  Future<OCMediaPermissionStatus> permissionStatus({
    Set<OCMediaType> types = kAllMediaTypes,
  }) {
    throw UnimplementedError('permissionStatus() has not been implemented.');
  }

  /// Prompts for library access and reports what the user granted.
  ///
  /// May resolve to [OCMediaPermissionStatus.limited]: on Android 14+ and iOS the
  /// user can share a subset instead of the whole library, and that is a
  /// success, not a refusal.
  Future<OCMediaPermissionStatus> requestPermission({
    Set<OCMediaType> types = kAllMediaTypes,
  }) {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Opens this app's page in system settings, for when prompting is no longer
  /// possible. Resolves to whether the settings screen was actually opened.
  Future<bool> openSettings() {
    throw UnimplementedError('openSettings() has not been implemented.');
  }

  /// Shows the OS picker that widens a [OCMediaPermissionStatus.limited] grant,
  /// and reports the access level once it closes.
  ///
  /// The "select more photos" affordance the grid shows in limited mode.
  Future<OCMediaPermissionStatus> presentLimitedPicker() {
    throw UnimplementedError(
      'presentLimitedPicker() has not been implemented.',
    );
  }

  /// The albums that hold at least one asset of the given [types].
  ///
  /// The first entry is the synthetic "all media" album the grid opens on.
  Future<List<OCMediaAlbum>> fetchAlbums({
    Set<OCMediaType> types = kAllMediaTypes,
  }) {
    throw UnimplementedError('fetchAlbums() has not been implemented.');
  }

  /// One page of an album, newest first.
  ///
  /// Pass a `null` [albumId] for the whole library. Implementations must query
  /// off the platform main thread and must not read more than [limit] rows —
  /// the grid pages as it scrolls, and a full-library fetch will not fit in
  /// memory or in a channel message.
  Future<OCMediaPage> fetchMedia({
    String? albumId,
    Set<OCMediaType> types = kAllMediaTypes,
    int offset = 0,
    int limit = 50,
  }) {
    throw UnimplementedError('fetchMedia() has not been implemented.');
  }

  /// A JPEG thumbnail for one asset, sized to roughly [width] x [height]
  /// pixels, or `null` if the platform could not produce one.
  ///
  /// Decoding happens natively and off the main thread. Callers are expected
  /// to cache the result; this method does no caching of its own.
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) {
    throw UnimplementedError('loadThumbnail() has not been implemented.');
  }

  /// Materialises an asset as a real file and returns its path.
  ///
  /// Library ids are not paths, so the asset is copied into the app cache —
  /// iCloud assets may have to be downloaded first, which can take a while.
  /// Call this on the final selection, not on every tile.
  Future<String> resolveFile(String id) {
    throw UnimplementedError('resolveFile() has not been implemented.');
  }

  /// One page of the files this platform is willing to list, most recently
  /// changed first.
  ///
  /// This is never the whole device: scoped storage on Android 11+ and the
  /// sandbox on iOS keep everything but this app's own files behind the system
  /// picker, and [OCDocumentPage.enumerable] says when that is the case.
  Future<OCDocumentPage> fetchDocuments({
    List<String> mimeTypes = const [],
    int offset = 0,
    int limit = 50,
  }) {
    throw UnimplementedError('fetchDocuments() has not been implemented.');
  }

  /// Opens the system document picker and returns cached paths for what the
  /// user chose, or an empty list if they dismissed it.
  ///
  /// Backed by the Storage Access Framework on Android and
  /// `UIDocumentPickerViewController` on iOS. The picked documents are copied
  /// into the app cache, because a SAF URI and a security-scoped iOS URL are
  /// neither of them usable as a path.
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) {
    throw UnimplementedError('pickDocuments() has not been implemented.');
  }
}
