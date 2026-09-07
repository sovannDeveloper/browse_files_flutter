import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/attachment_tab.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/browse_files_result.dart';
import '../models/media_item.dart';
import 'attachment_tab_bar.dart';
import 'browse_files_page.dart';
import 'media_grid.dart';
import 'thumbnail_cache.dart';

/// The attachment sheet: one call, one result.
///
/// ```dart
/// final result = await BrowseFiles.show(context);
/// if (result != null) {
///   for (final item in result.media) {
///     final path = await BrowseFilesFlutter.instance.resolveFile(item.id);
///   }
/// }
/// ```
class BrowseFiles {
  const BrowseFiles._();

  /// Slides the attachment sheet over the current screen.
  ///
  /// Resolves to what the user confirmed, or `null` if they dismissed the
  /// sheet by tapping the scrim, dragging it down or pressing back.
  static Future<BrowseFilesResult?> show(
    BuildContext context, {
    BrowseFilesOptions options = const BrowseFilesOptions(),
    ThumbnailCache? cache,
  }) {
    assert(Navigator.maybeOf(context) != null, _noNavigator);
    return showModalBottomSheet<BrowseFilesResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BrowseFilesSheet(options: options, cache: cache),
    );
  }

  /// Pushes the full-screen browser: photos and videos in one tab, every other
  /// file in the next.
  ///
  /// The same result as [show], for when the user is looking for something
  /// rather than grabbing the last photo they took.
  static Future<BrowseFilesResult?> showPage(
    BuildContext context, {
    BrowseFilesOptions options = const BrowseFilesOptions(),
    ThumbnailCache? cache,
    String title = 'Attach',
  }) {
    assert(Navigator.maybeOf(context) != null, _noNavigator);
    return Navigator.of(context).push<BrowseFilesResult>(
      MaterialPageRoute<BrowseFilesResult>(
        builder: (context) =>
            BrowseFilesPage(options: options, cache: cache, title: title),
      ),
    );
  }

  /// The mistake worth naming: a `State` that builds `MaterialApp` sits above
  /// the Navigator it creates, so its own context cannot open anything.
  static const String _noNavigator =
      'BrowseFiles needs a context below a Navigator. A State that builds '
      'MaterialApp itself is above it — call this from a widget inside '
      'MaterialApp, or wrap the call site in a Builder.';
}

/// The sheet's body, exposed so it can be embedded or widget-tested without
/// going through [BrowseFiles.show].
class BrowseFilesSheet extends StatefulWidget {
  /// Creates the sheet.
  const BrowseFilesSheet({
    this.options = const BrowseFilesOptions(),
    this.cache,
    super.key,
  });

  /// How the sheet should behave.
  final BrowseFilesOptions options;

  /// The thumbnail cache to draw from; defaults to [ThumbnailCache.shared].
  final ThumbnailCache? cache;

  @override
  State<BrowseFilesSheet> createState() => _BrowseFilesSheetState();
}

class _BrowseFilesSheetState extends State<BrowseFilesSheet> {
  /// The selection, in the order it was picked — that order is what the
  /// numbered tiles and the send order mean.
  final List<MediaItem> _selected = <MediaItem>[];

  late String _tabId = _initialTabId;

  ThemeData? _theme;
  Object? _themeKey;
  bool _pickingDocuments = false;
  String? _documentError;

  BrowseFilesOptions get _options => widget.options;

  ThumbnailCache get _cache => widget.cache ?? ThumbnailCache.shared;

  /// The tab to open on, ignoring an `initialTabId` that names no tab.
  String get _initialTabId =>
      _options.tabs.any((tab) => tab.id == _options.initialTabId)
      ? _options.initialTabId
      : (_options.tabs.isEmpty
            ? AttachmentTab.galleryId
            : _options.tabs.first.id);

  /// The open tab, falling back to the gallery for an empty tab row.
  AttachmentTab get _activeTab => _options.tabs.firstWhere(
    (tab) => tab.id == _tabId,
    orElse: () => AttachmentTab.gallery,
  );

  void _toggle(MediaItem item) {
    setState(() {
      if (_selected.remove(item)) return;
      if (_selected.length >= _options.maxSelection) return;
      _selected.add(item);
    });
  }

  void _confirm() {
    Navigator.of(
      context,
    ).pop(BrowseFilesResult(media: List<MediaItem>.unmodifiable(_selected)));
  }

