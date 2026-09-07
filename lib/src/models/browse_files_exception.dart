/// Why a browse operation failed.
enum BrowseFilesErrorCode {
  /// The app may not read the media library. Check the permission status for
  /// whether prompting again is worth it.
  permissionDenied,

  /// The user dismissed the sheet or the system picker without choosing.
  userCanceled,

  /// The asset is gone — deleted, or on a volume that was unmounted between
  /// the grid being built and the file being resolved.
  notFound,

  /// The asset could not be read, decoded or copied into the cache.
  ioError,

  /// The platform cannot do what was asked, usually because the OS version
  /// predates the API involved.
  unsupported,

  /// The plugin has no implementation registered for this platform, or the
  /// method has not been written on the native side yet.
  unimplemented,

  /// Anything that did not map to a more specific code.
  unknown;

  /// Reads the wire representation used by the native side.
  static BrowseFilesErrorCode fromName(String? name) =>
      BrowseFilesErrorCode.values.firstWhere(
        (value) => value.name == name,
        orElse: () => BrowseFilesErrorCode.unknown,
      );
}

/// Error thrown by every call in this package.
///
/// Callers never see a raw `PlatformException` or `MissingPluginException`;
/// both are translated into this type at the channel boundary.
class BrowseFilesException implements Exception {
  /// Creates an exception describing a failed operation.
  const BrowseFilesException(this.code, this.message, {this.details});

  /// The machine-readable reason the operation failed.
  final BrowseFilesErrorCode code;

  /// A human-readable description, suitable for logs.
  final String message;

  /// Extra platform-supplied context, when there is any.
  final String? details;

  /// Whether this is the user backing out rather than a fault.
  ///
  /// Worth checking before showing an error UI — a dismissed document picker
  /// is a normal outcome.
  bool get isCancellation => code == BrowseFilesErrorCode.userCanceled;

  @override
  String toString() =>
      'BrowseFilesException(${code.name}): $message'
      '${details == null ? '' : ' ($details)'}';
}
