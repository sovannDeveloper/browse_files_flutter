import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/media_album.dart';
import '../models/media_item.dart';
import '../models/media_permission.dart';
import 'attachment_grid_delegate.dart';
import 'media_tile.dart';
import 'thumbnail_cache.dart';

/// The Gallery tab: permission handling, then a paged grid of the library.
///
/// This widget talks to the platform only through [BrowseFilesFlutterPlatform],
/// so the whole tab can be driven by a fake in tests.
class MediaGrid extends StatefulWidget {
  /// Creates the gallery tab.
  const MediaGrid({
    required this.options,
    required this.cache,
    required this.selection,
    required this.onToggle,
    this.scrollController,
    this.canSelectMore = true,
    super.key,
  });

  /// The sheet's options: types, paging, columns, camera tile.
  final BrowseFilesOptions options;

  /// Where tiles get their thumbnails.
  final ThumbnailCache cache;

  /// The current selection, in pick order — the grid is told, it does not own
  /// it.
  final List<MediaItem> selection;

  /// Called when a tile is tapped.
  final ValueChanged<MediaItem> onToggle;

  /// The scroll controller to drive the grid with.
  ///
  /// The sheet passes its own so that dragging the grid resizes the sheet; a
  /// page passes one per tab so two scrollables never fight over the primary.
  final ScrollController? scrollController;

  /// Whether another tile may be added to the selection.
  ///
  /// The grid does not know what else is selected elsewhere — the page counts
  /// documents against the same cap — so it is told rather than counting.
  final bool canSelectMore;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> with WidgetsBindingObserver {
  final List<MediaItem> _items = <MediaItem>[];

  /// The ids in [_items], so a page cannot add an asset the grid already
  /// shows. A library that changes while it is being paged shifts every offset
  /// after the change, and a grid keyed by asset id throws on the duplicate.
  final Set<String> _ids = <String>{};

  /// The albums the top bar switches between, and the open one. Empty until
  /// the platform answers, and left empty when it cannot list albums at all —
  /// the grid works the same, it just gets no group selector.
  List<MediaAlbum> _albums = const <MediaAlbum>[];
  MediaAlbum? _album;

  MediaPermissionStatus? _permission;
  int _total = 0;
  bool _loadingPage = false;
  bool _busy = true;
  String? _error;

  BrowseFilesFlutterPlatform get _platform =>
      BrowseFilesFlutterPlatform.instance;

  bool get _hasMore => _items.length < _total;

  /// The album to page, or `null` for the whole library — the synthetic "all
  /// media" entry is the platform's way of saying "no filter".
  String? get _albumId => (_album?.isAll ?? true) ? null : _album!.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A camera app is another activity, and the library can change while it is
    // in front. Nothing tells the grid, so it re-reads the first page on the
    // way back.
    if (state == AppLifecycleState.resumed &&
        (_permission?.canBrowse ?? false)) {
      _refresh();
    }
  }

  /// Re-reads the first page, leaving the grid alone when nothing has changed
  /// — a reload would otherwise throw away everything paged in so far.
  Future<void> _refresh() async {
    final page = await _guard(
      () => _platform.fetchMedia(
        albumId: _albumId,
        types: widget.options.types,
        offset: 0,
        limit: widget.options.pageSize,
      ),
    );
    if (!mounted || page == null) return;
    final unchanged =
        page.total == _total &&
        (page.items.isEmpty ||
            (_items.isNotEmpty && page.items.first.id == _items.first.id));
    if (unchanged) return;
    setState(() {
      _replace(page.items);
      _total = page.total;
    });
  }

  /// Adopts [items] as the whole grid.
  void _replace(List<MediaItem> items) {
    _items.clear();
    _ids.clear();
    _append(items);
  }

  /// Adds the items of a page the grid does not already hold, and asks for
  /// their thumbnails straight away.
  void _append(List<MediaItem> items) {
    final added = <String>[];
    for (final item in items) {
      if (_ids.add(item.id)) {
        _items.add(item);
        added.add(item.id);
      }
    }
    final size = widget.options.thumbnailSize;
    widget.cache.prefetch(added, width: size, height: size);
  }

