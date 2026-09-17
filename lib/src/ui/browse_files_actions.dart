import 'package:flutter/material.dart';

import '../browse_files_flutter_platform_interface.dart';
import '../models/browse_files_action.dart';
import '../models/browse_files_exception.dart';
import '../models/browse_files_options.dart';
import '../models/browse_files_result.dart';
import '../models/browse_files_strings.dart';
import '../models/media_item.dart';
import '../models/media_type.dart';
import 'sheet_theme.dart';

/// The short attachment menu: take a photo, record a video, select photos &
/// videos, select files.
///
/// A row's text is [OCBrowseFilesAction.label] when set — see
/// [OCBrowseFilesAction.withLabel] — and the matching [OCBrowseFilesStrings]
/// entry otherwise.
///
/// A row does not do its work in place — the sheet pops with the chosen
/// [OCBrowseFilesAction] and the caller runs it through [runBrowseFilesAction]
/// once the sheet is gone, so the system camera or picker never opens
/// underneath a half-dismissed sheet. `OCBrowseFiles.showActions` is that
/// caller; the widget is public so it can be embedded or widget-tested on its
/// own.
class OCBrowseFilesActionsSheet extends StatelessWidget {
  /// Creates the menu.
  const OCBrowseFilesActionsSheet({
    this.options = const OCBrowseFilesOptions(),
    this.actions,
    this.showTitle = true,
    super.key,
  });

  /// Colours, strings and which kinds the camera may capture.
  final OCBrowseFilesOptions options;

  /// The rows, top to bottom; `null` for [OCBrowseFilesAction.defaultsFor].
  final List<OCBrowseFilesAction>? actions;

  /// Whether [OCBrowseFilesStrings.actionsTitle] heads the menu.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final theme = buildSheetTheme(Theme.of(context), options);
    final strings = options.text;
    final rows = actions ?? OCBrowseFilesAction.defaultsFor(options);
    return Theme(
      data: theme,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              if (showTitle)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      strings.actionsTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              for (final action in rows)
                _ActionRow(
                  key: ValueKey<OCBrowseFilesAction>(action),
                  icon: action.icon,
                  label: action.labelFor(strings),
                  onTap: () => Navigator.of(context).pop(action),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(label),
    );
  }
}

/// Does what a menu row promised, once the menu is out of the way.
///
/// The camera rows resolve to one item or nothing; the gallery row to what
/// the system picker returned, cut at [OCBrowseFilesOptions.maxSelection];
/// the files row to cached paths. A picker the user backed out of is
/// [OCBrowseFilesResult.empty], not an error. Platform failures propagate as
/// `OCBrowseFilesException` — there is no sheet left to show them in.
///
/// A host camera ([OCBrowseFilesOptions.onCameraTap]) replaces the built-in
/// one here as it does on the sheet's tile: the callback runs and the result
/// is [OCBrowseFilesResult.empty], since whatever it captured never passes
/// through the plugin.
Future<OCBrowseFilesResult> runBrowseFilesAction(
  OCBrowseFilesAction action,
  OCBrowseFilesOptions options, {
  OCBrowseFilesFlutterPlatform? platform,
}) async {
  final api = platform ?? OCBrowseFilesFlutterPlatform.instance;
  switch (action.kind) {
    case OCBrowseFilesActionKind.takePhoto:
    case OCBrowseFilesActionKind.recordVideo:
      final custom = options.onCameraTap;
      if (custom != null) {
        custom();
        return OCBrowseFilesResult.empty;
      }
      final type = action.kind == OCBrowseFilesActionKind.takePhoto
          ? OCMediaType.image
          : OCMediaType.video;
      await ensureCameraPermission(api, type, options.text);
      final item = await api.captureMedia(type: type);
      return item == null
          ? OCBrowseFilesResult.empty
          : OCBrowseFilesResult(media: <OCMediaItem>[item]);
    case OCBrowseFilesActionKind.gallery:
      final picked = await api.pickMedia(
        types: options.types.isEmpty ? kAllMediaTypes : options.types,
        allowMultiple: options.allowMultipleMedia && options.maxSelection > 1,
      );
      return OCBrowseFilesResult(
        media: List<OCMediaItem>.unmodifiable(
          picked.take(options.maxSelection),
        ),
      );
    case OCBrowseFilesActionKind.files:
      final paths = await api.pickDocuments(
        mimeTypes: options.documentMimeTypes,
        allowMultiple:
            options.allowMultipleDocuments && options.maxSelection > 1,
      );
      return OCBrowseFilesResult(
        documents: List<String>.unmodifiable(paths.take(options.maxSelection)),
      );
  }
}

/// Asks for the camera before it is opened, and throws `permissionDenied`
/// when the user refused — so a refused camera is a message, not a dead tap
/// or a black preview.
///
/// Anything else the platform reports (a missing purpose string, no
/// activity) propagates as it is.
Future<void> ensureCameraPermission(
  OCBrowseFilesFlutterPlatform api,
  OCMediaType type,
  OCBrowseFilesStrings strings,
) async {
  final status = await api.requestCameraPermission(type: type);
  if (!status.isGranted) {
    throw OCBrowseFilesException(
      OCBrowseFilesErrorCode.permissionDenied,
      strings.cameraPermissionDenied,
      details: status.name,
    );
  }
}
