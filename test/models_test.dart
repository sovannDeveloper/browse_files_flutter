import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaType', () {
    test('reads the wire names', () {
      expect(MediaType.fromName('image'), MediaType.image);
      expect(MediaType.fromName('video'), MediaType.video);
    });

    test('rejects anything else', () {
      expect(() => MediaType.fromName('audio'), throwsArgumentError);
      expect(() => MediaType.fromName(null), throwsArgumentError);
    });
  });

  group('MediaItem', () {
    test('parses a video, duration included', () {
      final item = MediaItem.fromMap(const {
        'id': '42',
        'type': 'video',
        'width': 1920,
        'height': 1080,
        'createdAtMs': 1700000000000,
        'durationMs': 5567000,
        'mimeType': 'video/mp4',
        'name': 'clip.mp4',
        'sizeBytes': 1024,
      });

      expect(item.id, '42');
      expect(item.isVideo, isTrue);
      expect(item.duration, const Duration(milliseconds: 5567000));
      expect(item.aspectRatio, closeTo(16 / 9, 0.001));
      expect(
        item.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('an image has no duration, and survives a map round trip', () {
      final item = MediaItem.fromMap(const {
        'id': '7',
        'type': 'image',
        'width': 100,
        'height': 200,
        'createdAtMs': 0,
      });

      expect(item.duration, isNull);
      expect(item.isVideo, isFalse);
      expect(MediaItem.fromMap(item.toMap()), item);
    });

    test('falls back to a square ratio when dimensions are missing', () {
      final item = MediaItem.fromMap(const {
        'id': '7',
        'type': 'image',
        'createdAtMs': 0,
      });

      expect(item.aspectRatio, 1);
    });
  });

  group('MediaPage', () {
    test('knows whether another page follows', () {
      final page = MediaPage.fromMap(const {
        'items': [
          {'id': '1', 'type': 'image', 'createdAtMs': 0},
          {'id': '2', 'type': 'image', 'createdAtMs': 0},
        ],
        'offset': 0,
        'total': 5,
      });

      expect(page.items, hasLength(2));
      expect(page.hasMore, isTrue);
      expect(
        MediaPage.fromMap(const {'items': [], 'offset': 5, 'total': 5}).hasMore,
        isFalse,
      );
      expect(MediaPage.empty.hasMore, isFalse);
    });
  });

  group('MediaAlbum', () {
    test('parses the channel representation', () {
      final album = MediaAlbum.fromMap(const {
        'id': 'all',
        'name': 'All media',
        'count': 12,
        'isAll': true,
      });

      expect(album.name, 'All media');
      expect(album.count, 12);
      expect(album.isAll, isTrue);
      expect(album.coverId, isNull);
    });
  });

  group('MediaPermissionStatus', () {
    test('limited can browse and does not need settings', () {
      expect(MediaPermissionStatus.limited.canBrowse, isTrue);
      expect(MediaPermissionStatus.limited.needsSettings, isFalse);
      expect(MediaPermissionStatus.granted.canBrowse, isTrue);
      expect(MediaPermissionStatus.denied.canBrowse, isFalse);
      expect(MediaPermissionStatus.permanentlyDenied.needsSettings, isTrue);
      expect(MediaPermissionStatus.restricted.needsSettings, isTrue);
    });

    test('an unrecognised name reads as denied', () {
      expect(
        MediaPermissionStatus.fromName('limited'),
        MediaPermissionStatus.limited,
      );
      expect(
        MediaPermissionStatus.fromName('who knows'),
        MediaPermissionStatus.denied,
      );
    });
  });

  group('BrowseFilesException', () {
    test('marks cancellation apart from failure', () {
      const canceled = BrowseFilesException(
        BrowseFilesErrorCode.userCanceled,
        'dismissed',
      );
      const failed = BrowseFilesException(
        BrowseFilesErrorCode.ioError,
        'broken',
      );

      expect(canceled.isCancellation, isTrue);
      expect(failed.isCancellation, isFalse);
      expect(
        BrowseFilesErrorCode.fromName('nope'),
        BrowseFilesErrorCode.unknown,
      );
    });
  });
}
