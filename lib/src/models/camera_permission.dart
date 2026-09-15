/// Where the app stands with the camera, as answered by
/// `requestCameraPermission`.
///
/// Only the camera is reported. Recording a video also asks for the
/// microphone on iOS, but a refused microphone does not block the capture —
/// the clip is simply silent.
enum OCCameraPermission {
  /// The camera may be opened. Also the answer on Android when the host app
  /// declares no `CAMERA` permission at all: the capture intent needs none.
  granted,

  /// The user refused this time; asking again may show the prompt again.
  denied,

  /// The user refused for good, or a policy forbids the camera. The only way
  /// back is the system Settings app.
  permanentlyDenied;

  /// Whether the camera may be opened.
  bool get isGranted => this == OCCameraPermission.granted;

  /// Reads the wire representation used by the native side; anything
  /// unrecognised counts as [denied].
  static OCCameraPermission fromName(String? name) =>
      OCCameraPermission.values.firstWhere(
        (value) => value.name == name,
        orElse: () => OCCameraPermission.denied,
      );
}
