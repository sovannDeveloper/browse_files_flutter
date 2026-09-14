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

  test('pickMedia sends the type filter and decodes the answer', () async {
    answerWith(
      (_) async => <Map<Object?, Object?>>[
        {
          'id': 'content://media/picker/0/1',
          'type': 'image',
          'width': 1080,
          'height': 1920,
          'createdAtMs': 1700000000000,
        },
        {
          'id': 'content://media/picker/0/2',
          'type': 'video',
          'width': 1920,
          'height': 1080,
          'createdAtMs': 1700000001000,
          'durationMs': 5567000,
        },
      ],
    );

    final items = await platform.pickMedia(
      types: const {OCMediaType.image},
      allowMultiple: false,
    );

    expect(items, hasLength(2));
    expect(items.first.id, 'content://media/picker/0/1');
    expect(items.last.isVideo, isTrue);
    expect(items.last.duration, const Duration(milliseconds: 5567000));
    expect(calls.single.method, 'pickMedia');
    expect(calls.single.arguments, {
      'types': ['image'],
      'allowMultiple': false,
    });
  });

  test('pickMedia defaults to both media types and multi-select', () async {
    answerWith((_) async => <Object?>[]);

    await platform.pickMedia();

    expect(calls.single.arguments, {
      'types': ['image', 'video'],
      'allowMultiple': true,
    });
  });

  test('pickMedia with no types is rejected before reaching the channel', () {
    expect(
      () => platform.pickMedia(types: const <OCMediaType>{}),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('pickMedia returns an empty list when nothing was chosen', () async {
    answerWith((_) async => null);

    expect(await platform.pickMedia(), isEmpty);
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

  test('loadThumbnail bad dimensions are rejected before the channel', () {
    expect(
      () => platform.loadThumbnail('1', width: 0, height: 10),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
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
      platform.pickMedia(),
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
      platform.pickMedia(),
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
    expect(
      platform.pickMedia(),
      throwsA(
        isA<OCBrowseFilesException>().having(
          (error) => error.code,
          'code',
          OCBrowseFilesErrorCode.unimplemented,
        ),
      ),
    );
  });

  test('captureMedia sends the kind and decodes the capture', () async {
    answerWith(
      (_) async => <Object?, Object?>{
        'id': 'file:///cache/browse_files/capture_1.mp4',
        'type': 'video',
        'width': 1920,
        'height': 1080,
        'createdAtMs': 1700000002000,
        'durationMs': 4000,
        'mimeType': 'video/mp4',
      },
    );

    final item = await platform.captureMedia(type: OCMediaType.video);

    expect(item?.isVideo, isTrue);
    expect(item?.duration, const Duration(seconds: 4));
    expect(calls.single.method, 'captureMedia');
    expect(calls.single.arguments, {'type': 'video'});
  });

  test('captureMedia defaults to a photo and null means backed out', () async {
    answerWith((_) async => null);

    expect(await platform.captureMedia(), isNull);
    expect(calls.single.arguments, {'type': 'image'});
  });

  test('captureMedia wraps platform errors', () async {
    answerWith(
      (_) async => throw PlatformException(
        code: 'unsupported',
        message: 'This device has no camera.',
      ),
    );

    expect(
      () => platform.captureMedia(),
      throwsA(
        isA<OCBrowseFilesException>().having(
          (error) => error.code,
          'code',
          OCBrowseFilesErrorCode.unsupported,
        ),
      ),
    );
  });
}
