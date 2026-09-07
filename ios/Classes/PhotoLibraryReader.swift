import Photos
import UIKit

/// Everything that reads the photo library, kept apart from the channel plumbing.
///
/// The maps handed back are exactly the shapes `MediaItem.fromMap`, `MediaAlbum.fromMap` and
/// `MediaPage.fromMap` read on the Dart side.
enum PhotoLibraryReader {
  /// The synthetic album that means "the whole library".
  static let allAlbumId = "all"

  /// Kept around so repeated tile requests reuse the same decoding pipeline.
  private static let imageManager = PHCachingImageManager()

  /// Where thumbnails are turned into JPEG, off the main thread.
  private static let encodeQueue = DispatchQueue(
    label: "com.kedtec.browse_files_flutter.thumbnails",
    qos: .userInitiated,
    attributes: .concurrent)

  /// One page of an album, newest first.
  ///
  /// `PHFetchResult` is lazy, so counting it and reading a window out of it does not pull the
  /// whole library into memory.
  static func fetchMedia(
    types: Set<String>, albumId: String?, offset: Int, limit: Int
  ) -> [String: Any] {
    let assets = fetchAssets(types: types, albumId: albumId)
    let total = assets.count
    var items: [[String: Any]] = []
    let end = min(offset + limit, total)
    if offset < end {
      assets.enumerateObjects(at: IndexSet(integersIn: offset..<end), options: []) { asset, _, _ in
        items.append(describe(asset))
      }
    }
    return ["items": items, "offset": offset, "total": total]
  }

  /// The albums holding at least one matching asset, "all media" first.
  static func fetchAlbums(types: Set<String>) -> [[String: Any]] {
    let options = fetchOptions(types: types)
    let everything = PHAsset.fetchAssets(with: options)
    var albums: [[String: Any]] = [
      album(
        id: allAlbumId, name: "All media", count: everything.count,
        coverId: everything.firstObject?.localIdentifier, isAll: true)
    ]
    let collections = [
      PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil),
      PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil),
    ]
    for result in collections {
      result.enumerateObjects { collection, _, _ in
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        guard assets.count > 0 else { return }
        albums.append(
          album(
            id: collection.localIdentifier,
            name: collection.localizedTitle ?? "",
            count: assets.count,
            coverId: assets.firstObject?.localIdentifier,
            isAll: false))
      }
    }
    return albums
  }

  /// A JPEG thumbnail for one asset, or nil when the library cannot produce one.
  static func loadThumbnail(
    id: String, width: Int, height: Int, quality: Int, completion: @escaping (Data?) -> Void
  ) {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    else {
      completion(nil)
      return
    }
    let options = PHImageRequestOptions()
    // A tile must never wait on iCloud: Photos keeps a small local rendition of an asset whose
    // full size lives in the cloud, and that is exactly what a 3-column grid wants. resolveFile
    // is where the download belongs, once the user has actually picked something.
    options.isNetworkAccessAllowed = false
    options.resizeMode = .fast
    options.isSynchronous = false
    // Both .fastFormat and .highQualityFormat call back exactly once, which is what a channel
    // reply needs (`.opportunistic` delivers twice). .fastFormat serves the cached thumbnail
    // instead of decoding and downscaling the original, so a screenful arrives in one pass.
    options.deliveryMode = .fastFormat
    imageManager.requestImage(
      for: asset,
      targetSize: CGSize(width: width, height: height),
      contentMode: .aspectFill,
      options: options
    ) { image, _ in
      guard let image else {
        completion(nil)
        return
      }
      // requestImage calls back on the main thread, and JPEG-encoding every tile there is a
      // stutter in the grid it is scrolling.
      encodeQueue.async {
        completion(image.jpegData(compressionQuality: CGFloat(quality) / 100))
      }
    }
  }

  /// Copies an asset into the app cache and hands back the path.
  ///
  /// An asset that only exists in iCloud has to be downloaded first, which is why this can take
  /// a while and why it is called for the final selection rather than for every tile.
  static func resolveFile(id: String, completion: @escaping (String?) -> Void) {
    // A document id on iOS is already a path into this app's own storage.
    if FileManager.default.fileExists(atPath: id) {
      completion(id)
      return
    }
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
      let resource = PHAssetResource.assetResources(for: asset).first,
      let target = cacheTarget(named: resource.originalFilename)
    else {
      completion(nil)
      return
    }
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options) {
      error in
      completion(error == nil ? target.path : nil)
    }
  }

  /// Copies a picked document out of its temporary URL into the app cache.
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

  private static func fetchAssets(types: Set<String>, albumId: String?) -> PHFetchResult<PHAsset> {
    let options = fetchOptions(types: types)
    guard let albumId, albumId != allAlbumId else {
      return PHAsset.fetchAssets(with: options)
    }
    guard
      let collection = PHAssetCollection.fetchAssetCollections(
        withLocalIdentifiers: [albumId], options: nil
      ).firstObject
    else {
      return PHAsset.fetchAssets(in: PHAssetCollection(), options: options)
    }
    return PHAsset.fetchAssets(in: collection, options: options)
  }

  private static func fetchOptions(types: Set<String>) -> PHFetchOptions {
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    var mediaTypes: [Int] = []
    if types.contains("image") { mediaTypes.append(PHAssetMediaType.image.rawValue) }
    if types.contains("video") { mediaTypes.append(PHAssetMediaType.video.rawValue) }
    options.predicate = NSPredicate(format: "mediaType IN %@", mediaTypes)
    return options
  }

  private static func describe(_ asset: PHAsset) -> [String: Any] {
    let isVideo = asset.mediaType == .video
    let created = asset.creationDate ?? asset.modificationDate ?? Date()
    var item: [String: Any] = [
      "id": asset.localIdentifier,
      "type": isVideo ? "video" : "image",
      "width": asset.pixelWidth,
      "height": asset.pixelHeight,
      "createdAtMs": Int(created.timeIntervalSince1970 * 1000),
    ]
    if isVideo {
      item["durationMs"] = Int(asset.duration * 1000)
    }
    // Names and byte sizes mean a PHAssetResource lookup per asset, which is too slow for a
    // page of tiles; resolveFile reports them when the asset actually becomes a file.
    return item
  }

  private static func album(
    id: String, name: String, count: Int, coverId: String?, isAll: Bool
  ) -> [String: Any] {
    var album: [String: Any] = ["id": id, "name": name, "count": count, "isAll": isAll]
    if let coverId { album["coverId"] = coverId }
    return album
  }

  /// A fresh path inside the plugin's cache directory, with any existing file cleared out.
  private static func cacheTarget(named name: String) -> URL? {
    guard
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }
    let directory = caches.appendingPathComponent("browse_files", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: nil)
    let safe = name.replacingOccurrences(of: "/", with: "_")
    let target = directory.appendingPathComponent(safe.isEmpty ? "file" : safe)
    try? FileManager.default.removeItem(at: target)
    return target
  }
}
