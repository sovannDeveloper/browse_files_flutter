import 'dart:typed_data';

import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:browse_files_flutter/src/ui/media_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatform platform;

  setUp(() {
    platform = _FakePlatform();
    BrowseFilesFlutterPlatform.instance = platform;
  });

  tearDown(() {
    BrowseFilesFlutterPlatform.instance = MethodChannelBrowseFilesFlutter();
  });

  testWidgets('opens on photos and videos, with a files tab beside it', (
    tester,
  ) async {
    platform.mediaTotal = 6;

    await _open(tester);

    expect(find.text('Photos & videos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.byType(MediaTile), findsWidgets);
  });

  testWidgets('the files tab lists what the platform will list', (
    tester,
  ) async {
    platform.documents = <DocumentItem>[
      DocumentItem(
        id: '7',
        name: 'quarterly-report.pdf',
        sizeBytes: 2411724,
        modifiedAt: DateTime(2026, 1, 2),
      ),
      DocumentItem(id: '8', name: 'notes.txt', sizeBytes: 512),
    ];

    await _open(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('quarterly-report.pdf'), findsOneWidget);
    expect(find.text('2.3 MB · 2 Jan 2026'), findsOneWidget);
    expect(find.text('512 B'), findsOneWidget);
    // The extension stands in for a file-type icon.
    expect(find.text('pdf'), findsOneWidget);
  });

  testWidgets('says so when the platform will not list the device', (
    tester,
  ) async {
    platform
      ..documents = const <DocumentItem>[]
      ..enumerable = false;

    await _open(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Files this app can see'), findsOneWidget);
    expect(find.textContaining('behind its own picker'), findsOneWidget);
    expect(find.textContaining('Nothing listed yet'), findsOneWidget);
  });

  testWidgets('the picker adds what it returns, already selected', (
    tester,
  ) async {
    platform.picked = <String>['/cache/contract.pdf'];

    await _open(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();

    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.text('Send (1)'), findsOneWidget);
  });

  testWidgets('the MIME filter reaches both the listing and the picker', (
    tester,
  ) async {
    platform.picked = <String>['/cache/clip.mp4'];
    const filter = <String>['image/*', 'video/*'];

    await _open(
      tester,
      options: const BrowseFilesOptions(documentMimeTypes: filter),
    );
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();

    expect(platform.listedWith, filter);
    expect(platform.pickedWith, filter);
  });

  testWidgets('one cap covers both tabs', (tester) async {
    platform
      ..mediaTotal = 4
      ..documents = <DocumentItem>[
        const DocumentItem(id: '7', name: 'a.pdf'),
        const DocumentItem(id: '8', name: 'b.pdf'),
      ];

    await _open(tester, options: const BrowseFilesOptions(maxSelection: 2));
    await tester.tap(find.byType(MediaTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Send (2)'), findsOneWidget);

    // Two is the cap, so the third pick is refused.
    await tester.tap(find.text('b.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Send (2)'), findsOneWidget);
    expect(find.text('1 media · 1 files (max 2)'), findsOneWidget);
  });

  testWidgets('confirming resolves the files it still has handles for', (
    tester,
  ) async {
    platform
      ..mediaTotal = 3
      ..documents = <DocumentItem>[
        const DocumentItem(id: '7', name: 'handle.pdf'),
        const DocumentItem(
          id: '/cache/already.txt',
          name: 'already.txt',
          path: '/cache/already.txt',
        ),
      ];

    final harness = await _open(tester);
    await tester.tap(find.byType(MediaTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('handle.pdf'));
    await tester.tap(find.text('already.txt'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send (3)'));
    await tester.pumpAndSettle();

    final result = harness.result;
    expect(result, isNotNull);
    expect(result!.media.single.id, 'asset-0');
    expect(result.documents, ['/cache/resolved-7', '/cache/already.txt']);
    // The one that already had a path was not resolved again.
    expect(platform.resolved, ['7']);
  });
}

/// Pushes the page over a throwaway screen and keeps what it returns.
Future<_Harness> _open(
  WidgetTester tester, {
  BrowseFilesOptions options = const BrowseFilesOptions(),
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              harness.result = await BrowseFiles.showPage(
                context,
                options: options,
                cache: ThumbnailCache(capacity: 16),
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
  BrowseFilesResult? result;
}

/// A platform with a synthetic library and a synthetic file list.
class _FakePlatform extends BrowseFilesFlutterPlatform {
  int mediaTotal = 0;
  List<DocumentItem> documents = const <DocumentItem>[];
  List<String> picked = const <String>[];
  List<String>? listedWith;
  List<String>? pickedWith;
  bool enumerable = true;
  final List<String> resolved = <String>[];

  @override
  Future<MediaPermissionStatus> permissionStatus({
    Set<MediaType> types = kAllMediaTypes,
  }) async => MediaPermissionStatus.granted;

  @override
  Future<MediaPage> fetchMedia({
    String? albumId,
    Set<MediaType> types = kAllMediaTypes,
    int offset = 0,
    int limit = 50,
  }) async {
    final end = (offset + limit).clamp(0, mediaTotal);
    return MediaPage(
      items: <MediaItem>[
        for (var i = offset; i < end; i++)
          MediaItem(
            id: 'asset-$i',
            type: MediaType.image,
            width: 100,
            height: 100,
            createdAt: DateTime(2026, 1, 1),
          ),
      ],
      offset: offset,
      total: mediaTotal,
    );
  }

  @override
  Future<DocumentPage> fetchDocuments({
    List<String> mimeTypes = const [],
    int offset = 0,
    int limit = 50,
  }) async {
    listedWith = mimeTypes;
    final end = (offset + limit).clamp(0, documents.length);
    return DocumentPage(
      items: offset >= end ? const [] : documents.sublist(offset, end),
      offset: offset,
      total: documents.length,
      enumerable: enumerable,
    );
  }

  @override
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) async => null;

  @override
  Future<String> resolveFile(String id) async {
    resolved.add(id);
    return '/cache/resolved-$id';
  }

  @override
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const <String>[],
    bool allowMultiple = true,
  }) async {
    pickedWith = mimeTypes;
    return picked;
  }
}
