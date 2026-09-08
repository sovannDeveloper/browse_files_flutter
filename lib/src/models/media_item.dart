import 'package:flutter/foundation.dart';

import 'media_type.dart';

/// One photo or video in the device's media library.
///
/// This is a description, not the bytes: [id] names the asset inside the
/// platform's library and is **not** a file path. Use `loadThumbnail` for a
/// grid tile, and `resolveFile` when the asset has to become a real file the
/// host app can read or upload.
@immutable
class OCMediaItem {
  /// Creates a description of a library asset.
  const OCMediaItem({
    required this.id,
    required this.type,
    required this.width,
    required this.height,
    required this.createdAt,
    this.duration,
    this.mimeType,
    this.name,
    this.sizeBytes,
  });

  /// Reconstructs an item from the platform channel representation.
  factory OCMediaItem.fromMap(Map<Object?, Object?> map) {
    final durationMs = map['durationMs'] as int?;
    return OCMediaItem(
      id: map['id']! as String,
      type: OCMediaType.fromName(map['type'] as String?),
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAtMs'] as int? ?? 0,
      ),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      mimeType: map['mimeType'] as String?,
      name: map['name'] as String?,
      sizeBytes: map['sizeBytes'] as int?,
    );
  }

  /// The library identifier: a `MediaStore` id on Android, a `PHAsset`
  /// `localIdentifier` on iOS.
  ///
  /// Stable enough to key a thumbnail cache and to re-resolve later, but it
  /// means nothing to `dart:io` — it is not a path.
  final String id;

  /// Whether this is an image or a video.
  final OCMediaType type;

  /// Pixel width of the asset, or `0` if the platform did not report one.
  final int width;

  /// Pixel height of the asset, or `0` if the platform did not report one.
  final int height;

  /// When the asset was created, used for the newest-first grid order.
  final DateTime createdAt;

  /// Playing time, for videos only. Always `null` for [OCMediaType.image].
  final Duration? duration;

  /// The asset's MIME type, when the platform reported one.
  final String? mimeType;

  /// The display name, usually the original file name.
  final String? name;

  /// Size in bytes, when the platform reported one.
  final int? sizeBytes;

  /// Whether this item is a video, and so carries a [duration] badge.
  bool get isVideo => type == OCMediaType.video;

  /// Width over height, or `1` when the platform reported no dimensions.
  double get aspectRatio => (width <= 0 || height <= 0) ? 1 : width / height;

  /// The channel representation, mirroring [MediaItem.fromMap].
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'type': type.name,
    'width': width,
    'height': height,
    'createdAtMs': createdAt.millisecondsSinceEpoch,
    'durationMs': duration?.inMilliseconds,
    'mimeType': mimeType,
    'name': name,
    'sizeBytes': sizeBytes,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OCMediaItem && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'MediaItem($id, ${type.name}, ${width}x$height)';
}
