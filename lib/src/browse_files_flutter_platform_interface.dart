import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'browse_files_flutter_method_channel.dart';
import 'models/camera_permission.dart';
import 'models/media_item.dart';
import 'models/media_type.dart';

/// Every media type the picker knows about — the default filter.
const Set<OCMediaType> kAllMediaTypes = {OCMediaType.image, OCMediaType.video};

/// The interface every platform implementation of `browse_files_flutter`
/// fulfils.
///
/// Platform implementations should extend this class rather than implement it,
/// so that new members can be added without breaking them.
///
/// The whole API is deliberately low-level: picking goes through the
/// platform's system picker (Android Photo Picker / iOS PHPickerViewController
/// / Android SAF), so the plugin never declares any media permission.
/// Thumbnails and file materialisation are fetched one asset at a time, and
/// files are only copied out of the picker grant on demand. The sheet UI is a
/// consumer of this interface, never a peer of it.
abstract class OCBrowseFilesFlutterPlatform extends PlatformInterface {
  /// Constructs a platform implementation.
  OCBrowseFilesFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static OCBrowseFilesFlutterPlatform _instance =
      OCMethodChannelBrowseFilesFlutter();

  /// The default instance to use.
  ///
  /// Defaults to [OCMethodChannelBrowseFilesFlutter].
  static OCBrowseFilesFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [OCBrowseFilesFlutterPlatform] when
  /// they register themselves.
  static set instance(OCBrowseFilesFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Opens the system media picker and returns what the user chose.
  ///
  /// On Android 13+ this is the Photo Picker (`ACTION_PICK_IMAGES`), below
  /// that the legacy `ACTION_GET_CONTENT` — neither requires a permission.
  /// On iOS the PHPickerViewController is used. Resolves to an empty list
  /// when the user dismissed the picker.
  ///
  /// The id of every returned [OCMediaItem] is a content URI (Android) or an
  /// asset identifier (iOS). It is **not** a file path: pass it to
  /// [loadThumbnail] for a grid tile and to [resolveFile] when the host app
  /// needs bytes on disk.
  Future<List<OCMediaItem>> pickMedia({
    Set<OCMediaType> types = kAllMediaTypes,
    bool allowMultiple = true,
  }) {
    throw UnimplementedError('pickMedia() has not been implemented.');
  }

  /// A JPEG thumbnail for one asset, sized to roughly [width] x [height]
  /// pixels, or `null` if the platform could not produce one.
  ///
  /// Decoding happens natively and off the main thread. Callers are expected
  /// to cache the result; this method does no caching of its own.
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) {
    throw UnimplementedError('loadThumbnail() has not been implemented.');
  }

  /// Materialises an asset as a real file and returns its path.
  ///
  /// The id comes from [pickMedia]: it is a content URI on Android or a
  /// PHAsset local identifier on iOS. The asset is copied into the app cache
  /// so the host app gets a file it owns; the original picker grant can be
  /// revoked later without affecting that copy.
  Future<String> resolveFile(String id) {
    throw UnimplementedError('resolveFile() has not been implemented.');
  }

  /// Opens the system document picker and returns cached paths for what the
  /// user chose, or an empty list if they dismissed it.
  ///
  /// Backed by the Storage Access Framework on Android and
  /// `UIDocumentPickerViewController` on iOS. The picked documents are copied
  /// into the app cache, because a SAF URI and a security-scoped iOS URL are
  /// neither of them usable as a path.
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) {
    throw UnimplementedError('pickDocuments() has not been implemented.');
  }

  /// Opens the system camera to take a photo or record a video, and returns
  /// the capture — or `null` if the user backed out.
  ///
  /// `ACTION_IMAGE_CAPTURE` / `ACTION_VIDEO_CAPTURE` on Android,
  /// `UIImagePickerController` with the camera source on iOS. The capture is
  /// written straight into the app cache rather than the user's library, so
  /// no storage or photo permission is involved; the returned item's id is
  /// already a resolved file and [resolveFile] hands it straight back.
  ///
  /// iOS needs `NSCameraUsageDescription` in the host's Info.plist, and
  /// `NSMicrophoneUsageDescription` too for video. Without them iOS kills the
  /// app when the camera opens.
  Future<OCMediaItem?> captureMedia({OCMediaType type = OCMediaType.image}) {
    throw UnimplementedError('captureMedia() has not been implemented.');
  }

  /// Makes sure the camera may be opened for [type], prompting the user if
  /// the platform has not asked yet, and reports where that left things.
  ///
  /// Android: the capture intent needs no permission unless the host app
  /// declares `CAMERA` in its own manifest — then the intent refuses to start
  /// until it is granted, so this checks and requests it. Without the
  /// declaration the answer is [OCCameraPermission.granted] straight away.
  /// iOS: `AVCaptureDevice` authorization for the camera, plus the
  /// microphone for video (a refused microphone does not block; the clip is
  /// silent). A missing `NSCameraUsageDescription` /
  /// `NSMicrophoneUsageDescription` fails with `unsupported`, the same as
  /// [captureMedia], rather than letting iOS kill the app.
  Future<OCCameraPermission> requestCameraPermission({
    OCMediaType type = OCMediaType.image,
  }) {
    throw UnimplementedError(
      'requestCameraPermission() has not been implemented.',
    );
  }
}