  /// Checks access first: asking the library for pages we may not read only
  /// produces a confusing error where a prompt belongs.
  Future<void> _bootstrap() async {
    final status = await _guard(
      () => _platform.permissionStatus(types: widget.options.types),
    );
    if (!mounted || status == null) return;
    setState(() {
      _permission = status;
      _busy = false;
    });
    if (status.canBrowse) {
      await _loadMore(reset: true);
      unawaited(_loadAlbums());
    }
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final status = await _guard(
      () => _platform.requestPermission(types: widget.options.types),
    );
    if (!mounted) return;
    setState(() {
      _permission = status ?? _permission;
      _busy = false;
    });
    if (status != null && status.canBrowse) {
      await _loadMore(reset: true);
      unawaited(_loadAlbums());
    }
  }

  Future<void> _selectMore() async {
    final status = await _guard(_platform.presentLimitedPicker);
    if (!mounted || status == null) return;
    setState(() => _permission = status);
    // The shared subset has changed, so everything paged in so far is stale.
    widget.cache.clear();
    await _loadMore(reset: true);
    unawaited(_loadAlbums());
  }

  /// Reads the album list for the top bar, after the first page is on screen.
  ///
  /// Never awaited ahead of the grid: listing albums means walking every row
  /// in the library — MediaStore has no GROUP BY — so a library of any size
  /// would hold the first page, and with it every thumbnail on it, behind a
  /// full scan. That is what made a first open paint an empty grid while a
  /// second one, reading the same warm caches, filled instantly.
  ///
  /// A platform that will not list albums is not an error the user can act on
  /// — the grid still shows the whole library — so this fails quietly into no
  /// selector rather than into the error panel [_guard] would raise.
  Future<void> _loadAlbums() async {
    final List<MediaAlbum> albums;
    try {
      albums = await _platform.fetchAlbums(types: widget.options.types);
    } on BrowseFilesException {
      return;
    }
    if (!mounted) return;
    // Covers are asked for at the tiles' size, so an album whose cover is
    // already on the grid costs nothing, and the menu is warm before it opens
    // rather than starting a decode per row when it does.
    final size = widget.options.thumbnailSize;
    widget.cache.prefetch(
      <String>[
        for (final album in albums)
          if (album.coverId != null) album.coverId!,
      ],
      width: size,
      height: size,
    );
    setState(() {
      _albums = albums;
      // Keep the open album across a re-read; it is gone from the list when
      // its last asset was deleted, and then the library is where to land.
      _album = albums.contains(_album)
          ? albums.firstWhere((album) => album == _album)
          : (albums.isEmpty ? null : albums.first);
    });
  }

  /// Switches the grid to another album, from the first page down.
  Future<void> _selectAlbum(MediaAlbum album) async {
    if (album == _album) return;
    setState(() {
      _album = album;
      _items.clear();
      _ids.clear();
      _total = 0;
      _busy = true;
      _error = null;
    });
    await _loadMore(reset: true);
  }

  Future<void> _openSettings() => _guard(_platform.openSettings);