  /// Hands the File tab straight to the system picker: browsing storage
  /// ourselves would mean re-implementing the file manager, and SAF already
  /// is one.
  Future<void> _pickDocuments() async {
    setState(() {
      _pickingDocuments = true;
      _documentError = null;
    });
    try {
      final paths = await BrowseFilesFlutterPlatform.instance.pickDocuments(
        mimeTypes: _options.documentMimeTypes,
        allowMultiple: _options.allowMultipleDocuments,
      );
      if (!mounted) return;
      setState(() => _pickingDocuments = false);
      if (paths.isEmpty) return;
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(BrowseFilesResult(documents: List<String>.unmodifiable(paths)));
    } on BrowseFilesException catch (error) {
      if (!mounted) return;
      setState(() {
        _pickingDocuments = false;
        // Backing out of the picker is a normal outcome, not a failure.
        _documentError = error.isCancellation ? null : error.message;
      });
    }
  }

  /// The sheet's own theme, so a host app can hand it Telegram's dark chrome
  /// without dyeing the app around it.
  ///
  /// Memoised because a drag rebuilds this widget every frame.
  ThemeData _sheetTheme(BuildContext context) {
    final base = Theme.of(context);
    final background = _options.backgroundColor;
    final accent = _options.accentColor;
    final key = Object.hash(base, background, accent);
    final cached = _theme;
    if (cached != null && _themeKey == key) return cached;

    final ThemeData built;
    if (background == null) {
      built = accent == null
          ? base
          : base.copyWith(
              colorScheme: base.colorScheme.copyWith(primary: accent),
            );
    } else {
      built = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent ?? base.colorScheme.primary,
          brightness: ThemeData.estimateBrightnessForColor(background),
        ).copyWith(surface: background, primary: accent),
      );
    }
    _theme = built;
    _themeKey = key;
    return built;
  }

  /// One step away from the sheet's surface, so the tab bar reads as a bar.
  Color _barColor(ThemeData theme) {
    final surface = theme.colorScheme.surface;
    final tint =
        ThemeData.estimateBrightnessForColor(surface) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Color.alphaBlend(tint.withValues(alpha: 0.07), surface);
  }

  @override
  Widget build(BuildContext context) {
    final theme = _sheetTheme(context);
    final peek = _options.peekSize;
    return Theme(
      data: theme,
      child: NotificationListener<DraggableScrollableNotification>(
        // Dragged down to the bottom stop: the user is closing the sheet.
        onNotification: (notification) {
          if (notification.extent <= notification.minExtent + 0.001) {
            Navigator.of(context).maybePop();
          }
          return false;
        },
        child: DraggableScrollableSheet(
          expand: false,
          snap: true,
          initialChildSize: peek,
          minChildSize: peek / 2,
          maxChildSize: 1,
          snapSizes: <double>[peek],
          builder: (context, scrollController) => DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                const _DragHandle(),
                Expanded(child: _body(scrollController, theme)),
                if (_selected.isNotEmpty) _confirmBar(theme),
                SafeArea(
                  top: false,
                  child: AttachmentTabBar(
                    tabs: _options.tabs,
                    activeId: _tabId,
                    barColor: _barColor(theme),
                    onSelected: (tab) => setState(() => _tabId = tab.id),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ScrollController scrollController, ThemeData theme) {
    final tab = _activeTab;
    if (tab.id == AttachmentTab.galleryId && tab.isBuiltIn) {
      return MediaGrid(
        key: const ValueKey<String>('browse-files-gallery'),
        options: _options,
        cache: _cache,
        selection: _selected,
        onToggle: _toggle,
        scrollController: scrollController,
        canSelectMore: _selected.length < _options.maxSelection,
      );
    }
    final builder = tab.builder;
    return _Fill(
      key: ValueKey<String>('browse-files-${tab.id}'),
      scrollController: scrollController,
      child: builder != null ? builder(context) : _fileTab(theme),
    );
  }

  Widget _fileTab(ThemeData theme) {
    final error = _documentError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Text('Files', style: theme.textTheme.titleMedium),
            Text(
              error ??
                  'Pick documents with the system file picker. They are copied '
                      'into this app before you get a path back.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: error == null ? null : theme.colorScheme.error,
              ),
            ),
            FilledButton(
              onPressed: _pickingDocuments ? null : _pickDocuments,
              child: Text(_pickingDocuments ? 'Opening…' : 'Browse files'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmBar(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${_selected.length} of ${_options.maxSelection} selected',
            style: theme.textTheme.bodySmall,
          ),
        ),
        FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.send, size: 16),
          label: Text('${_options.confirmLabel} (${_selected.length})'),
        ),
      ],
    ),
  );
}

/// Makes a non-scrolling tab body drag the sheet like the grid does.
class _Fill extends StatelessWidget {
  const _Fill({required this.scrollController, required this.child, super.key});

  final ScrollController scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      controller: scrollController,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: child,
      ),
    ),
  );
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
