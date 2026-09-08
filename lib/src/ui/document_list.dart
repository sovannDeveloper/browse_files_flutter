import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/document_item.dart';

/// The Files tab: what the platform will list, and the system picker for
/// everything it will not.
///
/// Neither OS lets an app walk the user's storage any more — Android 11
/// scoped it, iOS never allowed it — so this shows what is enumerable and puts
/// the picker at the top rather than pretending the device is empty.
class DocumentList extends StatefulWidget {
  /// Creates the files tab.
  const DocumentList({
    required this.options,
    required this.selection,
    required this.onToggle,
    required this.canSelectMore,
    this.scrollController,
    super.key,
  });

  /// The page's options: paging, MIME filter, selection cap.
  final BrowseFilesOptions options;

  /// The files currently selected, in pick order.
  final List<DocumentItem> selection;

  /// Called when a row is tapped.
  final ValueChanged<DocumentItem> onToggle;

  /// Whether another file may be added to the selection.
  final bool canSelectMore;

  /// The scroll controller to drive the list with.
  final ScrollController? scrollController;

  @override
  State<DocumentList> createState() => _DocumentListState();
}

class _DocumentListState extends State<DocumentList> {
  final List<DocumentItem> _items = <DocumentItem>[];

  /// The ids already listed: storage that changes between pages shifts the
  /// offsets after it, and the same file would otherwise be listed twice.
  final Set<String> _ids = <String>{};

  int _total = 0;
  bool _enumerable = true;
  bool _busy = true;
  bool _loadingPage = false;
  bool _picking = false;
  String? _error;

  BrowseFilesFlutterPlatform get _platform =>
      BrowseFilesFlutterPlatform.instance;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _loadMore(reset: true);
  }

  /// Fetches the next page; see [MediaGrid] for why this never calls
  /// `setState` before its first await.
  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingPage) return;
    _loadingPage = true;
    final offset = reset ? 0 : _items.length;
    final page = await _guard(
      () => _platform.fetchDocuments(
        mimeTypes: widget.options.documentMimeTypes,
        offset: offset,
        limit: widget.options.pageSize,
      ),
    );
    _loadingPage = false;
    if (!mounted || page == null) return;
    setState(() {
      if (reset) {
        _items.clear();
        _ids.clear();
      }
      for (final item in page.items) {
        if (_ids.add(item.id)) _items.add(item);
      }
      // A short page is the end of the listing, whatever the total claims.
      _total = page.items.length < widget.options.pageSize
          ? _items.length
          : (page.total > _items.length ? page.total : _items.length);
      _enumerable = page.enumerable;
      _busy = false;
    });
  }

  /// Hands the user to the system picker, then puts what they chose at the top
  /// of the list, already selected — it is what they came for.
  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final paths = await _platform.pickDocuments(
        mimeTypes: widget.options.documentMimeTypes,
        allowMultiple: widget.options.allowMultipleDocuments,
      );
      if (!mounted) return;
      final picked = <DocumentItem>[
        for (final path in paths) DocumentItem.fromPath(path),
      ];
      setState(() {
        _picking = false;
        for (final item in picked.reversed) {
          _items
            ..remove(item)
            ..insert(0, item);
          _ids.add(item.id);
        }
        _total = _items.length > _total ? _items.length : _total;
      });
      for (final item in picked) {
        if (!widget.selection.contains(item)) widget.onToggle(item);
      }
    } on BrowseFilesException catch (error) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = error.isCancellation ? null : error.message;
      });
    }
  }

  Future<T?> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
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
    if (_busy && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: widget.scrollController,
      // The header is row zero, and a trailing row carries the spinner while
      // there is another page to come.
      itemCount: _items.length + 1 + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) return _header(context);
        final position = index - 1;
        if (position >= _items.length) {
          _loadMore();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final item = _items[position];
        if (_hasMore &&
            position >= _items.length - widget.options.pageSize ~/ 3) {
          _loadMore();
        }
        final order = widget.selection.indexOf(item);
        return _DocumentRow(
          item: item,
          order: order < 0 ? null : order + 1,
          enabled: widget.canSelectMore || order >= 0,
          onTap: () => widget.onToggle(item),
        );
      },
    );
  }

  /// The storage entry that opens the system picker, and the heading for the
  /// listing under it.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          onTap: _picking ? null : _pick,
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: const Icon(Icons.smartphone_outlined),
          ),
          title: const Text('Internal Storage'),
          subtitle: const Text('Browse your file system'),
          trailing: _picking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('Recent files', style: theme.textTheme.titleSmall),
              if (!_enumerable)
                Text(
                  'The system keeps the rest of your storage behind its own '
                  'picker: Android 11 scoped it and iOS never opened it. Tap '
                  'Internal Storage to reach anything that is not listed here.',
                  style: theme.textTheme.bodySmall,
                ),
              if (error != null)
                Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              if (_items.isEmpty && !_busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No recent files — open Internal Storage to pick one.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One file in the list.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.item,
    required this.order,
    required this.enabled,
    required this.onTap,
  });

  final DocumentItem item;
  final int? order;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = order != null;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurfaceVariant,
        child: selected
            ? Text(
                '$order',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : Text(
                item.extension.isEmpty
                    ? '?'
                    : item.extension.substring(
                        0,
                        item.extension.length.clamp(0, 3),
                      ),
                style: const TextStyle(fontSize: 11),
              ),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_subtitle(item)),
    );
  }

  static String _subtitle(DocumentItem item) {
    final parts = <String>[
      if (item.sizeBytes != null) formatFileSize(item.sizeBytes!),
      if (item.modifiedAt != null) formatFileDate(item.modifiedAt!),
    ];
    return parts.isEmpty ? (item.mimeType ?? 'file') : parts.join(' · ');
  }
}

/// `1.2 MB`, the way a file list writes it.
String formatFileSize(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final rounded = unit == 0 || size >= 100
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}

/// `2 Jan 2026`, without dragging in a date-formatting package.
String formatFileDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
