import Flutter
import Photos
// presentLimitedLibraryPicker lives in PhotosUI, not Photos.
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// iOS side of `browse_files_flutter`.
///
/// `.limited` is a grant, not a refusal: the user shared part of the library and
/// `presentLimitedLibraryPicker` widens it.
///
/// Library reads run off the main thread and reply on it; the queries themselves live in
/// `PhotoLibraryReader`.
///
/// The host app must carry `NSPhotoLibraryUsageDescription` in its Info.plist, or iOS kills
/// the app the moment access is requested. See `example/ios/Runner/Info.plist`.
///
/// Errors come back as `FlutterError(code:message:details:)` with a code from
/// BrowseFilesErrorCode: permissionDenied, userCanceled, notFound, ioError, unsupported.
public class BrowseFilesFlutterPlugin: NSObject, FlutterPlugin {
  /// The reply waiting on the system document picker, and the picker keeping itself alive.
  private var pendingDocuments: FlutterResult?
  private var documentPicker: UIDocumentPickerViewController?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.kedtec.browse_files_flutter/methods",
      binaryMessenger: registrar.messenger())
    let instance = BrowseFilesFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permissionStatus":
      result(Self.name(of: Self.authorization()))
    case "requestPermission":
      requestPermission(result: result)
    case "presentLimitedPicker":
      presentLimitedPicker(result: result)
    case "openSettings":
      openSettings(result: result)
    case "fetchAlbums":
      let types = Self.types(from: call)
      onLibrary(result) { PhotoLibraryReader.fetchAlbums(types: types) }
    case "fetchMedia":
      let arguments = call.arguments as? [String: Any] ?? [:]
      let types = Self.types(from: call)
      let albumId = arguments["albumId"] as? String
      let offset = arguments["offset"] as? Int ?? 0
      let limit = arguments["limit"] as? Int ?? 50
      onLibrary(result) {
        PhotoLibraryReader.fetchMedia(types: types, albumId: albumId, offset: offset, limit: limit)
      }
    case "loadThumbnail":
      loadThumbnail(call, result: result)
    case "resolveFile":
      resolveFile(call, result: result)
    case "fetchDocuments":
      let arguments = call.arguments as? [String: Any] ?? [:]
      let mimeTypes = arguments["mimeTypes"] as? [String] ?? []
      let offset = arguments["offset"] as? Int ?? 0
      let limit = arguments["limit"] as? Int ?? 50
      onLibrary(result) {
        DocumentLibrary.fetchDocuments(mimeTypes: mimeTypes, offset: offset, limit: limit)
      }
    case "pickDocuments":
      pickDocuments(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Prompts once; iOS answers straight away with the recorded decision after that.
  private func requestPermission(result: @escaping FlutterResult) {
    let reply: (PHAuthorizationStatus) -> Void = { status in
      DispatchQueue.main.async { result(Self.name(of: status)) }
    }
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: reply)
    } else {
      PHPhotoLibrary.requestAuthorization(reply)
    }
  }

  /// Shows the system sheet that widens a `.limited` grant, then reports where it left things.
  private func presentLimitedPicker(result: @escaping FlutterResult) {
    guard #available(iOS 14, *) else {
      result(
        FlutterError(
          code: "unsupported",
          message: "Limited library access needs iOS 14 or newer.", details: nil))
      return
    }
    guard Self.authorization() == .limited else {
      result(
        FlutterError(
          code: "unsupported",
          message: "The limited-library picker only opens while access is limited.", details: nil))
      return
    }
    guard let controller = Self.topViewController() else {
      result(
        FlutterError(
          code: "unsupported",
          message: "There is no view controller to present the picker from.", details: nil))
      return
    }
    if #available(iOS 15, *) {
      PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) { _ in
        DispatchQueue.main.async { result(Self.name(of: Self.authorization())) }
      }
    } else {
      PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
      // Pre-iOS 15 there is no completion handler, so this reports the level as it stands;
      // the caller re-checks when the app comes back to the foreground.
      result(Self.name(of: Self.authorization()))
    }
  }

  private func openSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    DispatchQueue.main.async {
      guard UIApplication.shared.canOpenURL(url) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        DispatchQueue.main.async { result(opened) }
      }
    }
  }

  private func loadThumbnail(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let id = arguments["id"] as? String else {
      result(
        FlutterError(code: "notFound", message: "loadThumbnail needs an asset id.", details: nil))
      return
    }
    let width = arguments["width"] as? Int ?? 256
    let height = arguments["height"] as? Int ?? 256
    let quality = arguments["quality"] as? Int ?? 80
    PhotoLibraryReader.loadThumbnail(id: id, width: width, height: height, quality: quality) {
      data in
      DispatchQueue.main.async {
        result(data.map { FlutterStandardTypedData(bytes: $0) })
      }
    }
  }

  private func resolveFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let id = arguments["id"] as? String else {
      result(FlutterError(code: "notFound", message: "resolveFile needs an asset id.", details: nil))
      return
    }
    // A nil path crosses the channel as notFound, which is what a missing asset is.
    PhotoLibraryReader.resolveFile(id: id) { path in
      DispatchQueue.main.async { result(path) }
    }
  }

  /// Opens the system document picker; browsing storage ourselves is not this package's job.
  private func pickDocuments(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let mimeTypes = arguments["mimeTypes"] as? [String] ?? []
    let allowMultiple = arguments["allowMultiple"] as? Bool ?? true
    guard pendingDocuments == nil else {
      result(FlutterError(code: "unknown", message: "A document picker is already open.", details: nil))
      return
    }
    guard let host = Self.topViewController() else {
      result(
        FlutterError(
          code: "unsupported", message: "There is no view controller to present the picker from.",
          details: nil))
      return
    }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14, *) {
      let types = Self.contentTypes(for: mimeTypes)
      picker = UIDocumentPickerViewController(
        forOpeningContentTypes: types.isEmpty ? [.item] : types, asCopy: true)
    } else {
      // Pre-iOS 14 the picker takes UTIs rather than MIME types, so the filter is dropped
      // rather than guessed at.
      picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
    }
    picker.allowsMultipleSelection = allowMultiple
    picker.delegate = self
    pendingDocuments = result
    documentPicker = picker
    host.present(picker, animated: true)
  }

  /// The content types the picker should offer for a list of MIME types.
  ///
  /// `UTType(mimeType:)` cannot read a wildcard, so `image/*` and friends are mapped to the
  /// family's supertype by hand; `*/*` means everything.
  @available(iOS 14, *)
  private static func contentTypes(for mimeTypes: [String]) -> [UTType] {
    var types: [UTType] = []
    for mime in mimeTypes {
      if mime == "*/*" { return [.item] }
      if mime.hasSuffix("/*") {
        switch String(mime.dropLast(2)) {
        case "image": types.append(.image)
        case "video": types.append(.movie)
        case "audio": types.append(.audio)
        case "text": types.append(.text)
        default: break
        }
      } else if let type = UTType(mimeType: mime) {
        types.append(type)
      }
    }
    return types
  }

  /// Runs a library read off the main thread and replies on it.
  private func onLibrary(_ result: @escaping FlutterResult, work: @escaping () -> Any?) {
    DispatchQueue.global(qos: .userInitiated).async {
      let value = work()
      DispatchQueue.main.async { result(value) }
    }
  }

  private static func types(from call: FlutterMethodCall) -> Set<String> {
    let arguments = call.arguments as? [String: Any] ?? [:]
    return Set(arguments["types"] as? [String] ?? ["image", "video"])
  }

  /// Answers the waiting `pickDocuments` call exactly once.
  fileprivate func finishDocuments(with paths: [String]) {
    let reply = pendingDocuments
    pendingDocuments = nil
    documentPicker = nil
    reply?(paths)
  }

  private static func authorization() -> PHAuthorizationStatus {
    if #available(iOS 14, *) {
      return PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    return PHPhotoLibrary.authorizationStatus()
  }

  /// The MediaPermissionStatus name the Dart side expects.
  ///
  /// `.denied` maps to `permanentlyDenied`: iOS records the answer and never prompts again,
  /// so only Settings can change it.
  private static func name(of status: PHAuthorizationStatus) -> String {
    if #available(iOS 14, *), status == .limited {
      return "limited"
    }
    switch status {
    case .authorized:
      return "granted"
    case .denied:
      return "permanentlyDenied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    default:
      return "denied"
    }
  }

  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

extension BrowseFilesFlutterPlugin: UIDocumentPickerDelegate {
  public func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let paths = urls.compactMap { PhotoLibraryReader.copyToCache(url: $0) }
      DispatchQueue.main.async { self.finishDocuments(with: paths) }
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    // Backing out of the picker is a normal outcome, not a failure.
    finishDocuments(with: [])
  }
}
