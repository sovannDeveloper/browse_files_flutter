import 'package:flutter/foundation.dart';

import 'media_item.dart';

/// What the sheet was closed with.
///
/// The two tabs hand back different things and neither can stand in for the
/// other: [media] are library assets that still have to be resolved to files,
/// while [documents] are already cached paths, because a SAF URI and an iOS
/// security-scoped URL cannot be handed to the host app as they are.
@immutable
class BrowseFilesResult {
  /// Creates a result; both lists default to empty.
  const BrowseFilesResult({
    this.media = const <MediaItem>[],
    this.documents = const <String>[],
  });

  /// A result carrying nothing, for a sheet that was dismissed.
  static const BrowseFilesResult empty = BrowseFilesResult();

  /// The chosen library assets, in the order the user picked them.
  ///
  /// These are descriptions, not files: call `resolveFile` with an item's id
  /// when the host app needs bytes on disk.
  final List<MediaItem> media;

  /// Paths of the documents chosen through the File tab, already copied into
  /// the app cache.
  final List<String> documents;

  /// Whether the user picked nothing at all.
  bool get isEmpty => media.isEmpty && documents.isEmpty;

  /// Whether the user picked anything.
  bool get isNotEmpty => !isEmpty;

  /// How many things were picked, of both kinds.
  int get length => media.length + documents.length;

  @override
  String toString() =>
      'BrowseFilesResult(${media.length} media, ${documents.length} documents)';
}
