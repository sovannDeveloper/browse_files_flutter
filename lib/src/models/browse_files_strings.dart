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
///       galleryEmptyActionLabel: 'Choisir',
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
    this.galleryEmptyTitle = 'Nothing picked yet',
    this.galleryEmptyDetail =
        'Photos and videos you pick land here, in the order you pick them.',
    this.galleryEmptyActionLabel = 'Select photos & videos',
    this.gallerySelectMoreLabel = 'Select more',
    this.galleryErrorTitle = 'The picker could not be opened',
    this.retryLabel = 'Try again',
    this.storagePickerTitle = 'Internal Storage',
    this.storagePickerSubtitle = 'Browse your file system',
    this.unknownFileType = 'file',
    this.actionsTitle = 'Attach',
    this.takePhotoLabel = 'Take photo',
    this.recordVideoLabel = 'Record video',
    this.selectMediaLabel = 'Select photos & videos',
    this.selectFilesLabel = 'Select files',
    this.cameraErrorTitle = 'The camera could not be opened',
    this.cameraPermissionDenied =
        'Allow camera access in Settings to take photos and record videos.',
  });

  /// The full-screen browser's app bar title.
  final String pageTitle;

  /// The full-screen browser's first tab: the gallery.
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

  /// Heading shown when nothing has been picked yet.
  final String galleryEmptyTitle;

  /// The line under [galleryEmptyTitle].
  final String galleryEmptyDetail;

  /// The label on the button that opens the system Photo Picker.
  final String galleryEmptyActionLabel;

  /// The label on the button that adds more picks to an existing selection.
  final String gallerySelectMoreLabel;

  /// Heading of the panel shown when the picker fails to open.
  final String galleryErrorTitle;

  /// The action on that panel.
  final String retryLabel;

  /// The row at the top of the Files tab that opens the system picker.
  final String storagePickerTitle;

  /// The line under [storagePickerTitle].
  final String storagePickerSubtitle;

  /// A file's subtitle when the platform gave neither size nor date.
  final String unknownFileType;

  /// The heading of the short menu `OCBrowseFiles.showActions` opens.
  final String actionsTitle;

  /// The camera row that takes a photo — in the menu and in the choice the
  /// sheet's camera tile offers when both kinds are allowed.
  final String takePhotoLabel;

  /// The camera row that records a video.
  final String recordVideoLabel;

  /// The menu row that opens the system media picker.
  final String selectMediaLabel;

  /// The menu row that opens the system document picker.
  final String selectFilesLabel;

  /// Heading of the panel shown when the camera fails to open.
  final String cameraErrorTitle;

  /// Body of that panel when the user refused camera access — also the
  /// message of the `permissionDenied` exception `showActions` throws.
  final String cameraPermissionDenied;

  /// A copy of these strings with the given ones replaced.
  OCBrowseFilesStrings copyWith({
    String? pageTitle,
    String? mediaTabLabel,
    String? documentTabLabel,
    String? confirmLabel,
    String Function(String label, int count)? confirmButton,
    String Function(int media, int documents, int maxSelection)?
    selectionSummary,
    String? galleryEmptyTitle,
    String? galleryEmptyDetail,
    String? galleryEmptyActionLabel,
    String? gallerySelectMoreLabel,
    String? galleryErrorTitle,
    String? retryLabel,
    String? storagePickerTitle,
    String? storagePickerSubtitle,
    String? unknownFileType,
    String? actionsTitle,
    String? takePhotoLabel,
    String? recordVideoLabel,
    String? selectMediaLabel,
    String? selectFilesLabel,
    String? cameraErrorTitle,
    String? cameraPermissionDenied,
  }) => OCBrowseFilesStrings(
    pageTitle: pageTitle ?? this.pageTitle,
    mediaTabLabel: mediaTabLabel ?? this.mediaTabLabel,
    documentTabLabel: documentTabLabel ?? this.documentTabLabel,
    confirmLabel: confirmLabel ?? this.confirmLabel,
    confirmButton: confirmButton ?? this.confirmButton,
    selectionSummary: selectionSummary ?? this.selectionSummary,
    galleryEmptyTitle: galleryEmptyTitle ?? this.galleryEmptyTitle,
    galleryEmptyDetail: galleryEmptyDetail ?? this.galleryEmptyDetail,
    galleryEmptyActionLabel:
        galleryEmptyActionLabel ?? this.galleryEmptyActionLabel,
    gallerySelectMoreLabel:
        gallerySelectMoreLabel ?? this.gallerySelectMoreLabel,
    galleryErrorTitle: galleryErrorTitle ?? this.galleryErrorTitle,
    retryLabel: retryLabel ?? this.retryLabel,
    storagePickerTitle: storagePickerTitle ?? this.storagePickerTitle,
    storagePickerSubtitle: storagePickerSubtitle ?? this.storagePickerSubtitle,
    unknownFileType: unknownFileType ?? this.unknownFileType,
    actionsTitle: actionsTitle ?? this.actionsTitle,
    takePhotoLabel: takePhotoLabel ?? this.takePhotoLabel,
    recordVideoLabel: recordVideoLabel ?? this.recordVideoLabel,
    selectMediaLabel: selectMediaLabel ?? this.selectMediaLabel,
    selectFilesLabel: selectFilesLabel ?? this.selectFilesLabel,
    cameraErrorTitle: cameraErrorTitle ?? this.cameraErrorTitle,
    cameraPermissionDenied:
        cameraPermissionDenied ?? this.cameraPermissionDenied,
  );

  @override
  String toString() => 'OCBrowseFilesStrings($confirmLabel)';
}

String _confirmButton(String label, int count) => '$label ($count)';

String _selectionSummary(int media, int documents, int maxSelection) =>
    '$media media · $documents files (max $maxSelection)';
