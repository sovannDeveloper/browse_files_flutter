import 'package:flutter/foundation.dart';

/// A file that is not a photo or a video: a PDF, a spreadsheet, a song.
///
/// Documents are not library assets and the platforms treat them nothing like
/// photos. [id] is a `MediaStore` id on Android and an absolute path on iOS,
/// so it means nothing across platforms — hand it back to `resolveFile` and
/// use the path that comes out.
@immutable
class OCDocumentItem {
  /// Creates a description of a file.
  const OCDocumentItem({
    required this.id,
    required this.name,
    this.mimeType,
    this.sizeBytes,
    this.modifiedAt,
    this.path,
  });

  /// Reconstructs an item from the platform channel representation.
  factory OCDocumentItem.fromMap(Map<Object?, Object?> map) {
    final modifiedAtMs = map['modifiedAtMs'] as int?;
    return OCDocumentItem(
      id: map['id']! as String,
      name: map['name'] as String? ?? '',
      mimeType: map['mimeType'] as String?,
      sizeBytes: map['sizeBytes'] as int?,
      modifiedAt: modifiedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modifiedAtMs),
      path: map['path'] as String?,
    );
  }

  /// A file the app already holds — what the system picker hands back.
  factory OCDocumentItem.fromPath(String path, {int? sizeBytes}) =>
      OCDocumentItem(
        id: path,
        name: path.split('/').last,
        sizeBytes: sizeBytes,
        path: path,
      );

  /// The platform's handle on this file.
  final String id;

  /// The file name, extension included.
  final String name;

  /// The MIME type, when the platform reported one.
  final String? mimeType;

  /// Size in bytes, when the platform reported one.
  final int? sizeBytes;

  /// When the file last changed, when the platform reported it.
  final DateTime? modifiedAt;

  /// A path the host app can already read, or `null` while the file is still
  /// only a platform handle.
  ///
  /// iOS can only ever list files this app holds, so those arrive resolved;
  /// Android hands back `MediaStore` rows that have to be copied out first.
  final String? path;

  /// Whether this file can be read without a trip through `resolveFile`.
  bool get isResolved => path != null;

  /// The lowercase extension without the dot, or an empty string.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// The channel representation, mirroring [DocumentItem.fromMap].
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'modifiedAtMs': modifiedAt?.millisecondsSinceEpoch,
    'path': path,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OCDocumentItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DocumentItem($id, $name)';
}
