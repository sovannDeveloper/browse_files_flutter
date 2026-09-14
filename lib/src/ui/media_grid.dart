import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/browse_files_action.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/browse_files_strings.dart';
import '../models/media_item.dart';
import '../models/media_type.dart';
import 'attachment_grid_delegate.dart';
import 'browse_files_actions.dart';
import 'media_tile.dart';
import 'thumbnail_cache.dart';

/// The Gallery tab: an entry point into the system media picker, then a
/// confirmation grid of what the user picked.
///
/// On Android 13+ the picker is the system Photo Picker, below that
/// `ACTION_GET_CONTENT`. Neither needs a media permission, so there is no
/// permission panel — the only state the tab holds is the picked items.
///
/// This widget talks to the platform only through
/// [OCBrowseFilesFlutterPlatform], so the whole tab can be driven by a fake
/// in tests.
class OCMediaGrid extends StatefulWidget {
  /// Creates the gallery tab.
  const OCMediaGrid({
    required this.options,
    required this.cache,
    required this.selection,
    required this.onToggle,
    this.scrollController,
    this.canSelectMore = true,
    this.bottomInset = 0,
    super.key,
  });

  /// The sheet's options: types, cap, columns, camera tile.
  final OCBrowseFilesOptions options;

  /// Where tiles get their thumbnails.
  final OCThumbnailCache cache;

  /// The current selection, in pick order — the grid is told, it does not own
  /// it.
  final List<OCMediaItem> selection;

  /// Called when a tile is tapped.
  final ValueChanged<OCMediaItem> onToggle;

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

  /// Space to leave clear at the bottom, in logical pixels.
  ///
  /// The sheet floats its tab pill and confirm bar over the body; the grid
  /// scrolls under them, but the "Select more" row has to sit above.
  final double bottomInset;

  @override
  State<OCMediaGrid> createState() => _OCMediaGridState();
}

class _OCMediaGridState extends State<OCMediaGrid> {
  /// Picked items in pick order — a peer of the selection list, kept for the
  /// grid's own render and prefetching, mirroring what the caller already holds.
  ///
  /// Separating them from the selection avoids mutating the caller's list when
  /// the picker returns — the caller toggles items into the selection only
  /// after the picker succeeds.
  final List<OCMediaItem> _items = <OCMediaItem>[];

  /// The ids in [_items], so a second pick from the picker never lists an
  /// item the grid already shows.
  final Set<String> _ids = <String>{};

  bool _picking = false;
  bool _resolved = false;
  String? _error;

  /// Which panel heading [_error] sits under: the picker's or the camera's.
  bool _cameraError = false;

  OCBrowseFilesFlutterPlatform get _platform =>
      OCBrowseFilesFlutterPlatform.instance;

  OCBrowseFilesOptions get _options => widget.options;

  int get _count => _items.length;

  @override
  void initState() {
    super.initState();
    _adoptSelection(widget.selection);
  }

  @override
  void didUpdateWidget(OCMediaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host app (the sheet) is the source of truth for the selection; re-mirror
    // it when it changes — for example when a sibling tab adds an item, or
    // when the page rebuilds after a remove.
    _adoptSelection(widget.selection);
  }

  /// Treats [items] as the whole set of picked items.
  ///
  /// Adds every item that is not already there and prefetches their
  /// thumbnails at the tile size. The grid does not own the selection — when
  /// the caller updates it, this is what picks up the change.
  void _adoptSelection(Iterable<OCMediaItem> items) {
    final added = <String>[];
    for (final item in items) {
      if (_ids.add(item.id)) {
        _items.add(item);
        added.add(item.id);
      }
    }
    _prefetch(added);
  }

  void _prefetch(Iterable<String> ids) {
    if (ids.isEmpty) return;
    final size = _options.thumbnailSize;
    widget.cache.prefetch(ids, width: size, height: size);
  }

