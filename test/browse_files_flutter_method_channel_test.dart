import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = OCMethodChannelBrowseFilesFlutter();
  const channel = MethodChannel('com.kedtec.browse_files_flutter/methods');
  final calls = <MethodCall>[];

  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'permissionStatus sends the type filter and decodes the answer',
    () async {
      answerWith((_) async => 'limited');

      expect(
        await platform.permissionStatus(types: const {OCMediaType.image}),
        OCMediaPermissionStatus.limited,
      );
      expect(calls.single.method, 'permissionStatus');
      expect(calls.single.arguments, {
        'types': ['image'],
      });
    },
  );

  test('fetchMedia decodes a page', () async {
    answerWith(
      (_) async => {
        'items': [
          {
            'id': '1',
            'type': 'video',
            'width': 4,
            'height': 3,
            'createdAtMs': 10,
            'durationMs': 1000,
          },
        ],
        'offset': 0,
        'total': 3,
      },
    );

    final page = await platform.fetchMedia(albumId: 'camera', limit: 1);

    expect(page.items.single.id, '1');
    expect(page.items.single.duration, const Duration(seconds: 1));
    expect(page.hasMore, isTrue);
    expect(calls.single.arguments['albumId'], 'camera');
    expect(calls.single.arguments['limit'], 1);
  });

  test('fetchAlbums decodes a list', () async {
    answerWith(
      (_) async => [
        {'id': 'all', 'name': 'All media', 'count': 3, 'isAll': true},
        {'id': 'cam', 'name': 'Camera', 'count': 2},
      ],
    );

    final albums = await platform.fetchAlbums();

    expect(albums.map((album) => album.id), ['all', 'cam']);
    expect(albums.first.isAll, isTrue);
  });

  test('pickDocuments returns an empty list when nothing was chosen', () async {
    answerWith((_) async => null);

    expect(await platform.pickDocuments(), isEmpty);
  });

  test('resolveFile without a path is a notFound failure', () async {
    answerWith((_) async => null);

    expect(
      platform.resolveFile('1'),
      throwsA(
        isA<OCBrowseFilesException>().having(
          (error) => error.code,
          'code',
          OCBrowseFilesErrorCode.notFound,
        ),
      ),
    );
  });

  test('a platform error keeps its code', () async {
    answerWith(
      (_) async => throw PlatformException(
        code: 'permissionDenied',
        message: 'no access',
        details: 'limited',
      ),
    );

    expect(
      platform.fetchAlbums(),
      throwsA(
        isA<OCBrowseFilesException>()
            .having(
              (e) => e.code,
              'code',
              OCBrowseFilesErrorCode.permissionDenied,
            )
            .having((e) => e.message, 'message', 'no access')
            .having((e) => e.details, 'details', 'limited'),
      ),
    );
  });

  test('an unknown platform code degrades to unknown', () async {
    answerWith((_) async => throw PlatformException(code: 'weird'));

    expect(
      platform.openSettings(),
      throwsA(
        isA<OCBrowseFilesException>().having(
          (error) => error.code,
          'code',
          OCBrowseFilesErrorCode.unknown,
        ),
      ),
    );
  });

  test('a missing native implementation surfaces as unimplemented', () async {
    // No mock handler registered: the channel reports the method as missing,
    // which is exactly what the stub native side does today.
    expect(
      platform.permissionStatus(),
      throwsA(
        isA<OCBrowseFilesException>().having(
          (error) => error.code,
          'code',
          OCBrowseFilesErrorCode.unimplemented,
        ),
      ),
    );
  });

  test('bad paging arguments are rejected before reaching the channel', () {
    expect(() => platform.fetchMedia(limit: 0), throwsArgumentError);
    expect(() => platform.fetchMedia(offset: -1), throwsArgumentError);
    expect(
      () => platform.loadThumbnail('1', width: 0, height: 10),
      throwsArgumentError,
    );
    expect(() => platform.fetchAlbums(types: const {}), throwsArgumentError);
    expect(calls, isEmpty);
  });
}
