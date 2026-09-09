import 'package:flutter/material.dart';

/// One entry in the sheet's bottom row of attachment kinds.
///
/// Telegram's row is Gallery · File · Location · Article · Poll · Contact, but
/// only the first two are this package's business. The rest are extension
/// points: hand [AttachmentTab.custom] a [builder] and the host app owns that
/// tab's body entirely.
@immutable
class OCAttachmentTab {
  const OCAttachmentTab._({
    required this.id,
    required this.label,
    required this.icon,
    this.builder,
    this.badge,
  });

  /// A tab whose body the host app builds — anything this package deliberately
  /// does not implement.
  const OCAttachmentTab.custom({
    required this.id,
    required this.label,
    required this.icon,
    required WidgetBuilder this.builder,
    this.badge,
  });

  /// Telegram's Location tab. The map is the host app's to draw.
  const OCAttachmentTab.location({
    required WidgetBuilder this.builder,
    this.label = 'Location',
    this.badge,
  }) : id = locationId,
       icon = Icons.location_on_outlined;

  /// Telegram's Article tab, the one that carries a badge in their UI.
  const OCAttachmentTab.article({
    required WidgetBuilder this.builder,
    this.label = 'Article',
    this.badge,
  }) : id = articleId,
       icon = Icons.article_outlined;

  /// Telegram's Poll tab.
  const OCAttachmentTab.poll({
    required WidgetBuilder this.builder,
    this.label = 'Poll',
    this.badge,
  }) : id = pollId,
       icon = Icons.bar_chart;

  /// Telegram's Contact tab.
  const OCAttachmentTab.contact({
    required WidgetBuilder this.builder,
    this.label = 'Contact',
    this.badge,
  }) : id = contactId,
       icon = Icons.person_outline;

  /// The device's photos and videos, in a grid.
  static const OCAttachmentTab gallery = OCAttachmentTab._(
    id: galleryId,
    label: 'Gallery',
    icon: Icons.photo_library_outlined,
  );

  /// The system document picker.
  static const OCAttachmentTab file = OCAttachmentTab._(
    id: fileId,
    label: 'File',
    icon: Icons.insert_drive_file_outlined,
  );

  /// The [id] of the built-in [gallery] tab.
  static const String galleryId = 'gallery';

  /// The [id] of the built-in [file] tab.
  static const String fileId = 'file';

  /// The [id] of [AttachmentTab.location].
  static const String locationId = 'location';

  /// The [id] of [AttachmentTab.article].
  static const String articleId = 'article';

  /// The [id] of [AttachmentTab.poll].
  static const String pollId = 'poll';

  /// The [id] of [AttachmentTab.contact].
  static const String contactId = 'contact';

  /// The two tabs this package implements, in Telegram's order.
  static const List<OCAttachmentTab> defaults = <OCAttachmentTab>[
    gallery,
    file,
  ];

  /// Identifies the tab; also what `initialTabId` selects.
  final String id;

  /// The caption under the icon.
  final String label;

  /// The glyph above the caption.
  final IconData icon;

  /// Builds this tab's body, or `null` for the two tabs this package
  /// implements itself.
  final WidgetBuilder? builder;

  /// A small marker drawn over the tab's icon — Telegram puts a star on
  /// Article. Usually a tiny [Icon] or a coloured dot.
  final Widget? badge;

  /// Whether this package draws this tab's body.
  bool get isBuiltIn => builder == null;

  /// The same tab under another caption.
  ///
  /// The row's captions live on the tabs rather than in
  /// [OCBrowseFilesStrings], so this is how the built-in [gallery] and [file]
  /// tabs get localised:
  ///
  /// ```dart
  /// tabs: <OCAttachmentTab>[
  ///   OCAttachmentTab.gallery.withLabel('Galerie'),
  ///   OCAttachmentTab.file.withLabel('Fichier'),
  /// ],
  /// ```
  ///
  /// The [id] is untouched, so a relabelled built-in tab still gets its body
  /// from this package.
  OCAttachmentTab withLabel(String label) => OCAttachmentTab._(
    id: id,
    label: label,
    icon: icon,
    builder: builder,
    badge: badge,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OCAttachmentTab && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AttachmentTab($id)';
}