  /// Fetches the next page, or the first one again when [reset] is set.
  ///
  /// Deliberately does not call `setState` before awaiting: the grid asks for
  /// the next page from inside `itemBuilder`, and touching state during a
  /// build is an error.
  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingPage) return;
    _loadingPage = true;
    final offset = reset ? 0 : _items.length;
    final page = await _guard(
      () => _platform.fetchMedia(
        albumId: _albumId,
        types: widget.options.types,
        offset: offset,
        limit: widget.options.pageSize,
      ),
    );
    _loadingPage = false;
    if (!mounted || page == null) return;
    setState(() {
      if (reset) {
        _replace(page.items);
      } else {
        _append(page.items);
      }

      _total = page.items.length < widget.options.pageSize
          ? _items.length
          : (page.total > _items.length ? page.total : _items.length);
      _busy = false;
    });
  }

  /// Runs a platform call, turning its failure into the panel's error text.
  Future<T?> _guard<T>(Future<T> Function() call) async {
    try {
      final value = await call();
      if (mounted && _error != null) setState(() => _error = null);
      return value;
    } on BrowseFilesException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _busy = false;
        });
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = _permission;
    if (_busy && _items.isEmpty && permission == null) {
      return const _Centered(child: CircularProgressIndicator());
    }
    if (permission != null && !permission.canBrowse) {
      return _PermissionPanel(
        status: permission,
        busy: _busy,
        error: _error,
        onRequest: _request,
        onOpenSettings: _openSettings,
      );
    }
    return Column(
      children: [
        // Above the banner: which album is open outranks how much of the
        // library was shared, and an empty album must still be switchable.
        if (_albums.length > 1)
          _AlbumBar(
            albums: _albums,
            album: _album,
            cache: widget.cache,
            thumbnailSize: widget.options.thumbnailSize,
            onSelected: _selectAlbum,
          ),
        if (permission == MediaPermissionStatus.limited)
          _LimitedBanner(onSelectMore: _selectMore),
        Expanded(child: _content()),
      ],
    );
  }

  /// The grid, or what stands in for it while it is empty.
  Widget _content() {
    final error = _error;
    if (error != null && _items.isEmpty) {
      return _Centered(
        child: _Message(
          icon: Icons.error_outline,
          title: 'The library could not be read',
          detail: error,
          actionLabel: 'Try again',
          onAction: () => _loadMore(reset: true),
        ),
      );
    }
    if (_items.isEmpty) {
      return _busy
          ? const _Centered(child: CircularProgressIndicator())
          : const _Centered(
              child: _Message(
                icon: Icons.photo_outlined,
                title: 'Nothing here yet',
                detail:
                    'Photos and videos on this device show up in this grid.',
              ),
            );
    }
    return _grid();
  }

  Widget _grid() {
    final options = widget.options;
    final hasCamera = options.onCameraTap != null;
    final leading = hasCamera ? 1 : 0;
    return GridView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: 0,
        right: 0,
        top: 0,
        bottom: MediaQuery.of(context).padding.bottom + 100,
      ),
      // Build a couple of rows past the viewport so their thumbnails are asked
      // for before they are scrolled into view, rather than after.
      cacheExtent: 600,
      // The camera cell is two rows tall, which no stock delegate can express.
      gridDelegate: hasCamera
          ? AttachmentGridDelegate(crossAxisCount: options.crossAxisCount)
          : SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: options.crossAxisCount,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
      // One cell past the library while there is more of it: a spinner in the
      // grid is what says the next page is on its way.
      itemCount: _items.length + leading + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasCamera && index == 0) {
          return _CameraTile(onTap: options.onCameraTap!);
        }
        if (index - leading >= _items.length) {
          _loadMore();
          return const _LoadingCell();
        }
        final item = _items[index - leading];
        // Page in well before the last row scrolls into view.
        if (_hasMore &&
            index >= _items.length + leading - options.pageSize ~/ 3) {
          _loadMore();
        }
        final order = widget.selection.indexOf(item);
        return MediaTile(
          key: ValueKey<String>(item.id),
          item: item,
          cache: widget.cache,
          thumbnailSize: options.thumbnailSize,
          selectionOrder: order < 0 ? null : order + 1,
          enabled: widget.canSelectMore,
          onTap: () => widget.onToggle(item),
        );
      },
    );
  }
}

/// The top bar of the gallery: which group of media the grid is showing, and
/// the menu that switches it.
class _AlbumBar extends StatelessWidget {
  const _AlbumBar({
    required this.albums,
    required this.album,
    required this.cache,
    required this.thumbnailSize,
    required this.onSelected,
  });

  final List<MediaAlbum> albums;
  final MediaAlbum? album;
  final ThumbnailCache cache;

  /// The size covers are requested at — the tiles' size, so the two share
  /// cache entries instead of each decoding the same asset.
  final int thumbnailSize;

  final ValueChanged<MediaAlbum> onSelected;

