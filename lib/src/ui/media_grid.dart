import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
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

  MediaPermissionStatus? _permission;
  int _total = 0;
  bool _loadingPage = false;
  bool _busy = true;
  String? _error;

  BrowseFilesFlutterPlatform get _platform =>
      BrowseFilesFlutterPlatform.instance;

  bool get _hasMore => _items.length < _total;

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
    if (status.canBrowse) await _loadMore(reset: true);
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
    if (status != null && status.canBrowse) await _loadMore(reset: true);
  }

  Future<void> _selectMore() async {
    final status = await _guard(_platform.presentLimitedPicker);
    if (!mounted || status == null) return;
    setState(() => _permission = status);
    // The shared subset has changed, so everything paged in so far is stale.
    widget.cache.clear();
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
      // A short page is the end of the library, whatever the total says; and a
      // total below what is already loaded would leave the grid asking for a
      // page that never comes.
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
    if (_items.isEmpty && !_busy) {
      return const _Centered(
        child: _Message(
          icon: Icons.photo_outlined,
          title: 'Nothing here yet',
          detail: 'Photos and videos on this device show up in this grid.',
        ),
      );
    }
    return Column(
      children: [
        if (permission == MediaPermissionStatus.limited)
          _LimitedBanner(onSelectMore: _selectMore),
        Expanded(child: _grid()),
      ],
    );
  }

  Widget _grid() {
    final options = widget.options;
    final hasCamera = options.onCameraTap != null;
    final leading = hasCamera ? 1 : 0;
    return GridView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
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
