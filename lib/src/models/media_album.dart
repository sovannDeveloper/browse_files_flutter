import 'package:flutter/foundation.dart';

/// A bucket of media the user can switch the grid to — "Camera", "Screenshots",
/// "Downloads" on Android; a `PHAssetCollection` on iOS.
@immutable
class MediaAlbum {
  /// Creates an album description.
  const MediaAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.coverId,
    this.isAll = false,
  });

  /// Reconstructs an album from the platform channel representation.
  factory MediaAlbum.fromMap(Map<Object?, Object?> map) => MediaAlbum(
    id: map['id']! as String,
    name: map['name'] as String? ?? '',
    count: map['count'] as int? ?? 0,
    coverId: map['coverId'] as String?,
    isAll: map['isAll'] as bool? ?? false,
  );

  /// The platform's identifier for this album.
  final String id;

  /// The album's display name, as the OS localises it.
  final String name;

  /// How many items the album holds, for the header subtitle.
  final int count;

  /// The `MediaItem.id` of the album's cover asset, when it has one.
  final String? coverId;

  /// Whether this is the synthetic "all media" album the picker opens on.
  final bool isAll;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MediaAlbum && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MediaAlbum($id, $name, $count)';
}
