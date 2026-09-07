import 'package:flutter/services.dart';

/// The host app's half of the sheet's camera cell.
///
/// `browse_files_flutter` has no camera in it on purpose — the sheet calls
/// back through `BrowseFilesOptions.onCameraTap` and an app that already has a
/// camera opens its own. This is what that looks like: a channel of the
/// example app's own, backed by the system camera on both platforms.
///
/// The shot is written straight into the photo library, so what comes back is
/// an id the plugin can resolve like any other asset.
class ExampleCamera {
  /// Creates the camera facade.
  const ExampleCamera();

  static const MethodChannel _channel = MethodChannel(
    'com.kedtec.browse_files_flutter_example/camera',
  );

  /// Opens the system camera.
  ///
  /// Resolves to the library id of the photo taken, or `null` if the user
  /// backed out. Throws [PlatformException] when there is no camera to open.
  Future<String?> capture() => _channel.invokeMethod<String>('capture');
}
