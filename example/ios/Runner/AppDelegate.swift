import Flutter
import UIKit

/// Nothing to add: the camera and the pickers live in the plugin. What the host app owes is the
/// purpose strings in Info.plist — `NSCameraUsageDescription`, and `NSMicrophoneUsageDescription`
/// for video.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
