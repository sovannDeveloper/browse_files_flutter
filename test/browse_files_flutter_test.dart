import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records what the facade forwarded, and answers with canned values.
class FakeBrowseFilesPlatform
    with MockPlatformInterfaceMixin
    implements OCBrowseFilesFlutterPlatform {
  final calls = <String, Object?>{};

  @override
  Future<OCMediaPermissionStatus> permissionStatus({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async {
    calls['permissionStatus'] = types;
    return OCMediaPermissionStatus.limited;
  }

  @override
  Future<OCMediaPermissionStatus> requestPermission({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async {
    calls['requestPermission'] = types;
    return OCMediaPermissionStatus.granted;
  }

  @override
  Future<bool> openSettings() async {
    calls['openSettings'] = true;
    return true;
  }

  @override
  Future<OCMediaPermissionStatus> presentLimitedPicker() async {
    calls['presentLimitedPicker'] = true;
    return OCMediaPermissionStatus.limited;
  }

  @override
  Future<List<OCMediaAlbum>> fetchAlbums({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async {
    calls['fetchAlbums'] = types;
    return const [OCMediaAlbum(id: 'all', name: 'All', count: 1, isAll: true)];
  }

  @override
  Future<OCMediaPage> fetchMedia({
    String? albumId,
    Set<OCMediaType> types = kAllMediaTypes,
    int offset = 0,
    int limit = 50,
  }) async {
    calls['fetchMedia'] = {
      'albumId': albumId,
      'types': types,
      'offset': offset,
      'limit': limit,
    };
    return OCMediaPage.empty;
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
  Future<OCDocumentPage> fetchDocuments({
    List<String> mimeTypes = const [],
    int offset = 0,
    int limit = 50,
  }) async {
    calls['fetchDocuments'] = {
      'mimeTypes': mimeTypes,
      'offset': offset,
      'limit': limit,
    };
    return const OCDocumentPage(
      items: [OCDocumentItem(id: '7', name: 'notes.pdf')],
      offset: 0,
      total: 1,
    );
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

      expect(await plugin.permissionStatus(), OCMediaPermissionStatus.limited);
      expect(await plugin.requestPermission(), OCMediaPermissionStatus.granted);
      expect(await plugin.openSettings(), isTrue);
      expect(
        await plugin.presentLimitedPicker(),
        OCMediaPermissionStatus.limited,
      );
      expect(await plugin.fetchAlbums(), hasLength(1));
      expect(await plugin.fetchMedia(), OCMediaPage.empty);
      expect(
        await plugin.loadThumbnail('1', width: 10, height: 10),
        Uint8List.fromList(const [1, 2, 3]),
      );
      expect(await plugin.resolveFile('1'), '/cache/1.jpg');
      expect(await plugin.pickDocuments(), const ['/cache/doc.pdf']);
    });

    test('passes its arguments through unchanged', () async {
      await OCBrowseFilesFlutter.instance.fetchMedia(
        albumId: 'camera',
        types: const {OCMediaType.video},
        offset: 60,
        limit: 30,
      );

      expect(platform.calls['fetchMedia'], {
        'albumId': 'camera',
        'types': const {OCMediaType.video},
        'offset': 60,
        'limit': 30,
      });
    });

    test('forwards fetchDocuments with its paging', () async {
      final platform = FakeBrowseFilesPlatform();
      OCBrowseFilesFlutterPlatform.instance = platform;

      final page = await OCBrowseFilesFlutter.instance.fetchDocuments(
        mimeTypes: const ['application/pdf'],
        offset: 20,
        limit: 10,
      );

      expect(platform.calls['fetchDocuments'], {
        'mimeTypes': ['application/pdf'],
        'offset': 20,
        'limit': 10,
      });
      expect(page.items.single.name, 'notes.pdf');
    });

    test('defaults to both media types', () async {
      await OCBrowseFilesFlutter.instance.fetchAlbums();

      expect(platform.calls['fetchAlbums'], kAllMediaTypes);
    });
  });
}