  /// Opens the system media picker and adopts whatever the user chose.
  ///
  /// A picker that the user dismissed is a no-op — there is nothing to add,
  /// no error to show, and the existing selection stays put.
  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    final List<OCMediaItem> picked;
    try {
      picked = await _platform.pickMedia(
        types: _options.types.isEmpty ? kAllMediaTypes : _options.types,
        allowMultiple: _options.allowMultipleMedia && _options.maxSelection > 1,
      );
    } catch (error) {
      _fail(error, camera: false);
      return;
    }
    if (!mounted) return;
    _adopt(picked);
  }

  /// Opens the camera and adopts the shot.
  ///
  /// The host app's own camera wins when it supplied one; otherwise this is
  /// the system camera through `captureMedia`. With both kinds allowed the
  /// user is asked which first — Android has no single intent that does both.
  Future<void> _capture() async {
    final custom = _options.onCameraTap;
    if (custom != null) {
      custom();
      return;
    }
    if (_picking) return;
    final types = _options.cameraTypes;
    if (types.isEmpty) return;
    final OCMediaType? type;
    if (types.length == 1) {
      type = types.single;
    } else {
      final action = await showModalBottomSheet<OCBrowseFilesAction>(
        context: context,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => OCBrowseFilesActionsSheet(
          options: _options,
          showTitle: false,
          actions: const <OCBrowseFilesAction>[
            OCBrowseFilesAction.takePhoto,
            OCBrowseFilesAction.recordVideo,
          ],
        ),
      );
      type = switch (action) {
        OCBrowseFilesAction.takePhoto => OCMediaType.image,
        OCBrowseFilesAction.recordVideo => OCMediaType.video,
        _ => null,
      };
    }
    if (type == null || !mounted) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    final OCMediaItem? item;
    try {
      item = await _platform.captureMedia(type: type);
    } catch (error) {
      _fail(error, camera: true);
      return;
    }
    if (!mounted) return;
    _adopt(<OCMediaItem>[?item]);
  }

  void _fail(Object error, {required bool camera}) {
    if (!mounted) return;
    setState(() {
      _picking = false;
      _cameraError = camera;
      _error = error is OCBrowseFilesException
          ? (error.isCancellation ? null : error.message)
          : error.toString();
    });
  }

  /// Puts what the picker or camera returned into the grid and, in pick
  /// order, into the selection.
  void _adopt(List<OCMediaItem> picked) {
    final added = <OCMediaItem>[];
    setState(() {
      _picking = false;
      _resolved = true;
      // Adopt the picks before the caller toggles them in, so the grid paints
      // the new tiles the moment the caller rebuilds — and dedup against
      // whatever the user picked before.
      for (final item in picked) {
        if (!_ids.contains(item.id)) {
          _ids.add(item.id);
          _items.add(item);
          added.add(item);
        }
      }
      _prefetch([for (final item in added) item.id]);
    });
    // Hand the new items to the caller in pick order — same order Telegram
    // attaches. Stops at [maxSelection] so a user who flips past the cap in
    // the system picker does not silently get more than asked for.
    final capacity = _options.maxSelection - widget.selection.length;
    if (capacity <= 0) return;
    for (final item in added.take(capacity)) {
      widget.onToggle(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _options.text;
    // Two render modes: empty (the CTA) and confirming (the picked grid).
    if (!_resolved || _items.isEmpty) {
      return _EmptyState(
        strings: strings,
        busy: _picking,
        error: _error,
        errorTitle: _cameraError
            ? strings.cameraErrorTitle
            : strings.galleryErrorTitle,
        cameraTap: _options.hasCamera ? _capture : null,
        onPick: _picking ? null : _pick,
      );
    }
    return Column(
      children: [
        Expanded(child: _confirming(strings)),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8 + widget.bottomInset),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _count.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _picking || !widget.canSelectMore ? null : _pick,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(strings.gallerySelectMoreLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The 3-column grid of items the user picked, with the optional camera
  /// cell in front.
  Widget _confirming(OCBrowseFilesStrings strings) {
    final options = _options;
    final hasCamera = options.hasCamera;
    final leading = hasCamera ? 1 : 0;
    return GridView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        top: 4,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      // Build a couple of rows past the viewport so their thumbnails are
      // requested before they scroll in.
      cacheExtent: 600,
      gridDelegate: hasCamera
          ? OCAttachmentGridDelegate(crossAxisCount: options.crossAxisCount)
          : SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: options.crossAxisCount,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
      itemCount: _items.length + leading,
      itemBuilder: (context, index) {
        if (hasCamera && index == 0) {
          return _CameraTile(onTap: _picking ? null : _capture);
        }
        final item = _items[index - leading];
        final order = widget.selection.indexOf(item);
        return OCMediaTile(
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

/// What the gallery shows when nothing has been picked yet — the CTA that
/// opens the system picker, plus the optional camera tile.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.strings,
    required this.busy,
    required this.error,
    required this.errorTitle,
    required this.cameraTap,
    required this.onPick,
  });

  final OCBrowseFilesStrings strings;
  final bool busy;
  final String? error;
  final String errorTitle;
  final VoidCallback? cameraTap;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCamera = cameraTap != null;
    final hasError = error != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasError) ...[
                  Icon(
                    Icons.error_outline,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Text(errorTitle, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.galleryEmptyTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.galleryEmptyDetail,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : onPick,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : hasError
                      ? const Icon(Icons.refresh)
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    hasError
                        ? strings.retryLabel
                        : strings.galleryEmptyActionLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasCamera)
          Positioned(
            top: 8,
            right: 8,
            child: _CameraFloatingButton(onTap: cameraTap!),
          ),
      ],
    );
  }
}

/// The square camera shortcut Telegram puts on the sheet, in case the host
/// app has its own camera handler.
class _CameraFloatingButton extends StatelessWidget {
  const _CameraFloatingButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            Icons.photo_camera_outlined,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The first cell of the picking grid when the camera lives there — used by
/// the confirming flow, not the empty one. Same shape [_CameraFloatingButton]
/// raises, but as a cell so it lines up with the tiles.
class _CameraTile extends StatelessWidget {
  const _CameraTile({required this.onTap});
  final VoidCallback? onTap;

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
