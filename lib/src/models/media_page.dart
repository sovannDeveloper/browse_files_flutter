import 'package:flutter/foundation.dart';

import 'media_item.dart';

/// One window onto an album, as returned by a paged fetch.
///
/// The grid never asks for a whole library at once — a page carries the items
/// it asked for plus [total], so the grid can size its scroll extent without a
/// second count call.
@immutable
class MediaPage {
  /// Creates a page of results.
  const MediaPage({
    required this.items,
    required this.offset,
    required this.total,
  });

  /// Reconstructs a page from the platform channel representation.
  factory MediaPage.fromMap(Map<Object?, Object?> map) => MediaPage(
    items: (map['items'] as List<Object?>? ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(MediaItem.fromMap)
        .toList(growable: false),
    offset: map['offset'] as int? ?? 0,
    total: map['total'] as int? ?? 0,
  );

  /// A page with nothing in it, for the empty and permission-denied states.
  static const MediaPage empty = MediaPage(
    items: <MediaItem>[],
    offset: 0,
    total: 0,
  );

  /// The items in this window, newest first.
  final List<MediaItem> items;

  /// The index of [items] first element within the album.
  final int offset;

  /// How many items the album holds in total.
  final int total;

  /// Whether another page follows this one.
  bool get hasMore => offset + items.length < total;

  @override
  String toString() => 'MediaPage(${items.length} of $total from $offset)';
}
