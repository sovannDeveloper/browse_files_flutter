import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browse_files_flutter_platform_interface.dart';
import 'models/browse_files_exception.dart';
import 'models/document_page.dart';
import 'models/media_album.dart';
import 'models/media_page.dart';
import 'models/media_permission.dart';
import 'models/media_type.dart';

/// The default [BrowseFilesFlutterPlatform], talking to Android and iOS over a
/// method channel.
///
/// Every call funnels its failures through [_toBrowseFilesException], so
/// callers only ever catch [BrowseFilesException].
class MethodChannelBrowseFilesFlutter extends BrowseFilesFlutterPlatform {
  /// The channel carrying one-shot calls.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'com.kedtec.browse_files_flutter/methods',
  );

  @override
  Future<MediaPermissionStatus> permissionStatus({
    Set<MediaType> types = kAllMediaTypes,
  }) async {
    final names = _typeNames(types);
    return _guard(() async {
      final name = await methodChannel.invokeMethod<String>(
        'permissionStatus',
        {'types': names},
      );
      return MediaPermissionStatus.fromName(name);
    });
  }

  @override
  Future<MediaPermissionStatus> requestPermission({
    Set<MediaType> types = kAllMediaTypes,
  }) async {
    final names = _typeNames(types);
    return _guard(() async {
      final name = await methodChannel.invokeMethod<String>(
        'requestPermission',
        {'types': names},
      );
      return MediaPermissionStatus.fromName(name);
    });
  }

  @override
  Future<bool> openSettings() async {
    return _guard(
      () async =>
          await methodChannel.invokeMethod<bool>('openSettings') ?? false,
    );
  }

  @override
  Future<MediaPermissionStatus> presentLimitedPicker() async {
    return _guard(() async {
      final name = await methodChannel.invokeMethod<String>(
        'presentLimitedPicker',
      );
      return MediaPermissionStatus.fromName(name);
    });
  }

  @override
  Future<List<MediaAlbum>> fetchAlbums({
    Set<MediaType> types = kAllMediaTypes,
  }) async {
    final names = _typeNames(types);
    return _guard(() async {
      final albums = await methodChannel.invokeListMethod<Object?>(
        'fetchAlbums',
        {'types': names},
      );
      return (albums ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(MediaAlbum.fromMap)
          .toList(growable: false);
    });
  }

  @override
  Future<MediaPage> fetchMedia({
    String? albumId,
    Set<MediaType> types = kAllMediaTypes,
    int offset = 0,
    int limit = 50,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final names = _typeNames(types);
    return _guard(() async {
      final page = await methodChannel.invokeMapMethod<Object?, Object?>(
        'fetchMedia',
        {'albumId': albumId, 'types': names, 'offset': offset, 'limit': limit},
      );
      return page == null ? MediaPage.empty : MediaPage.fromMap(page);
    });
  }

  @override
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'thumbnail size must be positive, got ${width}x$height',
      );
    }
    return _guard(
      () => methodChannel.invokeMethod<Uint8List>('loadThumbnail', {
        'id': id,
        'width': width,
        'height': height,
        'quality': quality,
      }),
    );
  }

  @override
  Future<String> resolveFile(String id) async {
    return _guard(() async {
      final path = await methodChannel.invokeMethod<String>('resolveFile', {
        'id': id,
      });
      if (path == null) {
        throw BrowseFilesException(
          BrowseFilesErrorCode.notFound,
          'The asset $id could not be resolved to a file.',
        );
      }
      return path;
    });
  }

  @override
  Future<DocumentPage> fetchDocuments({
    List<String> mimeTypes = const [],
    int offset = 0,
    int limit = 50,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    return _guard(() async {
      final page = await methodChannel.invokeMapMethod<Object?, Object?>(
        'fetchDocuments',
        {'mimeTypes': mimeTypes, 'offset': offset, 'limit': limit},
      );
      return page == null ? DocumentPage.empty : DocumentPage.fromMap(page);
    });
  }

  @override
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) async {
    return _guard(() async {
      final paths = await methodChannel.invokeListMethod<String>(
        'pickDocuments',
        {'mimeTypes': mimeTypes, 'allowMultiple': allowMultiple},
      );
      return paths ?? const <String>[];
    });
  }

  List<String> _typeNames(Set<MediaType> types) {
    if (types.isEmpty) {
      throw ArgumentError.value(
        types,
        'types',
        'at least one media type is required',
      );
    }
    return [for (final type in types) type.name];
  }

  /// Runs a channel call, translating anything it throws into a
  /// [BrowseFilesException].
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BrowseFilesException {
      rethrow;
    } catch (error) {
      throw _toBrowseFilesException(error);
    }
  }
}

/// Turns a channel error into the plugin's own exception type, so callers never
/// have to reason about [PlatformException] codes.
BrowseFilesException _toBrowseFilesException(Object error) => switch (error) {
  BrowseFilesException() => error,
  MissingPluginException() => BrowseFilesException(
    BrowseFilesErrorCode.unimplemented,
    error.message ??
        'This platform has no browse_files_flutter implementation.',
  ),
  PlatformException() => BrowseFilesException(
    BrowseFilesErrorCode.fromName(error.code),
    error.message ?? 'The media library call failed.',
    details: error.details?.toString(),
  ),
  _ => BrowseFilesException(BrowseFilesErrorCode.unknown, error.toString()),
};
