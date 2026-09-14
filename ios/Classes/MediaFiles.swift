import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Everything that touches files in the plugin's cache, kept apart from the channel plumbing.
///
/// Nothing here goes near the photo library. What the pickers and the camera hand over is
/// copied into `Caches/browse_files`, and from then on an item's id *is* its path: `describe`
/// measures it, `loadThumbnail` decodes it small, and `resolveFile` has nothing left to do.
///
/// The maps handed back are exactly the shape `OCMediaItem.fromMap` reads on the Dart side.
/// Functions block and are called off the main thread.
enum MediaFiles {
  /// Where thumbnails are decoded, off the main thread.
  static let queue = DispatchQueue(
    label: "com.kedtec.browse_files_flutter.files",
    qos: .userInitiated,
    attributes: .concurrent)

  /// The plugin's corner of the cache, created on demand.
  static func cacheDirectory() -> URL? {
    guard
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }
    let directory = caches.appendingPathComponent("browse_files", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: nil)
    return directory
  }

  /// A path in the cache for a file called [name] that no earlier file is using.
  ///
  /// Never overwrites: a path handed to the host app stays valid, so a second file with the
  /// same name lands beside the first as `name (1).ext`.
  static func cacheTarget(named name: String) -> URL? {
    guard let directory = cacheDirectory() else { return nil }
    let safe = name.replacingOccurrences(of: "/", with: "_")
    let base = (safe as NSString).deletingPathExtension
    let ext = (safe as NSString).pathExtension
    var candidate = directory.appendingPathComponent(safe.isEmpty ? "file" : safe)
    var counter = 1
    while FileManager.default.fileExists(atPath: candidate.path) {
      let stem = "\(base.isEmpty ? "file" : base) (\(counter))"
      candidate = directory.appendingPathComponent(
        ext.isEmpty ? stem : "\(stem).\(ext)")
      counter += 1
    }
    return candidate
  }

  /// Copies a picked file — a picker's temporary URL, a security-scoped document URL —
  /// into the cache and hands back the path.
  static func copyToCache(url: URL) -> String? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let target = cacheTarget(named: url.lastPathComponent) else { return nil }
    do {
      try FileManager.default.copyItem(at: url, to: target)
      return target.path
    } catch {
      return nil
    }
  }

  /// Writes bytes into the cache under [name] and hands back the path.
  static func writeToCache(data: Data, named name: String) -> String? {
    guard let target = cacheTarget(named: name) else { return nil }
    do {
      try data.write(to: target, options: .atomic)
      return target.path
    } catch {
      return nil
    }
  }

  /// What a `UIImagePickerController` — the camera, or the iOS 13 library — handed over,
  /// stored in the cache and described; nil when nothing usable came back.
  static func store(info: [UIImagePickerController.InfoKey: Any]) -> [String: Any]? {
    let mediaType = info[.mediaType] as? String ?? "public.image"
    if mediaType == "public.movie" {
      guard let url = info[.mediaURL] as? URL, let path = copyToCache(url: url) else {
        return nil
      }
      return describe(path: path, isVideo: true)
    }
    // A library pick carries the original file; a camera shot only the decoded image.
    if let url = info[.imageURL] as? URL, let path = copyToCache(url: url) {
      return describe(path: path, isVideo: false)
    }
    guard let image = info[.originalImage] as? UIImage,
      let data = image.jpegData(compressionQuality: 0.92),
      let path = writeToCache(data: data, named: "capture_\(timestamp()).jpg")
    else { return nil }
    return describe(path: path, isVideo: false)
  }

  /// The metadata `OCMediaItem.fromMap` reads, measured off the file.
  ///
  /// A photo is measured with its EXIF orientation applied and a clip with its track
  /// transform, so portrait captures report portrait sizes.
  static func describe(path: String, isVideo: Bool) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    var width = 0
    var height = 0
    var durationMs: Int?
    if isVideo {
      let asset = AVURLAsset(url: url)
      durationMs = Int(CMTimeGetSeconds(asset.duration) * 1000)
      if let track = asset.tracks(withMediaType: .video).first {
        let size = track.naturalSize.applying(track.preferredTransform)
        width = Int(abs(size.width))
        height = Int(abs(size.height))
      }
    } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    {
      width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
      height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
      // EXIF orientations 5–8 are the rotated ones.
      if let orientation = properties[kCGImagePropertyOrientation] as? UInt32, orientation >= 5 {
        swap(&width, &height)
      }
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    let modified = (attributes?[.modificationDate] as? Date) ?? Date()
    var item: [String: Any] = [
      "id": path,
      "type": isVideo ? "video" : "image",
      "width": width,
      "height": height,
      "createdAtMs": Int(modified.timeIntervalSince1970 * 1000),
      "name": url.lastPathComponent,
      "mimeType": mimeType(of: url) ?? (isVideo ? "video/quicktime" : "image/jpeg"),
    ]
    if let durationMs { item["durationMs"] = durationMs }
    if let size = attributes?[.size] as? Int { item["sizeBytes"] = size }
    return item
  }

  /// A JPEG thumbnail of the file at [path], or nil when it cannot be decoded.
  ///
  /// Photos go through ImageIO's thumbnailer, which never inflates the full bitmap; clips
  /// give up a frame from half a second in, so a fade-from-black opening is not the tile.
  static func loadThumbnail(path: String, width: Int, height: Int, quality: Int) -> Data? {
    let url = URL(fileURLWithPath: path)
    let longest = max(width, height)
    let image: UIImage?
    if mimeType(of: url)?.hasPrefix("video/") == true {
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: longest, height: longest)
      let time = CMTime(seconds: 0.5, preferredTimescale: 600)
      image = (try? generator.copyCGImage(at: time, actualTime: nil)).map { UIImage(cgImage: $0) }
    } else {
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: longest,
      ]
      image = CGImageSourceCreateWithURL(url as CFURL, nil)
        .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
        .map { UIImage(cgImage: $0) }
    }
    return image?.jpegData(compressionQuality: CGFloat(quality) / 100)
  }

  /// The MIME type for a file's extension, or nil when the system has no idea.
  static func mimeType(of url: URL) -> String? {
    let ext = url.pathExtension.lowercased()
    if #available(iOS 14, *), let type = UTType(filenameExtension: ext),
      let mime = type.preferredMIMEType
    {
      return mime
    }
    switch ext {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "heic": return "image/heic"
    case "gif": return "image/gif"
    case "mov": return "video/quicktime"
    case "mp4", "m4v": return "video/mp4"
    default: return nil
    }
  }

  private static func timestamp() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
}
