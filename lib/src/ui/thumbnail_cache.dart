import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../browse_files_flutter_platform_interface.dart';

/// A bounded, least-recently-used cache of JPEG thumbnails.
///
/// The grid asks for a thumbnail per visible tile and scrolling revisits the
/// same assets constantly, so the bytes are kept — but only [capacity] of
/// them. Holding every thumbnail a long scroll touches is how a picker runs
/// out of memory.
class ThumbnailCache {
  /// Creates a cache holding at most [capacity] thumbnails.
  ///
  /// [platform] exists for tests; production uses whatever
  /// [BrowseFilesFlutterPlatform.instance] is at call time.
  ThumbnailCache({this.capacity = 256, BrowseFilesFlutterPlatform? platform})
    : assert(capacity > 0, 'a cache of nothing is not a cache'),
      _platform = platform;

  /// The cache the sheet uses unless it is handed another one.
  static final ThumbnailCache shared = ThumbnailCache();

  /// How many thumbnails are kept before the least recently used is dropped.
  final int capacity;

  final BrowseFilesFlutterPlatform? _platform;

  /// Insertion order is the LRU order: touched entries move to the end.
  final LinkedHashMap<String, Uint8List?> _entries =
      LinkedHashMap<String, Uint8List?>();

  /// Requests already in flight, so a rebuild does not ask twice for the same
  /// tile.
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  BrowseFilesFlutterPlatform get _api =>
      _platform ?? BrowseFilesFlutterPlatform.instance;

  /// How many thumbnails are currently held.
  @visibleForTesting
  int get length => _entries.length;

  /// The thumbnail for [id] at the given size, from memory when it is there.
  ///
  /// A `null` result means the platform could not produce one; that answer is
  /// cached too, so a broken asset is not re-asked on every rebuild.
  Future<Uint8List?> load(
    String id, {
    required int width,
    required int height,
  }) {
    final key = _keyOf(id, width, height);
    if (_entries.containsKey(key)) {
      final bytes = _entries.remove(key);
      _entries[key] = bytes;
      return SynchronousFuture<Uint8List?>(bytes);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _api
        .loadThumbnail(id, width: width, height: height)
        .then((bytes) {
          _store(key, bytes);
          return bytes;
        })
        .whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = request;
    return request;
  }

  /// Starts loading [ids] without waiting for the answers.
  ///
  /// The grid calls this the moment a page arrives, so the platform is already
  /// decoding while the tiles are still being laid out — on a first open,
  /// where the OS has no thumbnail cached yet and has to generate one per
  /// asset, that head start is most of the wait.
  void prefetch(
    Iterable<String> ids, {
    required int width,
    required int height,
  }) {
    for (final id in ids) {
      // A failure here is the tile's to report, not the prefetch's.
      load(id, width: width, height: height).catchError((_) => null);
    }
  }

  /// The bytes already in memory for [id] at this size, if any.
  ///
  /// Lets a tile paint on its first frame instead of flashing a placeholder.
  Uint8List? peek(String id, {required int width, required int height}) =>
      _entries[_keyOf(id, width, height)];

  /// Drops everything, for a library that has changed under us.
  void clear() {
    _entries.clear();
    _inFlight.clear();
  }

  void _store(String key, Uint8List? bytes) {
    _entries.remove(key);
    _entries[key] = bytes;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  String _keyOf(String id, int width, int height) => '$id@${width}x$height';
}
