import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:browse_files_flutter_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts with nothing called', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Nothing called yet'), findsOneWidget);
    expect(find.text('Tap a button above to get started'), findsOneWidget);
  });

  testWidgets('the attach button opens the menu', (WidgetTester tester) async {
    _useFakePlatform();

    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Attach'));
    await tester.pumpAndSettle();

    // The menu is pushed onto the app's Navigator, so this fails outright if
    // the screen is ever hoisted above MaterialApp again.
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Record video'), findsOneWidget);
    expect(find.text('Select photos & videos'), findsOneWidget);
    expect(find.text('Select files'), findsOneWidget);
  });

  testWidgets('captureMedia is routed to the platform', (
    WidgetTester tester,
  ) async {
    final platform = _useFakePlatform();

    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('captureMedia(image)'));
    await tester.pumpAndSettle();

    expect(platform.captures, <OCMediaType>[OCMediaType.image]);
    expect(find.textContaining('/cache/shot.jpg'), findsOneWidget);
  });

  testWidgets('pickMedia is routed to the platform', (
    WidgetTester tester,
  ) async {
    final platform = _useFakePlatform();

    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('pickMedia()'));
    await tester.pumpAndSettle();

    expect(platform.picks, 1);
    expect(find.textContaining('1 item(s)'), findsOneWidget);
  });

  testWidgets('pickDocuments is routed to the platform', (
    WidgetTester tester,
  ) async {
    _useFakePlatform();

    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('pickDocuments()'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/cache/doc.pdf'), findsOneWidget);
  });
}

/// Installs [_FakePlatform] for one test and puts the real one back after.
///
/// Anything that opens the sheet or the page needs this: a method channel with
/// no native side behind it never completes inside a widget test's fake async,
/// so the grid would sit on its spinner until `pumpAndSettle` gave up.
_FakePlatform _useFakePlatform() {
  final platform = _FakePlatform();
  OCBrowseFilesFlutterPlatform.instance = platform;
  addTearDown(
    () => OCBrowseFilesFlutterPlatform.instance =
        OCMethodChannelBrowseFilesFlutter(),
  );
  return platform;
}

/// A platform that answers without touching a channel.
class _FakePlatform extends OCBrowseFilesFlutterPlatform {
  /// The kinds the camera was opened for, in order.
  final List<OCMediaType> captures = <OCMediaType>[];

  int picks = 0;

  @override
  Future<List<OCMediaItem>> pickMedia({
    Set<OCMediaType> types = kAllMediaTypes,
    bool allowMultiple = true,
  }) async {
    picks++;
    return <OCMediaItem>[
      OCMediaItem(
        id: 'content://media/picker/0/1',
        type: OCMediaType.image,
        width: 1080,
        height: 1920,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<OCMediaItem?> captureMedia({
    OCMediaType type = OCMediaType.image,
  }) async {
    captures.add(type);
    return OCMediaItem(
      id: '/cache/shot.jpg',
      type: type,
      width: 1080,
      height: 1920,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) async => const <String>['/cache/doc.pdf'];
}
