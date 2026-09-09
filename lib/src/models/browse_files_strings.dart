import 'package:flutter/foundation.dart';

/// Every piece of text the sheet draws, so a host app can localise it or word
/// it its own way.
///
/// Hand one to [OCBrowseFilesOptions.strings]; anything left out keeps the
/// English default:
///
/// ```dart
/// OCBrowseFiles.show(
///   context,
///   options: const OCBrowseFilesOptions(
///     strings: OCBrowseFilesStrings(
///       confirmLabel: 'Envoyer',
///       permissionAllowLabel: 'Autoriser',
///     ),
///   ),
/// );
/// ```
///
/// The captions in the bottom tab row are not here: they belong to the tabs
/// themselves, so rename them with [OCAttachmentTab.withLabel].
@immutable
class OCBrowseFilesStrings {
  /// Creates a set of strings; every one of them has an English default.
  const OCBrowseFilesStrings({
    this.pageTitle = 'Attach',
    this.mediaTabLabel = 'Photos & videos',
    this.documentTabLabel = 'Files',
    this.confirmLabel = 'Select',
    this.confirmButton = _confirmButton,
    this.selectionSummary = _selectionSummary,
    this.albumMenuTooltip = 'Choose an album',
    this.albumItemCount = _albumItemCount,
    this.limitedAccessMessage = 'You shared some of your library',
    this.selectMoreLabel = 'Select more',
    this.permissionTitle = 'Let this app see your photos',
    this.permissionDetail =
        'Your photos and videos stay on the device; nothing is uploaded by '
        'this sheet.',
    this.permissionAllowLabel = 'Allow access',
    this.permissionDeniedTitle = 'Photo access is turned off',
    this.permissionDeniedDetail =
        'Turn photo access on in Settings and come back.',
    this.openSettingsLabel = 'Open settings',
    this.galleryErrorTitle = 'The library could not be read',
    this.retryLabel = 'Try again',
    this.galleryEmptyTitle = 'Nothing here yet',
    this.galleryEmptyDetail =
        'Photos and videos on this device show up in this grid.',
    this.storagePickerTitle = 'Internal Storage',
    this.storagePickerSubtitle = 'Browse your file system',
    this.recentFilesTitle = 'Recent files',
    this.recentFilesOnlyDetail =
        'The system keeps the rest of your storage behind its own picker: '
        'Android 11 scoped it and iOS never opened it. Tap Internal '
        'Storage to reach anything that is not listed here.',
    this.noRecentFiles = 'No recent files — open Internal Storage to pick one.',
    this.unknownFileType = 'file',
  });

  /// The full-screen browser's app bar title.
  final String pageTitle;

  /// The full-screen browser's first tab: the media grid.
  final String mediaTabLabel;

  /// The full-screen browser's second tab: the file list.
  final String documentTabLabel;

  /// The word on the confirm button, before [confirmButton] adds the count.
  final String confirmLabel;

  /// Builds the confirm button's caption out of [confirmLabel] and how many
  /// things are selected — `Select (3)` by default.
  final String Function(String label, int count) confirmButton;

  /// The line beside the confirm button: what is selected, and the cap.
  final String Function(int media, int documents, int maxSelection)
  selectionSummary;

  /// The long-press label on the album selector.
  final String albumMenuTooltip;

  /// How many assets the open album holds — `1 item` / `24 items`.
  final String Function(int count) albumItemCount;

  /// The banner shown when the user shared only part of their library.
  final String limitedAccessMessage;

  /// The banner's action: widen a partial grant.
  final String selectMoreLabel;

  /// Asking for library access, when the prompt is still available.
  final String permissionTitle;

  /// The reassurance under [permissionTitle].
  final String permissionDetail;

  /// The button that raises the OS permission prompt.
  final String permissionAllowLabel;

  /// Access was refused for good and only Settings can undo it.
  final String permissionDeniedTitle;

  /// The instructions under [permissionDeniedTitle].
  final String permissionDeniedDetail;

  /// The button that opens this app's page in system settings.
  final String openSettingsLabel;

  /// Heading of the panel that replaces the grid when a page failed to load.
  ///
  /// The platform's own message is shown under it, untouched.
  final String galleryErrorTitle;

  /// The action on that panel.
  final String retryLabel;