  /// How large a cover is drawn in the menu.
  static const double _coverExtent = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = album ?? albums.first;
    return Material(
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Flexible(
            child: PopupMenuButton<MediaAlbum>(
              initialValue: current,
              onSelected: onSelected,
              tooltip: 'Choose an album',
              position: PopupMenuPosition.under,
              constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
              itemBuilder: (context) => <PopupMenuEntry<MediaAlbum>>[
                for (final entry in albums)
                  PopupMenuItem<MediaAlbum>(
                    value: entry,
                    height: 60,
                    child: Row(
                      spacing: 14,
                      children: [
                        _AlbumCover(
                          album: entry,
                          cache: cache,
                          size: thumbnailSize,
                          extent: _coverExtent,
                        ),
                        Flexible(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${entry.count}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Flexible(
                      child: Text(
                        current.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              current.count == 1 ? '1 item' : '${current.count} items',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// One album's cover in the menu: the same thumbnail pipeline the tiles use,
/// keyed by the album's cover asset.
///
/// An album the platform gave no cover for — and one whose cover it cannot
/// make a thumbnail of — draws the placeholder rather than nothing, so every
/// row keeps the same shape.
class _AlbumCover extends StatefulWidget {
  const _AlbumCover({
    required this.album,
    required this.cache,
    required this.size,
    required this.extent,
  });

  final MediaAlbum album;
  final ThumbnailCache cache;
  final int size;
  final double extent;

  @override
  State<_AlbumCover> createState() => _AlbumCoverState();
}

class _AlbumCoverState extends State<_AlbumCover> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    final coverId = widget.album.coverId;
    if (coverId == null) return;
    _bytes = widget.cache.peek(
      coverId,
      width: widget.size,
      height: widget.size,
    );
    // The grid prefetches every cover when the album list lands, so the bytes
    // this row wants are usually already on their way; the listener paints
    // them whoever asked for them.
    widget.cache.changes.addListener(_onCacheChange);
    if (_bytes == null) _load(coverId);
  }

  @override
  void dispose() {
    widget.cache.changes.removeListener(_onCacheChange);
    super.dispose();
  }

  void _onCacheChange() {
    final coverId = widget.album.coverId;
    if (_bytes != null || coverId == null) return;
    final bytes = widget.cache.peek(
      coverId,
      width: widget.size,
      height: widget.size,
    );
    if (bytes == null || bytes.isEmpty || !mounted) return;
    setState(() => _bytes = bytes);
  }

  Future<void> _load(String coverId) async {
    try {
      final bytes = await widget.cache.load(
        coverId,
        width: widget.size,
        height: widget.size,
      );
      if (!mounted || bytes == null || bytes.isEmpty) return;
      setState(() => _bytes = bytes);
    } on Object {
      // A cover that will not load is a placeholder, not a broken menu.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.square(
        dimension: widget.extent,
        child: bytes == null
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.photo_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// The last cell of the grid while the next page is being read.
class _LoadingCell extends StatelessWidget {
  const _LoadingCell();

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// The strip shown above the grid when only part of the library is shared.
class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.onSelectMore});

  final VoidCallback onSelectMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'You shared some of your library',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(onPressed: onSelectMore, child: const Text('Select more')),
        ],
      ),
    );
  }
}

/// The first cell of the grid, standing in for Telegram's live camera preview.
///
/// A real preview means a camera stream inside the sheet, which is out of this
/// package's scope; this opens whatever camera the host app passed in.
class _CameraTile extends StatelessWidget {
  const _CameraTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                Icons.photo_camera_outlined,
                size: 30,
                color: scheme.onSurfaceVariant,
              ),
            ),
            // Where every other tile carries a selection ring, this one
            // carries the camera chip.
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.photo_camera,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the grid shows instead of tiles when the library is off limits.
class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.status,
    required this.busy,
    required this.error,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final MediaPermissionStatus status;
  final bool busy;
  final String? error;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final needsSettings = status.needsSettings;
    return _Centered(
      child: _Message(
        icon: needsSettings ? Icons.lock_outline : Icons.photo_library_outlined,
        title: needsSettings
            ? 'Photo access is turned off'
            : 'Let this app see your photos',
        detail:
            error ??
            (needsSettings
                ? 'Turn photo access on in Settings and come back.'
                : 'Your photos and videos stay on the device; nothing is '
                      'uploaded by this sheet.'),
        actionLabel: busy
            ? null
            : (needsSettings ? 'Open settings' : 'Allow access'),
        onAction: needsSettings ? onOpenSettings : onRequest,
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = actionLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
        Text(title, style: theme.textTheme.titleMedium),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        if (label != null)
          FilledButton(onPressed: onAction, child: Text(label)),
      ],
    );
  }
}
