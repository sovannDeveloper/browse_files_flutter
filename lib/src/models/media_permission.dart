/// How much of the media library this app may read.
///
/// Photo access is not a yes/no on either platform any more: both can grant a
/// *subset* of the library, and the picker has to render that subset plus a way
/// to widen it rather than treating it as a refusal.
enum OCMediaPermissionStatus {
  /// The whole library is readable.
  granted,

  /// Only the assets the user picked are readable.
  ///
  /// Android 14+ (`READ_MEDIA_VISUAL_USER_SELECTED`) and iOS
  /// (`PHAuthorizationStatus.limited`). The grid shows the shared subset and
  /// offers `presentLimitedPicker` to add more.
  limited,

  /// Access was refused, but asking again is still allowed.
  denied,

  /// Access was refused for good; only system settings can change it.
  ///
  /// Android reports this after the user checks "don't ask again" or exhausts
  /// the two-prompt budget; iOS after a denial has been recorded.
  permanentlyDenied,

  /// A policy or parental control blocks access, so no prompt would help
  /// (iOS `restricted`).
  restricted,

  /// Nothing has been asked yet.
  notDetermined;

  /// Whether the grid can show anything at all.
  ///
  /// True for [limited] as well as [granted] — a partial library is still a
  /// library.
  bool get canBrowse =>
      this == OCMediaPermissionStatus.granted ||
      this == OCMediaPermissionStatus.limited;

  /// Whether prompting again is pointless and the user must go to Settings.
  bool get needsSettings =>
      this == OCMediaPermissionStatus.permanentlyDenied ||
      this == OCMediaPermissionStatus.restricted;

  /// Reads the wire representation, falling back to [denied] for anything
  /// unrecognised — the safe reading of an unclear answer.
  static OCMediaPermissionStatus fromName(String? name) =>
      OCMediaPermissionStatus.values.firstWhere(
        (value) => value.name == name,
        orElse: () => OCMediaPermissionStatus.denied,
      );
}
