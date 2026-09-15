import AVFoundation
import Flutter
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// iOS side of `browse_files_flutter`.
///
/// Nothing here asks for photo library access. Media come through `PHPickerViewController`
/// (iOS 14+; `UIImagePickerController` on iOS 13), which runs out of process and hands over
/// copies of what the user chose, documents through `UIDocumentPickerViewController`, and
/// captures through the system camera. Everything lands in the plugin's cache, so an item's
/// id is a path and `resolveFile` has nothing left to do.
///
/// The host app's Info.plist needs `NSCameraUsageDescription` for `captureMedia`, and
/// `NSMicrophoneUsageDescription` too for video — iOS kills the app otherwise, which is why
/// this plugin checks for them before opening the camera.
///
/// Errors come back as `FlutterError(code:message:details:)` with a code from
/// `OCBrowseFilesErrorCode`: `permissionDenied`, `userCanceled`, `notFound`, `ioError`,
/// `unsupported`, `unknown`.
public class BrowseFilesFlutterPlugin: NSObject, FlutterPlugin {
  /// The reply waiting on the media picker.
  private var pendingMedia: FlutterResult?

  /// The reply waiting on the camera.
  private var pendingCapture: FlutterResult?

  /// The reply waiting on the system document picker, and the picker keeping itself alive.
  private var pendingDocuments: FlutterResult?
  private var documentPicker: UIDocumentPickerViewController?

