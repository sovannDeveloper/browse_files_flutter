import 'package:flutter/foundation.dart';

import 'document_item.dart';

/// One window onto the files the platform is willing to list.
@immutable
class DocumentPage {
  /// Creates a page of results.
  const DocumentPage({
    required this.items,
    required this.offset,
    required this.total,
    this.enumerable = true,
  });

  /// Reconstructs a page from the platform channel representation.
  factory DocumentPage.fromMap(Map<Object?, Object?> map) => DocumentPage(
    items: (map['items'] as List<Object?>? ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(DocumentItem.fromMap)
        .toList(growable: false),
    offset: map['offset'] as int? ?? 0,
    total: map['total'] as int? ?? 0,
    enumerable: map['enumerable'] as bool? ?? true,
  );

  /// A page with nothing in it.
  static const DocumentPage empty = DocumentPage(
    items: <DocumentItem>[],
    offset: 0,
    total: 0,
  );

  /// The files in this window, most recently changed first.
  final List<DocumentItem> items;

  /// The index of [items] first element within the whole list.
  final int offset;

  /// How many files the platform is willing to list in total.
  final int total;

  /// Whether this platform lists the device's files at all.
  ///
  /// `false` on iOS and on Android 11+, where scoped storage keeps everything
  /// but this app's own files behind the system picker. The Files tab says so
  /// rather than showing an empty list as if the device had no documents.
  final bool enumerable;

  /// Whether another page follows this one.
  bool get hasMore => offset + items.length < total;

  @override
  String toString() =>
      'DocumentPage(${items.length} of $total from $offset, '
      'enumerable: $enumerable)';
}
