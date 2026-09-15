import 'dart:typed_data';

import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:browse_files_flutter/src/ui/media_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    OCBrowseFilesFlutterPlatform.instance = platform;
  });

  tearDown(() {
    OCBrowseFilesFlutterPlatform.instance = OCMethodChannelBrowseFilesFlutter();
  });

  testWidgets('opens on the gallery, with a files tab beside it', (
    tester,
  ) async {
    platform.picked = <OCMediaItem>[
      for (var i = 0; i < 6; i++)
        _item(id: 'asset-$i', type: OCMediaType.image),
    ];

    await _open(tester);

    expect(find.text('Photos & videos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    // The gallery starts on its CTA; the grid fills once the picker answers.
    expect(find.byType(OCMediaTile), findsNothing);
    await tester.tap(
      find.text(const OCBrowseFilesStrings().galleryEmptyActionLabel),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OCMediaTile), findsNWidgets(6));
  });

  testWidgets('the files tab opens the system picker', (tester) async {
    platform.documents = <String>['/cache/report.pdf', '/cache/notes.txt'];

    final harness = await _open(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Internal Storage'), findsOneWidget);
    expect(find.text('Browse your file system'), findsOneWidget);
    await tester.tap(find.text('Internal Storage'));
    await tester.pumpAndSettle();
    // The page pops only when the user confirms — Telegram's pattern.
    expect(find.text('Select (2)'), findsOneWidget);

    await tester.tap(find.text('Select (2)'));
    await tester.pumpAndSettle();

    expect(harness.result?.documents, platform.documents);
    expect(harness.result?.media, isEmpty);
  });

  testWidgets('a dismissed document picker leaves the page open', (
    tester,
  ) async {
    platform.documents = const <String>[];

    final harness = await _open(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal Storage'));
    await tester.pumpAndSettle();

    expect(harness.result, isNull);
    // The page stays put — no confirm bar popped up because nothing was picked.
    expect(find.text('Internal Storage'), findsOneWidget);
  });

  testWidgets('one cap covers both tabs', (tester) async {
    platform.picked = <OCMediaItem>[
      for (var i = 0; i < 2; i++)
        _item(id: 'asset-$i', type: OCMediaType.image),
    ];

    final harness = await _open(
      tester,
      options: const OCBrowseFilesOptions(maxSelection: 2),
    );
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();
    expect(find.text('Select (2)'), findsOneWidget);

    // The cap is filled; another tap would not pick a third item.
    expect(find.byType(OCMediaTile), findsNWidgets(2));

    // Switching to Files tab keeps the selection — the cap is across both.
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Select (2)'), findsOneWidget);
    // The Files tab is dimmed: tapping it would do nothing.
    await tester.tap(find.text('Internal Storage'));
    await tester.pumpAndSettle();
    expect(harness.result, isNull);
    expect(find.text('Select (2)'), findsOneWidget);
  });

  testWidgets('confirming returns media ids and resolved document paths', (
    tester,
  ) async {
    platform.picked = <OCMediaItem>[
      _item(id: 'asset-0', type: OCMediaType.image),
    ];
    platform.documents = <String>['/cache/report.pdf'];

    final harness = await _open(tester);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();
    // The picker auto-toggled asset-0 in; the confirm bar now shows (1).
    expect(find.text('Select (1)'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal Storage'));
    await tester.pumpAndSettle();

    expect(find.text('Select (2)'), findsOneWidget);

    await tester.tap(find.text('Select (2)'));
    await tester.pumpAndSettle();

    final result = harness.result;
    expect(result, isNotNull);
    expect(result!.media.single.id, 'asset-0');
    expect(result.documents, ['/cache/report.pdf']);
  });
}

OCMediaItem _item({required String id, required OCMediaType type}) =>
    OCMediaItem(
      id: id,
      type: type,
      width: 100,
      height: 100,
      createdAt: DateTime(2026, 1, 1),
    );

/// Pushes the page over a throwaway screen and keeps what it returns.
Future<_Harness> _open(
  WidgetTester tester, {
  OCBrowseFilesOptions options = const OCBrowseFilesOptions(),
}) async {
  final harness = _Harness();
  _usePhoneViewport(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              harness.result = await OCBrowseFiles.showPage(
                context,
                options: options,
                cache: OCThumbnailCache(capacity: 16),
              );
            },
            child: const Text('open page'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open page'));
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  OCBrowseFilesResult? result;
}

/// A phone-shaped window: the default 800x600 makes each of three columns
/// ~265px tall, so a sheet at peek height shows barely one row.
void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A platform that picks and returns whatever the test said to.
class _FakePlatform extends OCBrowseFilesFlutterPlatform {
  List<OCMediaItem> picked = <OCMediaItem>[];
  List<String> documents = const <String>[];
  List<String>? pickedWith;

  OCBrowseFilesStrings get strings => const OCBrowseFilesStrings();

  @override
  Future<List<OCMediaItem>> pickMedia({
    Set<OCMediaType> types = kAllMediaTypes,
    bool allowMultiple = true,
  }) async => picked;

  @override
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) async => null;

  @override
  Future<String> resolveFile(String id) async => '/cache/$id.jpg';

  @override
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const <String>[],
    bool allowMultiple = true,
  }) async {
    pickedWith = mimeTypes;
    return documents;
  }

  @override
  Future<OCCameraPermission> requestCameraPermission({
    OCMediaType type = OCMediaType.image,
  }) async => OCCameraPermission.granted;
}
