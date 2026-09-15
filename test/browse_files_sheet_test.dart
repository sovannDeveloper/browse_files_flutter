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

  testWidgets('starts on the empty-state CTA, then a pick fills the grid', (
    tester,
  ) async {
    platform.picked = <OCMediaItem>[
      _item(id: 'a', type: OCMediaType.image),
      _item(id: 'b', type: OCMediaType.image),
    ];

    await _open(tester);

    // The empty state is the Gallery tab's first face — a single CTA tile.
    expect(find.text(platform.strings.galleryEmptyActionLabel), findsOneWidget);
    expect(find.byType(OCMediaTile), findsNothing);

    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    expect(platform.picks, 1, reason: 'one tap opens the system picker');
    expect(find.byType(OCMediaTile), findsNWidgets(2));
    expect(find.text('Select (2)'), findsOneWidget);
  });

  testWidgets('a dismissed picker leaves the empty state alone', (
    tester,
  ) async {
    platform.picked = const <OCMediaItem>[];

    final harness = await _open(tester);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    expect(platform.picks, 1);
    expect(find.byType(OCMediaTile), findsNothing);
    expect(harness.result, isNull);
    // Still on the empty CTA, not stuck on a spinner.
    expect(find.text(platform.strings.galleryEmptyActionLabel), findsOneWidget);
  });

  testWidgets('Select more reopens the picker and appends', (tester) async {
    platform.picked = <OCMediaItem>[_item(id: 'a', type: OCMediaType.image)];
    platform.pickerOutcome = (_) => <OCMediaItem>[
      _item(id: 'b', type: OCMediaType.image),
    ];

    await _open(tester);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    expect(find.byType(OCMediaTile), findsOneWidget);
    expect(platform.picks, 1);

    await tester.tap(find.text(platform.strings.gallerySelectMoreLabel));
    await tester.pumpAndSettle();

    expect(platform.picks, 2);
    // The new pick is appended and re-tapping the second item removes it.
    expect(find.byType(OCMediaTile), findsNWidgets(2));
    expect(find.text('Select (2)'), findsOneWidget);
  });

  testWidgets('tapping a selected tile deselects it', (tester) async {
    platform.picked = <OCMediaItem>[
      _item(id: 'a', type: OCMediaType.image),
      _item(id: 'b', type: OCMediaType.image),
    ];

    await _open(tester);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();
    expect(find.text('Select (2)'), findsOneWidget);

    await tester.tap(find.byType(OCMediaTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Select (1)'), findsOneWidget);
  });

  testWidgets('selection stops at maxSelection', (tester) async {
    platform.picked = <OCMediaItem>[
      for (var i = 0; i < 5; i++)
        _item(id: 'asset-$i', type: OCMediaType.image),
    ];

    await _open(tester, options: const OCBrowseFilesOptions(maxSelection: 2));
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    expect(find.text('Select (2)'), findsOneWidget);
    // The third tile is dimmed and tapping it doesn't add another pick.
    await tester.tap(find.byType(OCMediaTile).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Select (2)'), findsOneWidget);
  });

  testWidgets('a single cap forces the picker into single-pick mode', (
    tester,
  ) async {
    await _open(tester, options: const OCBrowseFilesOptions(maxSelection: 1));
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    // The grid never called for more than one item.
    expect(platform.lastAllowMultiple, isFalse);
  });

  testWidgets('confirming pops the result with the picked media', (
    tester,
  ) async {
    platform.picked = <OCMediaItem>[
      _item(id: 'a', type: OCMediaType.image),
      _item(id: 'b', type: OCMediaType.image),
    ];

    final harness = await _open(tester);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select (2)'));
    await tester.pumpAndSettle();

    final result = harness.result;
    expect(result, isNotNull);
    expect(result!.media.map((i) => i.id), ['a', 'b']);
    expect(result.documents, isEmpty);
  });

  testWidgets('videos carry a duration badge', (tester) async {
    platform.picked = <OCMediaItem>[
      _item(
        id: 'v',
        type: OCMediaType.video,
        duration: const Duration(hours: 1, minutes: 32, seconds: 48),
      ),
    ];

    await _open(tester);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    expect(find.text('1:32:48'), findsOneWidget);
  });

  testWidgets('a picker error paints the empty state with a Retry button', (
    tester,
  ) async {
    var calls = 0;
    platform.pickerOutcome = (i) {
      calls++;
      if (calls == 1) {
        throw OCBrowseFilesException(
          OCBrowseFilesErrorCode.notFound,
          'the picker could not be opened',
        );
      }
      return <OCMediaItem>[_item(id: 'a', type: OCMediaType.image)];
    };

    await _open(tester);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();
    expect(find.text(platform.strings.retryLabel), findsOneWidget);

    await tester.tap(find.text(platform.strings.retryLabel));
    await tester.pumpAndSettle();
    expect(find.byType(OCMediaTile), findsOneWidget);
  });

  testWidgets('a single cap forces the document picker into single-pick mode', (
    tester,
  ) async {
    await _open(tester, options: const OCBrowseFilesOptions(maxSelection: 1));
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal Storage'));
    await tester.pumpAndSettle();

    expect(platform.lastDocumentsAllowMultiple, isFalse);
  });

  testWidgets('the File tab hands back cached document paths', (tester) async {
    platform.documents = <String>['/cache/report.pdf', '/cache/notes.txt'];

    final harness = await _open(tester);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Internal Storage'), findsOneWidget);
    await tester.tap(find.text('Internal Storage'));
    await tester.pumpAndSettle();
    // Picking the documents puts them in the sheet's selection, but the sheet
    // only pops when the user confirms — Telegram's pattern.
    expect(find.text('Select (2)'), findsOneWidget);

    await tester.tap(find.text('Select (2)'));
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
    await tester.tap(find.text('Internal Storage'));
    await tester.pumpAndSettle();

    expect(harness.result, isNull);
    // Sheet is still open, ready for the user to try again.
    expect(find.text('Internal Storage'), findsOneWidget);
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
    platform.picked = <OCMediaItem>[
      _item(id: 'a', type: OCMediaType.image),
      _item(id: 'b', type: OCMediaType.image),
    ];
    final cache = OCThumbnailCache(capacity: 4);

    await _open(tester, cache: cache);
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();
    expect(platform.thumbnailRequests.length, greaterThan(0));
    expect(cache.length, lessThanOrEqualTo(4));

    // Tapping a tile rebuilds the grid; the cache means the prefetch is not
    // re-asked for what is already there.
    final firstPass = platform.thumbnailRequests.length;
    await tester.tap(find.byType(OCMediaTile).first);
    // Pump just enough frames for the AnimatedScale / selection dot to settle,
    // rather than pumpAndSettle which loops while the picker spinner animates.
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.thumbnailRequests.length, firstPass);
  });

  testWidgets('the camera tile leads the grid when a handler is set', (
    tester,
  ) async {
    platform.picked = <OCMediaItem>[
      for (var i = 0; i < 8; i++)
        _item(id: 'asset-$i', type: OCMediaType.image),
    ];
    var cameraTaps = 0;

    await _open(
      tester,
      options: OCBrowseFilesOptions(onCameraTap: () => cameraTaps++),
    );
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    final tileSize = tester.getSize(find.byType(OCMediaTile).first);
    final cameraSize = tester.getSize(
      find
          .ancestor(
            of: find.byIcon(Icons.photo_camera_outlined),
            matching: find.byType(GestureDetector),
          )
          .first,
    );

    // The camera tile is two rows tall — Telegram's design.
    expect(cameraSize.width, closeTo(tileSize.width, 0.5));
    expect(cameraSize.height, closeTo(tileSize.height * 2 + 2, 0.5));
    // It sits to the left of the first asset, not below it.
    expect(
      tester
          .getTopLeft(
            find
                .ancestor(
                  of: find.byIcon(Icons.photo_camera_outlined),
                  matching: find.byType(GestureDetector),
                )
                .first,
          )
          .dx,
      lessThan(tester.getTopLeft(find.byType(OCMediaTile).first).dx),
    );

    await tester.tap(find.byIcon(Icons.photo_camera_outlined).first);
    await tester.pumpAndSettle();
    expect(cameraTaps, 1);
  });

  testWidgets('no camera tile when showCamera is off', (tester) async {
    platform.picked = <OCMediaItem>[_item(id: 'a', type: OCMediaType.image)];

    await _open(tester, options: const OCBrowseFilesOptions(showCamera: false));
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);

    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
  });

  testWidgets('the built-in camera shoots straight into the selection', (
    tester,
  ) async {
    platform.captured = _item(id: '/cache/shot.jpg', type: OCMediaType.image);

    // Photos only: no photo/video choice, the camera opens on the tap.
    await _open(
      tester,
      options: const OCBrowseFilesOptions(types: {OCMediaType.image}),
    );
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();

    expect(platform.captures, <OCMediaType>[OCMediaType.image]);
    expect(find.byType(OCMediaTile), findsOneWidget);
    expect(find.text('Select (1)'), findsOneWidget);
    // The camera cell now leads the grid for the next shot.
    expect(find.byIcon(Icons.photo_camera_outlined), findsWidgets);
  });

  testWidgets('with both kinds allowed the camera asks photo or video first', (
    tester,
  ) async {
    platform.captured = _item(
      id: '/cache/clip.mp4',
      type: OCMediaType.video,
      duration: const Duration(seconds: 12),
    );

    await _open(tester);
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();

    expect(platform.captures, isEmpty, reason: 'the choice comes first');
    expect(find.text(platform.strings.takePhotoLabel), findsOneWidget);
    expect(find.text(platform.strings.recordVideoLabel), findsOneWidget);

    await tester.tap(find.text(platform.strings.recordVideoLabel));
    await tester.pumpAndSettle();

    expect(platform.captures, <OCMediaType>[OCMediaType.video]);
    expect(find.byType(OCMediaTile), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
  });

  testWidgets('a camera the user backed out of changes nothing', (
    tester,
  ) async {
    platform.captured = null;

    await _open(
      tester,
      options: const OCBrowseFilesOptions(types: {OCMediaType.image}),
    );
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();

    expect(platform.captures, hasLength(1));
    expect(find.byType(OCMediaTile), findsNothing);
    expect(find.text(platform.strings.galleryEmptyActionLabel), findsOneWidget);
  });

  testWidgets('the camera asks for permission before it opens', (tester) async {
    platform.captured = _item(id: '/cache/shot.jpg', type: OCMediaType.image);

    await _open(
      tester,
      options: const OCBrowseFilesOptions(types: {OCMediaType.image}),
    );
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();

    expect(platform.permissionRequests, <OCMediaType>[OCMediaType.image]);
    expect(platform.captures, <OCMediaType>[OCMediaType.image]);
  });

  testWidgets('a refused camera never opens and says why', (tester) async {
    platform.cameraPermission = OCCameraPermission.permanentlyDenied;
    platform.captured = _item(id: '/cache/shot.jpg', type: OCMediaType.image);

    await _open(
      tester,
      options: const OCBrowseFilesOptions(types: {OCMediaType.video}),
    );
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();

    expect(platform.permissionRequests, <OCMediaType>[OCMediaType.video]);
    expect(platform.captures, isEmpty);
    expect(find.byType(OCMediaTile), findsNothing);
    expect(find.text(platform.strings.cameraErrorTitle), findsOneWidget);
    expect(find.text(platform.strings.cameraPermissionDenied), findsOneWidget);
  });

  testWidgets('onCameraTap still overrides the built-in camera', (
    tester,
  ) async {
    var cameraTaps = 0;

    await _open(
      tester,
      options: OCBrowseFilesOptions(onCameraTap: () => cameraTaps++),
    );
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();

    expect(cameraTaps, 1);
    expect(platform.captures, isEmpty);
  });

  group('showActions', () {
    testWidgets('lists the four rows and runs the one tapped', (tester) async {
      platform.picked = <OCMediaItem>[
        _item(id: 'a', type: OCMediaType.image),
        _item(id: 'b', type: OCMediaType.video),
      ];

      final harness = await _openActions(tester);
      for (final label in <String>[
        platform.strings.takePhotoLabel,
        platform.strings.recordVideoLabel,
        platform.strings.selectMediaLabel,
        platform.strings.selectFilesLabel,
      ]) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text(platform.strings.selectMediaLabel));
      await tester.pumpAndSettle();

      // The menu is gone by the time the picker answers.
      expect(find.text(platform.strings.selectMediaLabel), findsNothing);
      expect(platform.picks, 1);
      expect(harness.result?.media.map((item) => item.id), ['a', 'b']);
    });

    testWidgets('the camera rows capture one item', (tester) async {
      platform.captured = _item(id: '/cache/shot.jpg', type: OCMediaType.image);

      final harness = await _openActions(tester);
      await tester.tap(find.text(platform.strings.takePhotoLabel));
      await tester.pumpAndSettle();

      expect(platform.captures, <OCMediaType>[OCMediaType.image]);
      expect(harness.result?.media.single.id, '/cache/shot.jpg');
    });

    testWidgets('the camera rows ask for permission first', (tester) async {
      platform.captured = _item(id: '/cache/clip.mp4', type: OCMediaType.video);

      await _openActions(tester);
      await tester.tap(find.text(platform.strings.recordVideoLabel));
      await tester.pumpAndSettle();

      expect(platform.permissionRequests, <OCMediaType>[OCMediaType.video]);
      expect(platform.captures, <OCMediaType>[OCMediaType.video]);
    });

    testWidgets('a refused camera throws permissionDenied', (tester) async {
      platform.cameraPermission = OCCameraPermission.denied;
      platform.captured = _item(id: '/cache/shot.jpg', type: OCMediaType.image);

      final harness = await _openActions(tester);
      await tester.tap(find.text(platform.strings.takePhotoLabel));
      await tester.pumpAndSettle();

      expect(platform.captures, isEmpty);
      expect(harness.result, isNull);
      expect(
        harness.error,
        isA<OCBrowseFilesException>()
            .having(
              (error) => error.code,
              'code',
              OCBrowseFilesErrorCode.permissionDenied,
            )
            .having(
              (error) => error.message,
              'message',
              platform.strings.cameraPermissionDenied,
            ),
      );
    });

    testWidgets('the files row returns cached paths', (tester) async {
      platform.documents = const <String>['/cache/a.pdf'];

      final harness = await _openActions(tester);
      await tester.tap(find.text(platform.strings.selectFilesLabel));
      await tester.pumpAndSettle();

      expect(harness.result?.documents, const <String>['/cache/a.pdf']);
    });

    testWidgets('backing out of the camera is empty, dismissing is null', (
      tester,
    ) async {
      platform.captured = null;

      var harness = await _openActions(tester);
      await tester.tap(find.text(platform.strings.takePhotoLabel));
      await tester.pumpAndSettle();
      expect(harness.result, OCBrowseFilesResult.empty);

      harness = await _openActions(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(harness.result, isNull);
    });

    testWidgets('the camera rows follow the allowed types', (tester) async {
      await _openActions(
        tester,
        options: const OCBrowseFilesOptions(types: {OCMediaType.video}),
      );

      expect(find.text(platform.strings.takePhotoLabel), findsNothing);
      expect(find.text(platform.strings.recordVideoLabel), findsOneWidget);
    });

    testWidgets('the gallery row respects maxSelection', (tester) async {
      platform.picked = <OCMediaItem>[
        for (var i = 0; i < 5; i++)
          _item(id: 'asset-$i', type: OCMediaType.image),
      ];

      final harness = await _openActions(
        tester,
        options: const OCBrowseFilesOptions(maxSelection: 2),
      );
      await tester.tap(find.text(platform.strings.selectMediaLabel));
      await tester.pumpAndSettle();

      expect(platform.lastAllowMultiple, isTrue);
      expect(harness.result?.media, hasLength(2));
    });
  });

  testWidgets('the tab row carries the full Telegram set when asked', (
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
    const black = Color(0xFF111112);

    await _open(
      tester,
      options: const OCBrowseFilesOptions(
        backgroundColor: black,
        accentColor: Color(0xFF29B6A4),
      ),
    );

    // The theme in force where the sheet draws itself, whatever wraps it.
    // Find the bar before any pick — once an item is chosen the bar gives way
    // to the confirm row.
    expect(find.byType(OCAttachmentTabBar), findsOneWidget);
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
    platform.picked = <OCMediaItem>[_item(id: 'a', type: OCMediaType.image)];

    await _open(
      tester,
      options: OCBrowseFilesOptions(
        strings: OCBrowseFilesStrings(
          confirmLabel: 'Envoyer',
          galleryEmptyActionLabel: 'Choisir',
        ),
      ),
    );

    expect(find.text('Choisir'), findsOneWidget);
    await tester.tap(find.text('Choisir'));
    await tester.pumpAndSettle();

    expect(find.text('Envoyer (1)'), findsOneWidget);
  });

  testWidgets('options.confirmLabel still wins over the strings', (
    tester,
  ) async {
    platform.picked = <OCMediaItem>[_item(id: 'a', type: OCMediaType.image)];

    await _open(
      tester,
      options: const OCBrowseFilesOptions(
        confirmLabel: 'Send',
        strings: OCBrowseFilesStrings(confirmLabel: 'Envoyer'),
      ),
    );
    await tester.tap(find.text(platform.strings.galleryEmptyActionLabel));
    await tester.pumpAndSettle();

    expect(find.text('Send (1)'), findsOneWidget);
  });
}

Widget _pollBody(BuildContext context) =>
    const Center(child: Text('a poll lives here'));

OCMediaItem _item({
  required String id,
  required OCMediaType type,
  Duration? duration,
}) => OCMediaItem(
  id: id,
  type: type,
  width: 1080,
  height: 1920,
  createdAt: DateTime(2026, 1, 1),
  duration: duration,
);

Future<_Harness> _open(
  WidgetTester tester, {
  OCBrowseFilesOptions options = const OCBrowseFilesOptions(),
  OCThumbnailCache? cache,
}) async {
  final harness = _Harness();
  _usePhoneViewport(tester);
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

Future<_Harness> _openActions(
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
              try {
                harness.result = await OCBrowseFiles.showActions(
                  context,
                  options: options,
                );
              } on OCBrowseFilesException catch (error) {
                harness.error = error;
              }
            },
            child: const Text('open menu'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open menu'));
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  OCBrowseFilesResult? result;
  OCBrowseFilesException? error;
}

/// A phone-shaped window: the default 800x600 makes each of three columns
/// ~265px tall, so a sheet at peek height shows barely one row.
void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A platform that serves the items [picked] tells it to, so the sheet can
/// be driven without a device.
class _FakePlatform extends OCBrowseFilesFlutterPlatform {
  /// The library the picker returns.
  List<OCMediaItem> picked = <OCMediaItem>[];

  /// The documents the Files picker returns; defaults to none.
  List<String> documents = const <String>[];

  /// Hook to override the pick result per call (mostly for error flows).
  List<OCMediaItem> Function(int call) pickerOutcome = (i) => <OCMediaItem>[];

  OCBrowseFilesStrings get strings => const OCBrowseFilesStrings();

  int picks = 0;
  bool? lastAllowMultiple;
  bool? lastDocumentsAllowMultiple;
  Set<OCMediaType>? lastTypes;

  /// What the camera hands back; `null` is the user backing out.
  OCMediaItem? captured;

  /// The kinds the camera was opened for, in order.
  final List<OCMediaType> captures = <OCMediaType>[];

  /// What the camera permission prompt answers.
  OCCameraPermission cameraPermission = OCCameraPermission.granted;

  /// The kinds the camera permission was asked for, in order.
  final List<OCMediaType> permissionRequests = <OCMediaType>[];

  final List<String> thumbnailRequests = <String>[];

  @override
  Future<List<OCMediaItem>> pickMedia({
    Set<OCMediaType> types = kAllMediaTypes,
    bool allowMultiple = true,
  }) async {
    picks++;
    lastAllowMultiple = allowMultiple;
    lastTypes = types;
    if (picks == 1 && picked.isNotEmpty) return picked;
    return pickerOutcome(picks);
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
  }) async {
    lastDocumentsAllowMultiple = allowMultiple;
    return documents;
  }

  @override
  Future<OCMediaItem?> captureMedia({
    OCMediaType type = OCMediaType.image,
  }) async {
    captures.add(type);
    return captured;
  }

  @override
  Future<OCCameraPermission> requestCameraPermission({
    OCMediaType type = OCMediaType.image,
  }) async {
    permissionRequests.add(type);
    return cameraPermission;
  }
}
