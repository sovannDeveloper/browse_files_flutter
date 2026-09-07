import Flutter
import Photos
import UIKit

/// The host app's half of the attachment sheet's camera cell.
///
/// browse_files_flutter carries no camera, so this opens the system one, saves the shot into
/// the photo library and hands Dart the asset's local identifier — an ordinary library id the
/// plugin can resolve like any other.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pendingResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.kedtec.browse_files_flutter_example/camera",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "capture":
          self?.capture(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func capture(result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "The camera is already open.", details: nil))
      return
    }
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      // The simulator lands here: there is no camera to open.
      result(FlutterError(code: "unsupported", message: "This device has no camera.", details: nil))
      return
    }
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = self
    pendingResult = result
    window?.rootViewController?.present(picker, animated: true)
  }

  /// Answers the waiting `capture` call exactly once.
  fileprivate func finishCapture(with identifier: String?) {
    let reply = pendingResult
    pendingResult = nil
    reply?(identifier)
  }
}

extension AppDelegate: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    guard let image = info[.originalImage] as? UIImage else {
      finishCapture(with: nil)
      return
    }
    var identifier: String?
    PHPhotoLibrary.shared().performChanges {
      let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
      identifier = request.placeholderForCreatedAsset?.localIdentifier
    } completionHandler: { saved, _ in
      DispatchQueue.main.async { self.finishCapture(with: saved ? identifier : nil) }
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    finishCapture(with: nil)
  }
}
