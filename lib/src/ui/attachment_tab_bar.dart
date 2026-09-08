import 'package:division/division.dart';
import 'package:flutter/material.dart';

import '../models/attachment_tab.dart';

/// The floating, horizontally scrollable row of attachment kinds along the
/// sheet's bottom edge, the open one sitting in a tinted pill.
class OCAttachmentTabBar extends StatelessWidget {
  /// Creates the tab row.
  const OCAttachmentTabBar({
    required this.tabs,
    required this.activeId,
    required this.onSelected,
    this.barColor,
    super.key,
  });

  /// The tabs to show, left to right.
  final List<OCAttachmentTab> tabs;

  /// The [OCAttachmentTab.id] currently open.
  final String activeId;

  /// Called with the tab the user tapped.
  final ValueChanged<OCAttachmentTab> onSelected;

  /// The bar's own colour, a step away from the sheet behind it.
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    // A single tab needs no bar — the sheet's content already names what it
    // is, and a row of one would just duplicate that label.
    if (tabs.length <= 1) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final barStyle = ParentStyle()
      ..margin(left: 8, top: 4, right: 8, bottom: 8)
      ..padding(all: 6)
      ..borderRadius(all: 100)
      ..background.color(barColor ?? scheme.surfaceContainerHighest)
      ..overflow.hidden();
    return Parent(
      style: barStyle,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in tabs)
              _TabButton(
                tab: tab,
                active: tab.id == activeId,
                scheme: scheme,
                onTap: () => onSelected(tab),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.active,
    required this.scheme,
    required this.onTap,
  });

  final OCAttachmentTab tab;
  final bool active;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final badge = tab.badge;
    return Parent(
      style: ParentStyle()
        ..width(78)
        ..padding(vertical: 8)
        ..borderRadius(all: 100)
        ..ripple(true)
        ..background.color(
          active ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
        )
        ..animate(150, Curves.easeOut),
      gesture: Gestures()..onTap(onTap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(tab.icon, size: 24, color: color),
              if (badge != null) Positioned(right: -5, top: -3, child: badge),
            ],
          ),
          Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
