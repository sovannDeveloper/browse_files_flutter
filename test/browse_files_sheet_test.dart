import 'dart:typed_data';

import 'package:browse_files_flutter/browse_files_flutter.dart';
// The tile is an implementation detail of the sheet, not public API; these
// tests are inside the package, so they may reach for it directly.
import 'package:browse_files_flutter/src/ui/attachment_tab_bar.dart';
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

  testWidgets('shows a grid of the library, newest first', (tester) async {
    platform.total = 12;

    final harness = await _open(tester);

    expect(find.byType(OCMediaTile), findsWidgets);
    expect(platform.fetchedPages, isNotEmpty);
    expect(platform.fetchedPages.first.limit, 50);
    expect(harness.result, isNull, reason: 'nothing confirmed yet');
  });

  testWidgets('the gallery bar switches the grid to another album', (
    tester,
  ) async {
    platform
      ..total = 12
      ..albums = <OCMediaAlbum>[
        const OCMediaAlbum(
          id: 'all',
          name: 'All media',
          count: 12,
          isAll: true,
        ),
        const OCMediaAlbum(id: 'camera', name: 'Camera', count: 4),
      ];

    await _open(tester);

    expect(find.text('All media'), findsOneWidget);
    expect(find.text('12 items'), findsOneWidget);
    expect(platform.fetchedAlbumIds, [null]);

    await tester.tap(find.text('All media'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera').last);
    await tester.pumpAndSettle();

    expect(platform.fetchedAlbumIds.last, 'camera');
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('4 items'), findsOneWidget);
  });

  testWidgets('one album leaves the gallery bar off', (tester) async {
    platform.total = 6;

    await _open(tester);

    expect(find.text('All media'), findsNothing);
  });

  testWidgets('pages the library in as the grid is scrolled', (tester) async {
    platform.total = 130;

    await _open(tester);

    expect(platform.fetchedPages, [(offset: 0, limit: 50)]);
    await _scrollToEnd(tester);

    // Fifty at a time, each page asked for once and in order.
    expect(platform.fetchedPages, [
      (offset: 0, limit: 50),
      (offset: 50, limit: 50),
      (offset: 100, limit: 50),
    ]);
    expect(find.byType(OCMediaTile), findsWidgets);
  });

  testWidgets('a library that shifts while it is paged lists no asset twice', (
    tester,
  ) async {
    platform
      ..total = 130
      ..overlap = 5;

    await _open(tester);
    // Duplicate ids would throw on the grid's keys before this returned.
    await _scrollToEnd(tester);

    final ids = tester
        .widgetList<OCMediaTile>(find.byType(OCMediaTile))
        .map((tile) => tile.item.id)
        .toList();
    expect(ids.toSet().length, ids.length, reason: 'one tile per asset');
  });

  testWidgets('tapping tiles selects them in order and confirms', (
    tester,
  ) async {
    platform.total = 6;

    final harness = await _open(tester);
    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();

    // The first pick is numbered 1 and the confirm bar counts it.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Send (1)'), findsOneWidget);

    await tester.tap(find.byType(OCMediaTile).at(1));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Send (2)'), findsOneWidget);

    await tester.tap(find.text('Send (2)'));
    await tester.pumpAndSettle();

    final result = harness.result;
    expect(result, isNotNull);
    expect(result!.media, hasLength(2));
    expect(result.media.first.id, 'asset-0');
    expect(result.media.last.id, 'asset-1');
    expect(result.documents, isEmpty);
  });

  testWidgets('a second tap deselects', (tester) async {
    platform.total = 4;

    await _open(tester);
    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Send (1)'), findsOneWidget);

    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Send ('), findsNothing);
  });

  testWidgets('selection stops at maxSelection', (tester) async {
    platform.total = 9;

    await _open(tester, options: const OCBrowseFilesOptions(maxSelection: 2));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(OCMediaTile).at(i));
      await tester.pumpAndSettle();
    }

    expect(find.text('Send (2)'), findsOneWidget);
    expect(find.text('2 of 2 selected'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('videos carry a duration badge', (tester) async {
    platform
      ..total = 3
      ..videoDuration = const Duration(hours: 1, minutes: 32, seconds: 48);

    await _open(tester);

    // asset-1 is the video: every third item in the fake library.
    expect(find.text('1:32:48'), findsOneWidget);
  });

  testWidgets('asks for access when the library is off limits', (tester) async {
    platform
      ..status = OCMediaPermissionStatus.denied
      ..total = 5;

    await _open(tester);
    expect(find.text('Let this app see your photos'), findsOneWidget);
    expect(platform.fetchedPages, isEmpty, reason: 'no paging before a grant');

    platform.grantOnRequest = OCMediaPermissionStatus.granted;
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();

    expect(platform.requests, 1);
    expect(find.byType(OCMediaTile), findsWidgets);
  });

  testWidgets('permanently denied points at Settings instead of prompting', (
    tester,
  ) async {
    platform.status = OCMediaPermissionStatus.permanentlyDenied;

    await _open(tester);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(platform.settingsOpened, 1);
    expect(platform.requests, 0);
  });

  testWidgets('a limited grant still browses, and offers to widen', (
    tester,
  ) async {
    platform
      ..status = OCMediaPermissionStatus.limited
      ..total = 4;

    await _open(tester);
    expect(find.byType(OCMediaTile), findsWidgets);
    expect(find.text('You shared some of your library'), findsOneWidget);

    await tester.tap(find.text('Select more'));
    await tester.pumpAndSettle();

    expect(platform.limitedPickerShown, 1);
  });

  testWidgets('the File tab hands back cached document paths', (tester) async {
    platform.documents = <String>['/cache/report.pdf', '/cache/notes.txt'];

    final harness = await _open(tester);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Browse files'), findsOneWidget);
    await tester.tap(find.text('Browse files'));
    await tester.pumpAndSettle();

    expect(harness.result?.documents, platform.documents);
    expect(harness.result?.media, isEmpty);
  });

  testWidgets('a dismissed document picker leaves the sheet open', (
    tester,
  ) async {
    platform.documents = const <String>[];

    final harness = await _open(tester);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse files'));
    await tester.pumpAndSettle();

    expect(harness.result, isNull);
    expect(find.text('Browse files'), findsOneWidget);
  });

  testWidgets('custom tabs are built by the host app', (tester) async {
    const options = OCBrowseFilesOptions(
      tabs: <OCAttachmentTab>[
        OCAttachmentTab.gallery,
        OCAttachmentTab.custom(
          id: 'poll',
          label: 'Poll',
          icon: Icons.poll_outlined,
          builder: _pollBody,
        ),
      ],
    );

    await _open(tester, options: options);
    await tester.tap(find.text('Poll'));
    await tester.pumpAndSettle();

    expect(find.text('a poll lives here'), findsOneWidget);
  });

  testWidgets('thumbnails are cached per asset and size', (tester) async {
    platform.total = 6;
    final cache = OCThumbnailCache(capacity: 4);

    await _open(tester, cache: cache);
    final firstPass = platform.thumbnailRequests.length;
    expect(firstPass, greaterThan(0));

    // Rebuilding must not re-ask for what the cache already holds.
    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();
    expect(platform.thumbnailRequests.length, firstPass);
    expect(cache.length, lessThanOrEqualTo(4));
  });

  testWidgets('a page asks for its thumbnails before the tiles are built', (
    tester,
  ) async {
    platform.total = 130;

    await _open(tester);

    // The last asset of the first page is nowhere near the viewport, so only a
    // prefetch can have asked for it — and nothing beyond that page has been
    // asked for at all.
    expect(platform.thumbnailRequests, contains(startsWith('asset-49@')));
    expect(
      platform.thumbnailRequests,
      isNot(contains(startsWith('asset-50@'))),
    );
  });

  testWidgets('the grid re-reads the library after a trip to the camera', (
    tester,
  ) async {
    platform.total = 3;

    await _open(tester);
    final beforeResume = platform.fetchedPages.length;

    // A photo taken in another app while the sheet was backgrounded.
    platform.total = 4;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(platform.fetchedPages.length, beforeResume + 1);
    expect(platform.fetchedPages.last.offset, 0);
    expect(find.byType(OCMediaTile), findsNWidgets(4));
  });

  testWidgets('an unchanged library survives a resume untouched', (
    tester,
  ) async {
    platform.total = 3;

    await _open(tester);
    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Nothing new, so the selection and the grid stay exactly as they were.
    expect(find.text('Send (1)'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the camera cell leads the grid, two rows tall', (tester) async {
    platform.total = 8;
    var cameraTaps = 0;

    await _open(
      tester,
      options: OCBrowseFilesOptions(onCameraTap: () => cameraTaps++),
    );

    final camera = find.ancestor(
      of: find.byIcon(Icons.photo_camera_outlined),
      matching: find.byType(GestureDetector),
    );
    final cameraSize = tester.getSize(camera.first);
    final tileSize = tester.getSize(find.byType(OCMediaTile).first);

    expect(cameraSize.width, closeTo(tileSize.width, 0.5));
    // Two rows of tiles plus the gap between them.
    expect(cameraSize.height, closeTo(tileSize.height * 2 + 2, 0.5));
    // It sits at the top-left, with the first asset beside it, not under it.
    expect(
      tester.getTopLeft(camera.first).dx,
      lessThan(tester.getTopLeft(find.byType(OCMediaTile).first).dx),
    );

    await tester.tap(camera.first);
    await tester.pumpAndSettle();
    expect(cameraTaps, 1);
  });

  testWidgets('no camera tile without a handler', (tester) async {
    platform.total = 4;

    await _open(tester);

    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
  });

  testWidgets('the tab row carries Telegram\'s full set when asked', (
    tester,
  ) async {
    final options = OCBrowseFilesOptions(
      tabs: <OCAttachmentTab>[
        OCAttachmentTab.gallery,
        OCAttachmentTab.file,
        OCAttachmentTab.location(builder: (context) => const Text('map')),
        OCAttachmentTab.article(
          builder: (context) => const Text('article'),
          badge: const Icon(Icons.star, size: 10),
        ),
        OCAttachmentTab.poll(builder: (context) => const Text('poll')),
        OCAttachmentTab.contact(builder: (context) => const Text('contact')),
      ],
    );

    await _open(tester, options: options);

    for (final label in [
      'Gallery',
      'File',
      'Location',
      'Article',
      'Poll',
      'Contact',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label tab');
    }
    expect(find.byIcon(Icons.star), findsOneWidget, reason: 'article badge');

    await tester.tap(find.text('Location'));
    await tester.pumpAndSettle();
    expect(find.text('map'), findsOneWidget);
  });

  testWidgets('a forced background recolours the sheet, not the app', (
    tester,
  ) async {
    platform.total = 3;
    const black = Color(0xFF111112);

    await _open(
      tester,
      options: const OCBrowseFilesOptions(
        backgroundColor: black,
        accentColor: Color(0xFF29B6A4),
      ),
    );

    // The theme in force where the sheet draws itself, whatever wraps it.
    final sheet = Theme.of(tester.element(find.byType(OCAttachmentTabBar)));
    expect(sheet.colorScheme.surface, black);
    expect(sheet.colorScheme.primary, const Color(0xFF29B6A4));
    // The screen behind the sheet keeps its own theme.
    expect(
      Theme.of(tester.element(find.text('open sheet'))).colorScheme.surface,
      isNot(black),
    );
  });

  testWidgets('custom strings replace the sheet\'s own wording', (
    tester,
  ) async {
    platform
      ..total = 12
      ..albums = <OCMediaAlbum>[
        const OCMediaAlbum(id: 'all', name: 'Tout', count: 12, isAll: true),
        const OCMediaAlbum(id: 'camera', name: 'Appareil photo', count: 4),
      ];

    await _open(
      tester,
      options: OCBrowseFilesOptions(
        strings: OCBrowseFilesStrings(
          confirmLabel: 'Envoyer',
          albumItemCount: (count) => '$count éléments',
          selectionSummary: (media, documents, max) =>
              '$media sur $max sélectionnés',
        ),
        tabs: <OCAttachmentTab>[
          OCAttachmentTab.gallery.withLabel('Galerie'),
          OCAttachmentTab.file.withLabel('Fichier'),
        ],
      ),
    );

    expect(find.text('12 éléments'), findsOneWidget);
    expect(find.text('Galerie'), findsOneWidget);
    expect(find.text('Fichier'), findsOneWidget);

    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Envoyer (1)'), findsOneWidget);
    expect(find.text('1 sur 10 sélectionnés'), findsOneWidget);
  });

  testWidgets('options.confirmLabel still wins over the strings', (
    tester,
  ) async {
    platform.total = 3;

    await _open(
      tester,
      options: const OCBrowseFilesOptions(
        confirmLabel: 'Send',
        strings: OCBrowseFilesStrings(confirmLabel: 'Envoyer'),
      ),
    );

    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Send (1)'), findsOneWidget);
  });
}

Widget _pollBody(BuildContext context) =>
    const Center(child: Text('a poll lives here'));

/// Opens the sheet over a throwaway screen and keeps hold of what it returns.
/// Drags the grid up until the library stops growing under it.
///
/// The sheet expands before it scrolls, so this is several drags rather than
/// one big fling.
Future<void> _scrollToEnd(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    // The grid itself, not a tile: a tile near the top of the list may already
    // have scrolled out of the viewport, and the drag would miss it.
    await tester.drag(find.byType(GridView), const Offset(0, -900));
    await tester.pumpAndSettle();
  }
}

Future<_Harness> _open(
  WidgetTester tester, {
  OCBrowseFilesOptions options = const OCBrowseFilesOptions(),
  OCThumbnailCache? cache,
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              harness.result = await OCBrowseFiles.show(
                context,
                options: options,
                cache: cache ?? OCThumbnailCache(capacity: 32),
              );
            },
            child: const Text('open sheet'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  OCBrowseFilesResult? result;
}

/// A platform that serves a synthetic library, so the sheet can be driven
/// without a device.
class _FakePlatform extends OCBrowseFilesFlutterPlatform {
  OCMediaPermissionStatus status = OCMediaPermissionStatus.granted;
  OCMediaPermissionStatus? grantOnRequest;
  Duration videoDuration = const Duration(minutes: 2, seconds: 5);
  int total = 0;
  List<String> documents = const <String>[];

  /// How many rows each page after the first repeats from the one before it.
  int overlap = 0;

  int requests = 0;
  int settingsOpened = 0;
  int limitedPickerShown = 0;
  final List<({int offset, int limit})> fetchedPages =
      <({int offset, int limit})>[];
  final List<String> thumbnailRequests = <String>[];

  /// The albums the top bar offers; one entry keeps the bar hidden.
  List<OCMediaAlbum>? albums;

  /// Which album each page was asked for, `null` for the whole library.
  final List<String?> fetchedAlbumIds = <String?>[];

  @override
  Future<OCMediaPermissionStatus> permissionStatus({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async => status;

  @override
  Future<OCMediaPermissionStatus> requestPermission({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async {
    requests++;
    return status = grantOnRequest ?? status;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<OCMediaPermissionStatus> presentLimitedPicker() async {
    limitedPickerShown++;
    return status;
  }

  @override
  Future<List<OCMediaAlbum>> fetchAlbums({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async =>
      albums ??
      <OCMediaAlbum>[
        OCMediaAlbum(id: 'all', name: 'All media', count: total, isAll: true),
      ];

  @override
  Future<OCMediaPage> fetchMedia({
    String? albumId,
    Set<OCMediaType> types = kAllMediaTypes,
    int offset = 0,
    int limit = 50,
  }) async {
    fetchedPages.add((offset: offset, limit: limit));
    fetchedAlbumIds.add(albumId);
    // Assets added while the grid is being paged push everything down, so a
    // later page hands back rows an earlier one already carried.
    final start = offset == 0 ? 0 : (offset - overlap).clamp(0, total);
    final end = (start + limit).clamp(0, total);
    return OCMediaPage(
      items: <OCMediaItem>[for (var i = start; i < end; i++) _itemAt(i)],
      offset: offset,
      total: total,
    );
  }

  @override
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) async {
    thumbnailRequests.add('$id@${width}x$height');
    // Null means "no thumbnail": the tile paints its placeholder, which keeps
    // these tests off real JPEG bytes.
    return null;
  }

  @override
  Future<String> resolveFile(String id) async => '/cache/$id.jpg';

  @override
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const <String>[],
    bool allowMultiple = true,
  }) async => documents;

  OCMediaItem _itemAt(int index) {
    final isVideo = index == 1;
    return OCMediaItem(
      id: 'asset-$index',
      type: isVideo ? OCMediaType.video : OCMediaType.image,
      width: 1080,
      height: 1920,
      createdAt: DateTime(2026, 1, 1).subtract(Duration(minutes: index)),
      duration: isVideo ? videoDuration : null,
    );
  }
}
