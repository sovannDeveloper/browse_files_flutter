import 'package:flutter/material.dart';

import '../models/attachment_tab.dart';

/// The floating, horizontally scrollable row of attachment kinds along the
/// sheet's bottom edge, the open one sitting in a tinted pill.
class AttachmentTabBar extends StatelessWidget {
  /// Creates the tab row.
  const AttachmentTabBar({
    required this.tabs,
    required this.activeId,
    required this.onSelected,
    this.barColor,
    super.key,
  });

  /// The tabs to show, left to right.
  final List<AttachmentTab> tabs;

  /// The [AttachmentTab.id] currently open.
  final String activeId;

  /// Called with the tab the user tapped.
  final ValueChanged<AttachmentTab> onSelected;

  /// The bar's own colour, a step away from the sheet behind it.
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    // A single tab needs no bar — the sheet's content already names what it
    // is, and a row of one would just duplicate that label.
    if (tabs.length <= 1) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: barColor ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(26),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(6),
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

  final AttachmentTab tab;
  final bool active;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final badge = tab.badge;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
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
                fontSize: 12,
                color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
