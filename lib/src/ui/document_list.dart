import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/document_item.dart';

/// The Files tab — just the system Storage Access Framework picker.
///
/// Without `READ_EXTERNAL_STORAGE` the platform cannot list files outside
/// this app's own storage, so the tab loses its paged "recent files" list.
/// SAF (`ACTION_OPEN_DOCUMENT`) opens the same system picker Android users
/// see when they tap "Browse" in Files, and the picked URIs are copied into
/// the cache so the host app gets readable paths back.
///
/// This widget talks to the platform only through
/// [OCBrowseFilesFlutterPlatform], so the whole tab can be driven by a fake
/// in tests.
class OCDocumentList extends StatefulWidget {
  /// Creates the files tab.
  const OCDocumentList({
    required this.options,
    required this.selection,
    required this.onToggle,
    required this.canSelectMore,
    this.scrollController,
    this.bottomInset = 0,
    super.key,
  });

  /// The page's options: MIME filter, selection cap, multi-select.
  final OCBrowseFilesOptions options;

  /// The files currently selected, in pick order.
  final List<OCDocumentItem> selection;

  /// Called when a row is tapped.
  final ValueChanged<OCDocumentItem> onToggle;

  /// Whether another file may be added to the selection.
  ///
  /// The list does not know what else is selected elsewhere — the page
  /// counts media against the same cap — so it is told rather than
  /// counting.
  final bool canSelectMore;

  /// The scroll controller to drive the list with.
  final ScrollController? scrollController;

  /// Space to leave clear at the bottom, for a bar the sheet floats over the
  /// list.
  final double bottomInset;

  @override
  State<OCDocumentList> createState() => _OCDocumentListState();
}

class _OCDocumentListState extends State<OCDocumentList> {
  bool _picking = false;
  String? _error;

  OCBrowseFilesFlutterPlatform get _platform =>
      OCBrowseFilesFlutterPlatform.instance;

  /// Hands the user to the system picker, then puts what they chose at the
  /// top of the selection — it is what they came for.
  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    final List<String> paths;
    try {
      paths = await _platform.pickDocuments(
        mimeTypes: widget.options.documentMimeTypes,
        // A cap of one is a single pick, like the gallery: letting the picker
        // multi-select and then keeping only the first would be a surprise.
        allowMultiple:
            widget.options.allowMultipleDocuments &&
            widget.options.maxSelection > 1,
      );
    } on OCBrowseFilesException catch (error) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = error.isCancellation ? null : error.message;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = error.toString();
      });
      return;
    }
    if (!mounted) return;
    setState(() => _picking = false);
    for (final path in paths) {
      final item = OCDocumentItem.fromPath(path);
      if (!widget.selection.contains(item)) widget.onToggle(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.options.text;
    final error = _error;
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + widget.bottomInset,
      ),
      children: [
        const SizedBox(height: 8),
        ListTile(
          onTap: (_picking || !widget.canSelectMore) ? null : _pick,
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: const Icon(Icons.smartphone_outlined),
          ),
          title: Text(strings.storagePickerTitle),
          subtitle: Text(strings.storagePickerSubtitle),
          trailing: _picking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
