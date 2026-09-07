import 'package:flutter/rendering.dart';

/// The grid geometry Telegram uses: a leading tile that is [leadingRowSpan] rows
/// tall in the first column, with the rest of the library flowing around it.
///
/// Flutter has no built-in delegate that lets one cell span rows, and pulling in
/// a staggered-grid package for a single tile is not worth the dependency, so
/// the layout is computed here.
class AttachmentGridDelegate extends SliverGridDelegate {
  /// Creates the delegate.
  const AttachmentGridDelegate({
    required this.crossAxisCount,
    this.spacing = 2,
    this.leadingRowSpan = 2,
  }) : assert(crossAxisCount > 0, 'a grid needs at least one column'),
       assert(leadingRowSpan > 0, 'the leading tile spans at least one row');

  /// Columns in the grid.
  final int crossAxisCount;

  /// The gap between tiles, both ways.
  final double spacing;

  /// How many rows the first tile is tall.
  final int leadingRowSpan;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final available =
        constraints.crossAxisExtent - spacing * (crossAxisCount - 1);
    return _AttachmentGridLayout(
      crossAxisCount: crossAxisCount,
      tileExtent: available / crossAxisCount,
      spacing: spacing,
      leadingRowSpan: leadingRowSpan,
    );
  }

  @override
  bool shouldRelayout(AttachmentGridDelegate oldDelegate) =>
      oldDelegate.crossAxisCount != crossAxisCount ||
      oldDelegate.spacing != spacing ||
      oldDelegate.leadingRowSpan != leadingRowSpan;
}

class _AttachmentGridLayout extends SliverGridLayout {
  const _AttachmentGridLayout({
    required this.crossAxisCount,
    required this.tileExtent,
    required this.spacing,
    required this.leadingRowSpan,
  });

  final int crossAxisCount;
  final double tileExtent;
  final double spacing;
  final int leadingRowSpan;

  double get _stride => tileExtent + spacing;

  /// The cells left beside the tall leading tile.
  int get _sideSlots => leadingRowSpan * (crossAxisCount - 1);

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount <= 0) return 0;
    return _rowsFor(childCount) * _stride - spacing;
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (index == 0) {
      return SliverGridGeometry(
        scrollOffset: 0,
        crossAxisOffset: 0,
        mainAxisExtent:
            tileExtent * leadingRowSpan + spacing * (leadingRowSpan - 1),
        crossAxisExtent: tileExtent,
      );
    }
    final slot = index - 1;
    final int row;
    final int column;
    if (slot < _sideSlots) {
      row = slot ~/ (crossAxisCount - 1);
      column = 1 + slot % (crossAxisCount - 1);
    } else {
      final rest = slot - _sideSlots;
      row = leadingRowSpan + rest ~/ crossAxisCount;
      column = rest % crossAxisCount;
    }
    return SliverGridGeometry(
      scrollOffset: row * _stride,
      crossAxisOffset: column * _stride,
      mainAxisExtent: tileExtent,
      crossAxisExtent: tileExtent,
    );
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    final row = _rowAt(scrollOffset);
    // The leading tile reaches into every row it spans, so it stays in range.
    if (row < leadingRowSpan) return 0;
    return 1 + _sideSlots + (row - leadingRowSpan) * crossAxisCount;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    final row = _rowAt(scrollOffset);
    if (row < leadingRowSpan) return _sideSlots;
    return _sideSlots + (row - leadingRowSpan + 1) * crossAxisCount;
  }

  int _rowAt(double scrollOffset) =>
      scrollOffset <= 0 ? 0 : (scrollOffset / _stride).floor();

  int _rowsFor(int childCount) {
    if (childCount <= 1 + _sideSlots) return leadingRowSpan;
    final rest = childCount - 1 - _sideSlots;
    return leadingRowSpan + (rest / crossAxisCount).ceil();
  }
}
