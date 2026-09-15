import 'dart:typed_data';

import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records what the facade forwarded, and answers with canned values.
class FakeBrowseFilesPlatform
    with MockPlatformInterfaceMixin
    implements OCBrowseFilesFlutterPlatform {
  final calls = <String, Object?>{};

  /// The items `pickMedia` returns; defaults to two images.
  List<OCMediaItem> picked = <OCMediaItem>[
    OCMediaItem(
      id: 'content://media/picker/0/1',
      type: OCMediaType.image,
      width: 1080,
      height: 1920,
      createdAt: DateTime(2026, 1, 1),
    ),
    OCMediaItem(
      id: 'content://media/picker/0/2',
      type: OCMediaType.image,
      width: 1080,
      height: 1920,
      createdAt: DateTime(2026, 1, 2),
    ),
  ];

  @override
  Future<List<OCMediaItem>> pickMedia({
    Set<OCMediaType> types = kAllMediaTypes,
    bool allowMultiple = true,
  }) async {
    calls['pickMedia'] = {'types': types, 'allowMultiple': allowMultiple};
    return picked;
  }

  @override
  Future<Uint8List?> loadThumbnail(
    String id, {
    required int width,
    required int height,
    int quality = 80,
  }) async {
    calls['loadThumbnail'] = {
      'id': id,
      'width': width,
      'height': height,
      'quality': quality,
    };
    return Uint8List.fromList(const [1, 2, 3]);
  }

  @override
  Future<String> resolveFile(String id) async {
    calls['resolveFile'] = id;
    return '/cache/$id.jpg';
  }

  @override
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) async {
    calls['pickDocuments'] = {
      'mimeTypes': mimeTypes,
      'allowMultiple': allowMultiple,
    };
    return const ['/cache/doc.pdf'];
  }

  @override
  Future<OCMediaItem?> captureMedia({
    OCMediaType type = OCMediaType.image,
  }) async {
    calls['captureMedia'] = type;
    return OCMediaItem(
      id: '/cache/capture.${type == OCMediaType.video ? 'mp4' : 'jpg'}',
      type: type,
      width: 1080,
      height: 1920,
      createdAt: DateTime(2026, 1, 3),
    );
  }

  @override
  Future<OCCameraPermission> requestCameraPermission({
    OCMediaType type = OCMediaType.image,
  }) async {
    calls['requestCameraPermission'] = type;
    return OCCameraPermission.granted;
  }
}

void main() {
  test('$OCMethodChannelBrowseFilesFlutter is the default instance', () {
    expect(
      OCBrowseFilesFlutterPlatform.instance,
      isInstanceOf<OCMethodChannelBrowseFilesFlutter>(),
    );
  });

  group('facade', () {
    late FakeBrowseFilesPlatform platform;

    setUp(() {
      platform = FakeBrowseFilesPlatform();
      OCBrowseFilesFlutterPlatform.instance = platform;
    });

    test('forwards every call to the platform', () async {
      final plugin = OCBrowseFilesFlutter.instance;

      expect(await plugin.pickMedia(), hasLength(2));
      expect(
        await plugin.loadThumbnail('1', width: 10, height: 10),
        Uint8List.fromList(const [1, 2, 3]),
      );
      expect(await plugin.resolveFile('1'), '/cache/1.jpg');
      expect(await plugin.pickDocuments(), const ['/cache/doc.pdf']);
      expect((await plugin.captureMedia())?.id, '/cache/capture.jpg');
    });

    test('passes the capture kind through and defaults to a photo', () async {
      final plugin = OCBrowseFilesFlutter.instance;

      final video = await plugin.captureMedia(type: OCMediaType.video);
      expect(platform.calls['captureMedia'], OCMediaType.video);
      expect(video?.isVideo, isTrue);

      await plugin.captureMedia();
      expect(platform.calls['captureMedia'], OCMediaType.image);
    });

    test('requestCameraPermission passes the kind through', () async {
      final plugin = OCBrowseFilesFlutter.instance;

      expect(
        await plugin.requestCameraPermission(type: OCMediaType.video),
        OCCameraPermission.granted,
      );
      expect(platform.calls['requestCameraPermission'], OCMediaType.video);

      await plugin.requestCameraPermission();
      expect(platform.calls['requestCameraPermission'], OCMediaType.image);
    });

    test('passes pickMedia arguments through unchanged', () async {
      await OCBrowseFilesFlutter.instance.pickMedia(
        types: const {OCMediaType.video},
        allowMultiple: false,
      );

      expect(platform.calls['pickMedia'], {
        'types': const {OCMediaType.video},
        'allowMultiple': false,
      });
    });

    test('passes pickDocuments arguments through unchanged', () async {
      await OCBrowseFilesFlutter.instance.pickDocuments(
        mimeTypes: const ['application/pdf'],
        allowMultiple: false,
      );

      expect(platform.calls['pickDocuments'], {
        'mimeTypes': ['application/pdf'],
        'allowMultiple': false,
      });
    });

    test('defaults to both media types and multi-select', () async {
      await OCBrowseFilesFlutter.instance.pickMedia();

      expect(platform.calls['pickMedia'], {
        'types': kAllMediaTypes,
        'allowMultiple': true,
      });
    });

    test('a dismissed picker comes back empty', () async {
      platform.picked = const <OCMediaItem>[];

      expect(await OCBrowseFilesFlutter.instance.pickMedia(), isEmpty);
    });
  });
}
