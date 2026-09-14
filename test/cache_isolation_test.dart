import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('simple cache test', (tester) async {
    final cache = OCThumbnailCache(capacity: 4);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: (_) => const SizedBox.shrink())),
    );

    await cache.load('a', width: 256, height: 256);
    expect(cache.length, 1);
  });
}
