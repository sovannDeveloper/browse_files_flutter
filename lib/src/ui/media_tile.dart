import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import 'thumbnail_cache.dart';

/// One cell of the media grid: a thumbnail, a selection control, and — for a
/// video — a play glyph with its duration.
class OCMediaTile extends StatefulWidget {
  /// Creates a tile for [item].
  const OCMediaTile({
    required this.item,
    required this.cache,
    required this.thumbnailSize,
    required this.selectionOrder,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  /// The asset this tile shows.
  final OCMediaItem item;

  /// Where the thumbnail comes from.
  final OCThumbnailCache cache;

  /// The pixel size to request, square.
  final int thumbnailSize;

  /// This item's 1-based place in the selection, or `null` when unselected.
  final int? selectionOrder;

  /// Whether tapping does anything — false once the selection cap is reached.
  final bool enabled;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  /// Whether this tile is part of the selection.
  bool get isSelected => selectionOrder != null;

  @override
  State<OCMediaTile> createState() => _OCMediaTileState();
}

class _OCMediaTileState extends State<OCMediaTile> {
  Uint8List? _bytes;

  /// Set once the platform has answered without bytes: an asset it cannot make
  /// a thumbnail of. Kept apart from a request still in flight so a blank tile
  /// means "loading" and nothing else.
  bool _missing = false;

  /// Set when the request itself failed.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.cache.peek(
      widget.item.id,
      width: widget.thumbnailSize,
      height: widget.thumbnailSize,
    );
    // A prefetch started elsewhere (the grid, a sibling tile) can land in the
    // cache without our `_load` ever firing; the listener picks that up.
    widget.cache.changes.addListener(_onCacheChange);
    if (_bytes == null) _load();
  }

  @override
  void dispose() {
    widget.cache.changes.removeListener(_onCacheChange);
    super.dispose();
  }

  void _onCacheChange() {
    if (_bytes != null || _failed || _missing) return;
    final bytes = widget.cache.peek(
      widget.item.id,
      width: widget.thumbnailSize,
      height: widget.thumbnailSize,
    );
    if (bytes == null) return;
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  void didUpdateWidget(OCMediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.thumbnailSize != widget.thumbnailSize) {
      _bytes = null;
      _failed = false;
      _missing = false;
      _load();
    }
  }

  Future<void> _load() async {
    final item = widget.item;
    try {
      final bytes = await widget.cache.load(
        item.id,
        width: widget.thumbnailSize,
        height: widget.thumbnailSize,
      );
      if (!mounted || widget.item.id != item.id) return;
      setState(() {
        // Empty bytes are not an image: a platform that failed to encode one
        // is a tile with nothing to show, not a tile still waiting.
        _bytes = (bytes == null || bytes.isEmpty) ? null : bytes;
        _missing = _bytes == null;
      });
    } on Object {
      // A thumbnail that cannot be decoded is a blank tile, not a broken grid.
      if (!mounted || widget.item.id != item.id) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.isSelected;
    return GestureDetector(
      onTap: widget.enabled || selected ? widget.onTap : null,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedScale(
              scale: selected ? 0.88 : 1,
              duration: const Duration(milliseconds: 120),
              child: _thumbnail(theme),
            ),
            if (!widget.enabled && !selected)
              ColoredBox(
                color: theme.colorScheme.surface.withValues(alpha: 0.5),
              ),
            if (widget.item.isVideo)
              Positioned(
                left: 6,
                bottom: 6,
                child: _VideoBadge(duration: widget.item.duration),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: _SelectionDot(order: widget.selectionOrder),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(ThemeData theme) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _placeholder(theme),
      );
    }
    return _placeholder(theme);
  }

  /// The cell before its thumbnail arrives: a small spinner while the
  /// platform is still working, a marked icon once it has answered with
  /// nothing.
  Widget _placeholder(ThemeData theme) {
    final icon = _failed
        ? Icons.broken_image_outlined
        : (_missing ? Icons.image_not_supported_outlined : null);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: icon == null
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Center(
              child: Icon(
                icon,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
    );
  }
}

/// The circular control at a tile's top-right corner.
///
/// Telegram fills it with the selection order rather than a tick, so the user
/// can see what order the attachments will be sent in.
class _SelectionDot extends StatelessWidget {
  const _SelectionDot({this.order});

  final int? order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = order != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Unselected is an empty ring over the photo, not a filled dot.
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, spreadRadius: 0.5),
        ],
      ),
      child: selected
          ? Text(
              '$order',
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

/// The play glyph and running time on a video tile.
class _VideoBadge extends StatelessWidget {
  const _VideoBadge({this.duration});

  final Duration? duration;

  /// A drop shadow rather than a pill: the glyph sits straight on the frame,
  /// and the shadow is what keeps it readable over a bright one.
  static const List<Shadow> _shadows = <Shadow>[
    Shadow(color: Colors.black54, blurRadius: 4),
  ];

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 3,
    children: [
      const Icon(
        Icons.play_arrow,
        size: 14,
        color: Colors.white,
        shadows: _shadows,
      ),
      Text(
        formatMediaDuration(duration),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          shadows: _shadows,
        ),
      ),
    ],
  );
}

/// Formats a video length the way the badge shows it: `2:05`, or `1:32:48`
/// once it passes an hour.
String formatMediaDuration(Duration? duration) {
  final total = duration ?? Duration.zero;
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  final minutes = total.inMinutes.remainder(60);
  if (total.inHours <= 0) return '$minutes:$seconds';
  return '${total.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds';
}
