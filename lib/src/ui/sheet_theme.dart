import 'package:flutter/material.dart';

import '../models/browse_files_options.dart';

/// The theme a sheet draws with, so a host app can hand it Telegram's dark
/// chrome without dyeing the app around it.
///
/// No [OCBrowseFilesOptions.backgroundColor] means the app's own theme, with
/// the primary swapped for [OCBrowseFilesOptions.accentColor] when there is
/// one; a background builds a whole scheme of the right brightness on top.
ThemeData buildSheetTheme(ThemeData base, OCBrowseFilesOptions options) {
  final background = options.backgroundColor;
  final accent = options.accentColor;
  if (background == null) {
    return accent == null
        ? base
        : base.copyWith(
            colorScheme: base.colorScheme.copyWith(primary: accent),
          );
  }
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent ?? base.colorScheme.primary,
      brightness: ThemeData.estimateBrightnessForColor(background),
    ).copyWith(surface: background, primary: accent),
  );
}

/// One step away from the sheet's surface, so a bar reads as a bar.
Color sheetBarColor(ThemeData theme) {
  final surface = theme.colorScheme.surface;
  final tint = ThemeData.estimateBrightnessForColor(surface) == Brightness.dark
      ? Colors.white
      : Colors.black;
  return Color.alphaBlend(tint.withValues(alpha: 0.07), surface);
}

/// The pill above a sheet that says "drag me".
class SheetDragHandle extends StatelessWidget {
  /// Creates the handle.
  const SheetDragHandle({super.key});

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
