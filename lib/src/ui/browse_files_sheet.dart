import 'package:division/division.dart';
import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/attachment_tab.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/browse_files_result.dart';
import '../models/document_item.dart';
import '../models/media_item.dart';
import 'attachment_tab_bar.dart';
import 'browse_files_page.dart';
import 'document_list.dart';
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
class OCBrowseFiles {
  const OCBrowseFiles._();

  /// Slides the attachment sheet over the current screen.
  ///
  /// Resolves to what the user confirmed, or `null` if they dismissed the
  /// sheet by tapping the scrim, dragging it down or pressing back.
  static Future<OCBrowseFilesResult?> show(
    BuildContext context, {
    OCBrowseFilesOptions options = const OCBrowseFilesOptions(),
    OCThumbnailCache? cache,
  }) {
    assert(Navigator.maybeOf(context) != null, _noNavigator);
    return showModalBottomSheet<OCBrowseFilesResult>(
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
  static Future<OCBrowseFilesResult?> showPage(
    BuildContext context, {
    OCBrowseFilesOptions options = const OCBrowseFilesOptions(),
    OCThumbnailCache? cache,
    String title = 'Attach',
  }) {
    assert(Navigator.maybeOf(context) != null, _noNavigator);
    return Navigator.of(context).push<OCBrowseFilesResult>(
      MaterialPageRoute<OCBrowseFilesResult>(
        builder: (context) =>
            OCBrowseFilesPage(options: options, cache: cache, title: title),
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
/// going through [OCBrowseFiles.show].
class BrowseFilesSheet extends StatefulWidget {
  /// Creates the sheet.
  const BrowseFilesSheet({
    this.options = const OCBrowseFilesOptions(),
    this.cache,
    super.key,
  });

  /// How the sheet should behave.
  final OCBrowseFilesOptions options;

  /// The thumbnail cache to draw from; defaults to [OCThumbnailCache.shared].
  final OCThumbnailCache? cache;

  @override
  State<BrowseFilesSheet> createState() => _BrowseFilesSheetState();
}

class _BrowseFilesSheetState extends State<BrowseFilesSheet> {
  /// The selection on each axis — the cap counts across both, like the page.
  final List<OCMediaItem> _media = <OCMediaItem>[];
  final List<OCDocumentItem> _documents = <OCDocumentItem>[];

  /// The two lists need their own scroll controllers: two scrollables sharing
  /// the primary one would fight over it mid-swipe.
  final ScrollController _mediaScroll = ScrollController();
  final ScrollController _documentScroll = ScrollController();

  late String _tabId = _initialTabId;

  ThemeData? _theme;
  Object? _themeKey;

  bool _resolving = false;
  String? _error;

  OCBrowseFilesOptions get _options => widget.options;

  OCThumbnailCache get _cache => widget.cache ?? OCThumbnailCache.shared;

  int get _count => _media.length + _documents.length;

  bool get _canSelectMore => _count < _options.maxSelection;

  /// The tab to open on, ignoring an `initialTabId` that names no tab.
  String get _initialTabId =>
      _options.tabs.any((tab) => tab.id == _options.initialTabId)
      ? _options.initialTabId
      : (_options.tabs.isEmpty
            ? OCAttachmentTab.galleryId
            : _options.tabs.first.id);

  /// The open tab, falling back to the gallery for an empty tab row.
  OCAttachmentTab get _activeTab => _options.tabs.firstWhere(
    (tab) => tab.id == _tabId,
    orElse: () => OCAttachmentTab.gallery,
  );

  @override
  void dispose() {
    _mediaScroll.dispose();
    _documentScroll.dispose();
    super.dispose();
  }

  void _toggleMedia(OCMediaItem item) {
    setState(() {
      if (_media.remove(item)) return;
      if (!_canSelectMore) return;
      _media.add(item);
    });
  }

  void _toggleDocument(OCDocumentItem item) {
    setState(() {
      if (_documents.remove(item)) return;
      if (!_canSelectMore) return;
      _documents.add(item);
    });
  }

  /// Documents were picked *as* files — copy the ones that are still platform
  /// handles out to the cache so the host app gets readable paths back.
  Future<void> _confirm() async {
    setState(() {
      _resolving = true;
      _error = null;
    });
    final paths = <String>[];
    try {
      for (final document in _documents) {
        paths.add(
          document.path ??
              await OCBrowseFilesFlutterPlatform.instance.resolveFile(
                document.id,
              ),
        );
      }
    } on OCBrowseFilesException catch (error) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = error.message;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      OCBrowseFilesResult(
        media: List<OCMediaItem>.unmodifiable(_media),
        documents: List<String>.unmodifiable(paths),
      ),
    );
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
            child: Stack(
              children: [
                Column(
                  children: [
                    const _DragHandle(),
                    Expanded(child: _body(scrollController, theme)),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        Center(
                          child: Column(
                            children: [
                              if (_count <= 0)
                                OCAttachmentTabBar(
                                  tabs: _options.tabs,
                                  activeId: _tabId,
                                  barColor: _barColor(theme),
                                  onSelected: (tab) =>
                                      setState(() => _tabId = tab.id),
                                ),
                              if (_count > 0) _confirmBar(theme),
                            ],
                          ),
                        ),
                      ],
                    ),
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
    if (tab.id == OCAttachmentTab.galleryId && tab.isBuiltIn) {
      return OCMediaGrid(
        key: const ValueKey<String>('browse-files-gallery'),
        options: _options,
        cache: _cache,
        selection: _media,
        onToggle: _toggleMedia,
        scrollController: scrollController,
        canSelectMore: _canSelectMore,
      );
    }
    if (tab.id == OCAttachmentTab.fileId && tab.isBuiltIn) {
      return OCDocumentList(
        key: const ValueKey<String>('browse-files-file'),
        options: _options,
        selection: _documents,
        onToggle: _toggleDocument,
        scrollController: scrollController,
        canSelectMore: _canSelectMore,
      );
    }
    final builder = tab.builder;
    if (builder == null) {
      // An empty tab row falls through to the gallery branch above; this only
      // runs for unknown ids the host passed through `initialTabId`.
      return const SizedBox.shrink();
    }
    return _Fill(
      key: ValueKey<String>('browse-files-${tab.id}'),
      scrollController: scrollController,
      child: builder(context),
    );
  }

  Widget _confirmBar(ThemeData theme) {
    final error = _error;
    return Parent(
      style: ParentStyle()
        ..background.color(_barColor(theme))
        ..margin(horizontal: 16, bottom: 10)
        ..borderRadius(all: 106)
        ..padding(left: 16, top: 4, right: 8, bottom: 4)
        ..elevation(3, opacity: .5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              error ??
                  '${_media.length} media · ${_documents.length} files '
                      '(max ${_options.maxSelection})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: error == null ? null : theme.colorScheme.error,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _resolving ? null : _confirm,
            icon: _resolving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const SizedBox(),
            label: Text('${_options.confirmLabel} ($_count)'),
          ),
        ],
      ),
    );
  }
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
