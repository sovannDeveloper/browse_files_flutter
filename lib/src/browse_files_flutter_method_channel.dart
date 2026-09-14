import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browse_files_flutter_platform_interface.dart';
import 'models/browse_files_exception.dart';
import 'models/media_item.dart';
import 'models/media_type.dart';

/// The default [OCBrowseFilesFlutterPlatform], talking to Android and iOS over a
/// method channel.
///
/// Every call funnels its failures through [_toBrowseFilesException], so
/// callers only ever catch [OCBrowseFilesException].
class OCMethodChannelBrowseFilesFlutter extends OCBrowseFilesFlutterPlatform {
  /// The channel carrying one-shot calls.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'com.kedtec.browse_files_flutter/methods',
  );

  @override
  Future<List<OCMediaItem>> pickMedia({
    Set<OCMediaType> types = kAllMediaTypes,
    bool allowMultiple = true,
  }) async {
    final names = _typeNames(types);
    return _guard(() async {
      final raw =
          await methodChannel.invokeListMethod<Object?>(
            'pickMedia',
            <String, Object?>{'types': names, 'allowMultiple': allowMultiple},
          ) ??
          const <Object?>[];
      return raw
          .cast<Map<Object?, Object?>>()
          .map(OCMediaItem.fromMap)
          .toList(growable: false);
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
        throw OCBrowseFilesException(
          OCBrowseFilesErrorCode.notFound,
          'The asset $id could not be resolved to a file.',
        );
      }
      return path;
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

  @override
  Future<OCMediaItem?> captureMedia({
    OCMediaType type = OCMediaType.image,
  }) async {
    return _guard(() async {
      final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
        'captureMedia',
        <String, Object?>{'type': type.name},
      );
      // A null reply is the user backing out of the camera, not a failure.
      return raw == null ? null : OCMediaItem.fromMap(raw);
    });
  }

  List<String> _typeNames(Set<OCMediaType> types) {
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
  /// [OCBrowseFilesException].
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on OCBrowseFilesException {
      rethrow;
    } catch (error) {
      throw _toBrowseFilesException(error);
    }
  }
}

/// Turns a channel error into the plugin's own exception type, so callers never
/// have to reason about [PlatformException] codes.
OCBrowseFilesException _toBrowseFilesException(Object error) => switch (error) {
  OCBrowseFilesException() => error,
  MissingPluginException() => OCBrowseFilesException(
    OCBrowseFilesErrorCode.unimplemented,
    error.message ??
        'This platform has no browse_files_flutter implementation.',
  ),
  PlatformException() => OCBrowseFilesException(
    OCBrowseFilesErrorCode.fromName(error.code),
    error.message ?? 'The media library call failed.',
    details: error.details?.toString(),
  ),
  _ => OCBrowseFilesException(OCBrowseFilesErrorCode.unknown, error.toString()),
};