  /// `UIImagePickerController` serves both the camera and the iOS 13 library, so its delegate
  /// has to know which reply it is answering.
  private enum ImagePickerPurpose { case camera, library }
  private var imagePickerPurpose = ImagePickerPurpose.library

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.kedtec.browse_files_flutter/methods",
      binaryMessenger: registrar.messenger())
    let instance = BrowseFilesFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickMedia":
      pickMedia(call, result: result)
    case "captureMedia":
      captureMedia(call, result: result)
    case "requestCameraPermission":
      requestCameraPermission(call, result: result)
    case "loadThumbnail":
      loadThumbnail(call, result: result)
    case "resolveFile":
      resolveFile(call, result: result)
    case "pickDocuments":
      pickDocuments(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - pickMedia

  /// Presents the system media picker; what it hands back is copied into the cache.
  private func pickMedia(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let types = Set(arguments["types"] as? [String] ?? ["image", "video"])
    let allowMultiple = arguments["allowMultiple"] as? Bool ?? true
    guard pendingMedia == nil else {
      result(FlutterError(code: "unknown", message: "A media picker is already open.", details: nil))
      return
    }
    guard let host = Self.topViewController() else {
      result(
        FlutterError(
          code: "unsupported", message: "There is no view controller to present the picker from.",
          details: nil))
      return
    }
    pendingMedia = result
    if #available(iOS 14, *) {
      var configuration = PHPickerConfiguration()
      configuration.selectionLimit = allowMultiple ? 0 : 1
      configuration.filter = Self.pickerFilter(for: types)
      // The file as it is, not a transcode: `.automatic` can spend a minute re-encoding a
      // long clip before the delegate ever hears about it.
      configuration.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      host.present(picker, animated: true)
    } else {
      // iOS 13 has no PHPicker; the old picker still runs out of process and needs no
      // permission, but takes one item at a time.
      let picker = UIImagePickerController()
      picker.sourceType = .photoLibrary
      picker.mediaTypes = Self.imagePickerTypes(for: types)
      picker.delegate = self
      imagePickerPurpose = .library
      host.present(picker, animated: true)
    }
  }

  @available(iOS 14, *)
  private static func pickerFilter(for types: Set<String>) -> PHPickerFilter {
    let wantsImages = types.contains("image")
    let wantsVideos = types.contains("video")
    if wantsImages && !wantsVideos { return .images }
    if wantsVideos && !wantsImages { return .videos }
    return .any(of: [.images, .videos])
  }

  private static func imagePickerTypes(for types: Set<String>) -> [String] {
    var mediaTypes: [String] = []
    if types.contains("image") { mediaTypes.append("public.image") }
    if types.contains("video") { mediaTypes.append("public.movie") }
    return mediaTypes.isEmpty ? ["public.image", "public.movie"] : mediaTypes
  }

  /// Answers the waiting `pickMedia` call exactly once.
  fileprivate func finishMedia(with items: [[String: Any]]) {
    let reply = pendingMedia
    pendingMedia = nil
    reply?(items)
  }

  // MARK: - captureMedia

  /// Opens the system camera for a photo or a video.
  ///
  /// The missing-purpose-string case is caught here because the alternative is iOS killing
  /// the app with no error anywhere Dart can see; a denied camera comes back as
  /// `permissionDenied` rather than the black preview the picker would otherwise show.
  private func captureMedia(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let isVideo = (arguments["type"] as? String) == "video"
    guard pendingCapture == nil else {
      result(FlutterError(code: "unknown", message: "The camera is already open.", details: nil))
      return
    }
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      // The simulator lands here: there is no camera to open.
      result(FlutterError(code: "unsupported", message: "This device has no camera.", details: nil))
      return
    }
    if let missing = Self.missingUsageDescription(isVideo: isVideo) {
      result(missing)
      return
    }
    pendingCapture = result
    Self.authorizeCamera(isVideo: isVideo) { [weak self] status in
      guard let self else { return }
      guard status == Self.granted else {
        self.finishCapture(
          error: FlutterError(
            code: "permissionDenied",
            message: "Camera access was refused; it can be turned on in Settings.",
            details: status))
        return
      }
      guard let host = Self.topViewController() else {
        self.finishCapture(
          error: FlutterError(
            code: "unsupported",
            message: "There is no view controller to present the camera from.",
            details: nil))
        return
      }
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.mediaTypes = [isVideo ? "public.movie" : "public.image"]
      picker.cameraCaptureMode = isVideo ? .video : .photo
      picker.videoQuality = .typeHigh
      picker.delegate = self
      self.imagePickerPurpose = .camera
      host.present(picker, animated: true)
    }
  }

  // MARK: - requestCameraPermission

  /// Where the app stands with the camera, prompting first if iOS has not asked yet.
  ///
  /// The same checks `captureMedia` runs before opening the camera, without the camera: the
  /// sheet calls this first so a refused camera is a message rather than a black preview.
  /// Video also asks for the microphone, but a refused microphone does not change the answer
  /// — `UIImagePickerController` records without sound in that case.
  private func requestCameraPermission(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let isVideo = (arguments["type"] as? String) == "video"
    if let missing = Self.missingUsageDescription(isVideo: isVideo) {
      result(missing)
      return
    }
    Self.authorizeCamera(isVideo: isVideo) { status in result(status) }
  }

  // OCCameraPermission on the Dart side.
  private static let granted = "granted"
  private static let denied = "denied"
  private static let permanentlyDenied = "permanentlyDenied"

  /// The `unsupported` error for a purpose string the host forgot, or nil when both the camera
  /// and (for video) the microphone have one. Caught here because the alternative is iOS
  /// killing the app with no error anywhere Dart can see.
  private static func missingUsageDescription(isVideo: Bool) -> FlutterError? {
    let info = Bundle.main.infoDictionary ?? [:]
    guard info["NSCameraUsageDescription"] != nil else {
      return FlutterError(
        code: "unsupported",
        message: "Add NSCameraUsageDescription to the app's Info.plist to open the camera.",
        details: nil)
    }
    if isVideo, info["NSMicrophoneUsageDescription"] == nil {
      return FlutterError(
        code: "unsupported",
        message: "Add NSMicrophoneUsageDescription to the app's Info.plist to record video.",
        details: nil)
    }
    return nil
  }

  /// Resolves the camera's authorization to an `OCCameraPermission` name, asking iOS to
  /// prompt when it has not yet, and — for video — asking for the microphone after the camera
  /// so both prompts land before the picker opens. Calls back on the main thread.
  private static func authorizeCamera(isVideo: Bool, completion: @escaping (String) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      if isVideo {
        authorizeMicrophone { completion(granted) }
      } else {
        completion(granted)
      }
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { ok in
        DispatchQueue.main.async {
          guard ok else {
            // iOS shows the prompt once; a refusal here is only undone in Settings.
            completion(permanentlyDenied)
            return
          }
          if isVideo {
            authorizeMicrophone { completion(granted) }
          } else {
            completion(granted)
          }
        }
      }
    case .denied, .restricted:
      completion(permanentlyDenied)
    @unknown default:
      completion(denied)
    }
  }

  /// Prompts for the microphone if iOS has not asked yet; the answer is not reported because
  /// it never blocks a capture.
  private static func authorizeMicrophone(_ completion: @escaping () -> Void) {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
      completion()
      return
    }
    AVCaptureDevice.requestAccess(for: .audio) { _ in
      DispatchQueue.main.async(execute: completion)
    }
  }

  /// Answers the waiting `captureMedia` call exactly once.
  fileprivate func finishCapture(with item: [String: Any]? = nil, error: FlutterError? = nil) {
    let reply = pendingCapture
    pendingCapture = nil
    reply?(error ?? item)
  }

  // MARK: - loadThumbnail / resolveFile

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
    guard FileManager.default.fileExists(atPath: id) else {
      result(nil)
      return
    }
    MediaFiles.queue.async {
      let data = MediaFiles.loadThumbnail(path: id, width: width, height: height, quality: quality)
      DispatchQueue.main.async {
        result(data.map { FlutterStandardTypedData(bytes: $0) })
      }
    }
  }

  /// Every id this plugin hands out is already a file in the cache, so this only checks it is
  /// still there — a nil crosses the channel as `notFound`.
  private func resolveFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let id = arguments["id"] as? String else {
      result(FlutterError(code: "notFound", message: "resolveFile needs an asset id.", details: nil))
      return
    }
    result(FileManager.default.fileExists(atPath: id) ? id : nil)
  }

  // MARK: - pickDocuments

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

  /// Answers the waiting `pickDocuments` call exactly once.
  fileprivate func finishDocuments(with paths: [String]) {
    let reply = pendingDocuments
    pendingDocuments = nil
    documentPicker = nil
    reply?(paths)
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

// MARK: - PHPickerViewControllerDelegate

@available(iOS 14, *)
extension BrowseFilesFlutterPlugin: PHPickerViewControllerDelegate {
  /// Copies every pick into the cache, in the order the user chose them, and answers once.
  ///
  /// `loadFileRepresentation` hands over a temporary URL that is gone the moment the callback
  /// returns, so the copy happens inside it; the callbacks run concurrently and the results
  /// are slotted back by index.
  public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard !results.isEmpty else {
      // Backing out of the picker is a normal outcome, not a failure.
      finishMedia(with: [])
      return
    }
    var items = [[String: Any]?](repeating: nil, count: results.count)
    let lock = NSLock()
    let group = DispatchGroup()
    for (index, result) in results.enumerated() {
      let provider = result.itemProvider
      let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
      let identifier = isVideo ? UTType.movie.identifier : UTType.image.identifier
      guard provider.hasItemConformingToTypeIdentifier(identifier) else { continue }
      group.enter()
      provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
        defer { group.leave() }
        guard let url, let path = MediaFiles.copyToCache(url: url) else { return }
        let item = MediaFiles.describe(path: path, isVideo: isVideo)
        lock.lock()
        items[index] = item
        lock.unlock()
      }
    }
    group.notify(queue: .main) { [weak self] in
      self?.finishMedia(with: items.compactMap { $0 })
    }
  }
}

// MARK: - UIImagePickerControllerDelegate

extension BrowseFilesFlutterPlugin: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  public func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    let purpose = imagePickerPurpose
    MediaFiles.queue.async {
      let item = MediaFiles.store(info: info)
      DispatchQueue.main.async { [weak self] in
        switch purpose {
        case .camera:
          self?.finishCapture(with: item)
        case .library:
          self?.finishMedia(with: item.map { [$0] } ?? [])
        }
      }
    }
  }

  public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    // Backing out is a normal outcome: nil from the camera, nothing from the library.
    switch imagePickerPurpose {
    case .camera: finishCapture()
    case .library: finishMedia(with: [])
    }
  }
}

// MARK: - UIDocumentPickerDelegate

extension BrowseFilesFlutterPlugin: UIDocumentPickerDelegate {
  public func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    MediaFiles.queue.async {
      let paths = urls.compactMap { MediaFiles.copyToCache(url: $0) }
      DispatchQueue.main.async { self.finishDocuments(with: paths) }
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    // Backing out of the picker is a normal outcome, not a failure.
    finishDocuments(with: [])
  }
}
