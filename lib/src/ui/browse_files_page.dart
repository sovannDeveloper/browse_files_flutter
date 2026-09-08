import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/browse_files_result.dart';
import '../models/document_item.dart';
import '../models/media_item.dart';
import 'document_list.dart';
import 'media_grid.dart';
import 'thumbnail_cache.dart';

/// A full screen of everything attachable, split by kind: photos and videos in
/// one tab, every other file in the next.
///
/// The sheet is for picking something quickly without leaving the screen; this
/// is for browsing. Both hand back the same [OCBrowseFilesResult], and the
/// selection cap counts across both tabs — ten attachments is ten, whichever
/// tab they came from.
class OCBrowseFilesPage extends StatefulWidget {
  /// Creates the page.
  const OCBrowseFilesPage({
    this.options = const OCBrowseFilesOptions(),
    this.cache,
    this.title = 'Attach',
    super.key,
  });

  /// How the page should behave: types, paging, cap, MIME filter.
  final OCBrowseFilesOptions options;

  /// The thumbnail cache to draw from; defaults to [OCThumbnailCache.shared].
  final OCThumbnailCache? cache;

  /// The app bar's title.
  final String title;

  @override
  State<OCBrowseFilesPage> createState() => _OCBrowseFilesPageState();
}

class _OCBrowseFilesPageState extends State<OCBrowseFilesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// A controller per tab: two scrollables sharing the primary one would fight
  /// over it mid-swipe.
  final ScrollController _mediaScroll = ScrollController();
  final ScrollController _documentScroll = ScrollController();

  final List<OCMediaItem> _media = <OCMediaItem>[];
  final List<OCDocumentItem> _documents = <OCDocumentItem>[];

  bool _resolving = false;
  String? _error;

  OCBrowseFilesOptions get _options => widget.options;

  int get _count => _media.length + _documents.length;

  bool get _canSelectMore => _count < _options.maxSelection;

  @override
  void dispose() {
    _tabs.dispose();
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

  /// Turns the selection into something the host app can read.
  ///
  /// Media stay as ids — resolving a ten-photo selection is slow and the
  /// caller may only want some of it — but documents were chosen *as* files,
  /// so the ones that are still platform handles are copied out here.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.perm_media_outlined), text: 'Photos & videos'),
            Tab(icon: Icon(Icons.folder_outlined), text: 'Files'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          OCMediaGrid(
            options: _options,
            cache: widget.cache ?? OCThumbnailCache.shared,
            selection: _media,
            onToggle: _toggleMedia,
            scrollController: _mediaScroll,
            canSelectMore: _canSelectMore,
          ),
          OCDocumentList(
            options: _options,
            selection: _documents,
            onToggle: _toggleDocument,
            scrollController: _documentScroll,
            canSelectMore: _canSelectMore,
          ),
        ],
      ),
      bottomNavigationBar: _count == 0 ? null : _confirmBar(theme),
    );
  }

  Widget _confirmBar(ThemeData theme) {
    final error = _error;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
                  : const Icon(Icons.check, size: 18),
              label: Text('${_options.confirmLabel} ($_count)'),
            ),
          ],
        ),
      ),
    );
  }
}
