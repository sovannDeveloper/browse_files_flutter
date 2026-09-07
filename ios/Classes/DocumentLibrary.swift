import Foundation
import UniformTypeIdentifiers

/// The files iOS lets an app list: its own.
///
/// There is no device-wide file store to enumerate here — the sandbox is the point of iOS
/// storage — so this walks the app's Documents directory and the plugin's own cache, which is
/// where anything picked through `UIDocumentPickerViewController` already lands. Everything
/// else stays behind that picker, and the page says so rather than pretending the device has
/// no files.
enum DocumentLibrary {
  static func fetchDocuments(mimeTypes: [String], offset: Int, limit: Int) -> [String: Any] {
    let manager = FileManager.default
    var roots: [URL] = []
    if let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first {
      roots.append(documents)
    }
    if let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
      roots.append(caches.appendingPathComponent("browse_files", isDirectory: true))
    }

    let keys: [URLResourceKey] = [
      .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .nameKey,
    ]
    var files: [(url: URL, modified: Date, size: Int, mime: String?)] = []
    for root in roots {
      guard
        let entries = try? manager.contentsOfDirectory(
          at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
      else { continue }
      for url in entries {
        let values = try? url.resourceValues(forKeys: Set(keys))
        guard values?.isRegularFile == true else { continue }
        let mime = mimeType(of: url)
        guard matches(mime, mimeTypes) else { continue }
        files.append(
          (
            url: url,
            modified: values?.contentModificationDate ?? .distantPast,
            size: values?.fileSize ?? 0,
            mime: mime
          ))
      }
    }
    files.sort { $0.modified > $1.modified }

    let total = files.count
    let end = min(offset + limit, total)
    var items: [[String: Any]] = []
    if offset < end {
      for file in files[offset..<end] {
        var item: [String: Any] = [
          "id": file.url.path,
          "name": file.url.lastPathComponent,
          "sizeBytes": file.size,
          "modifiedAtMs": Int(file.modified.timeIntervalSince1970 * 1000),
          // These are already this app's files, so they arrive resolved.
          "path": file.url.path,
        ]
        if let mime = file.mime { item["mimeType"] = mime }
        items.append(item)
      }
    }
    return [
      "items": items,
      "offset": offset,
      "total": total,
      // iOS never lists the device's files, only this app's.
      "enumerable": false,
    ]
  }

  /// Whether a file's MIME type satisfies the filter.
  ///
  /// An empty filter takes everything; `image/*` matches a whole family, and `*/*` is the same
  /// as no filter at all.
  static func matches(_ mime: String?, _ patterns: [String]) -> Bool {
    if patterns.isEmpty || patterns.contains("*/*") { return true }
    guard let mime else { return false }
    for pattern in patterns {
      if pattern.hasSuffix("/*") {
        if mime.hasPrefix(String(pattern.dropLast(1))) { return true }
      } else if pattern == mime {
        return true
      }
    }
    return false
  }

  private static func mimeType(of url: URL) -> String? {
    if #available(iOS 14, *) {
      return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }
    return nil
  }
}