  /// Heading shown when the library holds nothing of the requested types.
  final String galleryEmptyTitle;

  /// The line under [galleryEmptyTitle].
  final String galleryEmptyDetail;

  /// The row at the top of the Files tab that opens the system picker.
  final String storagePickerTitle;

  /// The line under [storagePickerTitle].
  final String storagePickerSubtitle;

  /// Heading over the files the platform will list by itself.
  final String recentFilesTitle;

  /// Why that listing is not the whole device, shown only when the platform
  /// says it cannot enumerate storage.
  final String recentFilesOnlyDetail;

  /// Shown when that listing came back empty.
  final String noRecentFiles;

  /// A file's subtitle when the platform gave neither size nor date.
  final String unknownFileType;

  /// A copy of these strings with the given ones replaced.
  OCBrowseFilesStrings copyWith({
    String? pageTitle,
    String? mediaTabLabel,
    String? documentTabLabel,
    String? confirmLabel,
    String Function(String label, int count)? confirmButton,
    String Function(int media, int documents, int maxSelection)?
    selectionSummary,
    String? albumMenuTooltip,
    String Function(int count)? albumItemCount,
    String? limitedAccessMessage,
    String? selectMoreLabel,
    String? permissionTitle,
    String? permissionDetail,
    String? permissionAllowLabel,
    String? permissionDeniedTitle,
    String? permissionDeniedDetail,
    String? openSettingsLabel,
    String? galleryErrorTitle,
    String? retryLabel,
    String? galleryEmptyTitle,
    String? galleryEmptyDetail,
    String? storagePickerTitle,
    String? storagePickerSubtitle,
    String? recentFilesTitle,
    String? recentFilesOnlyDetail,
    String? noRecentFiles,
    String? unknownFileType,
  }) => OCBrowseFilesStrings(
    pageTitle: pageTitle ?? this.pageTitle,
    mediaTabLabel: mediaTabLabel ?? this.mediaTabLabel,
    documentTabLabel: documentTabLabel ?? this.documentTabLabel,
    confirmLabel: confirmLabel ?? this.confirmLabel,
    confirmButton: confirmButton ?? this.confirmButton,
    selectionSummary: selectionSummary ?? this.selectionSummary,
    albumMenuTooltip: albumMenuTooltip ?? this.albumMenuTooltip,
    albumItemCount: albumItemCount ?? this.albumItemCount,
    limitedAccessMessage: limitedAccessMessage ?? this.limitedAccessMessage,
    selectMoreLabel: selectMoreLabel ?? this.selectMoreLabel,
    permissionTitle: permissionTitle ?? this.permissionTitle,
    permissionDetail: permissionDetail ?? this.permissionDetail,
    permissionAllowLabel: permissionAllowLabel ?? this.permissionAllowLabel,
    permissionDeniedTitle: permissionDeniedTitle ?? this.permissionDeniedTitle,
    permissionDeniedDetail:
        permissionDeniedDetail ?? this.permissionDeniedDetail,
    openSettingsLabel: openSettingsLabel ?? this.openSettingsLabel,
    galleryErrorTitle: galleryErrorTitle ?? this.galleryErrorTitle,
    retryLabel: retryLabel ?? this.retryLabel,
    galleryEmptyTitle: galleryEmptyTitle ?? this.galleryEmptyTitle,
    galleryEmptyDetail: galleryEmptyDetail ?? this.galleryEmptyDetail,
    storagePickerTitle: storagePickerTitle ?? this.storagePickerTitle,
    storagePickerSubtitle: storagePickerSubtitle ?? this.storagePickerSubtitle,
    recentFilesTitle: recentFilesTitle ?? this.recentFilesTitle,
    recentFilesOnlyDetail: recentFilesOnlyDetail ?? this.recentFilesOnlyDetail,
    noRecentFiles: noRecentFiles ?? this.noRecentFiles,
    unknownFileType: unknownFileType ?? this.unknownFileType,
  );

  @override
  String toString() => 'OCBrowseFilesStrings($confirmLabel)';
}

String _confirmButton(String label, int count) => '$label ($count)';

String _selectionSummary(int media, int documents, int maxSelection) =>
    '$media media · $documents files (max $maxSelection)';

String _albumItemCount(int count) => count == 1 ? '1 item' : '$count items';
