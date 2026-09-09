import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaType', () {
    test('reads the wire names', () {
      expect(OCMediaType.fromName('image'), OCMediaType.image);
      expect(OCMediaType.fromName('video'), OCMediaType.video);
    });

    test('rejects anything else', () {
      expect(() => OCMediaType.fromName('audio'), throwsArgumentError);
      expect(() => OCMediaType.fromName(null), throwsArgumentError);
    });
  });

  group('MediaItem', () {
    test('parses a video, duration included', () {
      final item = OCMediaItem.fromMap(const {
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
      final item = OCMediaItem.fromMap(const {
        'id': '7',
        'type': 'image',
        'width': 100,
        'height': 200,
        'createdAtMs': 0,
      });

      expect(item.duration, isNull);
      expect(item.isVideo, isFalse);
      expect(OCMediaItem.fromMap(item.toMap()), item);
    });

    test('falls back to a square ratio when dimensions are missing', () {
      final item = OCMediaItem.fromMap(const {
        'id': '7',
        'type': 'image',
        'createdAtMs': 0,
      });

      expect(item.aspectRatio, 1);
    });
  });

  group('MediaPage', () {
    test('knows whether another page follows', () {
      final page = OCMediaPage.fromMap(const {
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
        OCMediaPage.fromMap(const {
          'items': [],
          'offset': 5,
          'total': 5,
        }).hasMore,
        isFalse,
      );
      expect(OCMediaPage.empty.hasMore, isFalse);
    });
  });

  group('MediaAlbum', () {
    test('parses the channel representation', () {
      final album = OCMediaAlbum.fromMap(const {
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
      expect(OCMediaPermissionStatus.limited.canBrowse, isTrue);
      expect(OCMediaPermissionStatus.limited.needsSettings, isFalse);
      expect(OCMediaPermissionStatus.granted.canBrowse, isTrue);
      expect(OCMediaPermissionStatus.denied.canBrowse, isFalse);
      expect(OCMediaPermissionStatus.permanentlyDenied.needsSettings, isTrue);
      expect(OCMediaPermissionStatus.restricted.needsSettings, isTrue);
    });

    test('an unrecognised name reads as denied', () {
      expect(
        OCMediaPermissionStatus.fromName('limited'),
        OCMediaPermissionStatus.limited,
      );
      expect(
        OCMediaPermissionStatus.fromName('who knows'),
        OCMediaPermissionStatus.denied,
      );
    });
  });

  group('BrowseFilesException', () {
    test('marks cancellation apart from failure', () {
      const canceled = OCBrowseFilesException(
        OCBrowseFilesErrorCode.userCanceled,
        'dismissed',
      );
      const failed = OCBrowseFilesException(
        OCBrowseFilesErrorCode.ioError,
        'broken',
      );

      expect(canceled.isCancellation, isTrue);
      expect(failed.isCancellation, isFalse);
      expect(
        OCBrowseFilesErrorCode.fromName('nope'),
        OCBrowseFilesErrorCode.unknown,
      );
    });
  });

  group('BrowseFilesStrings', () {
    test('leaves the strings it was not given alone', () {
      const defaults = OCBrowseFilesStrings();
      final translated = defaults.copyWith(confirmLabel: 'Envoyer');

      expect(translated.confirmLabel, 'Envoyer');
      expect(translated.retryLabel, defaults.retryLabel);
      expect(translated.confirmButton('Envoyer', 3), 'Envoyer (3)');
      expect(defaults.albumItemCount(1), '1 item');
      expect(defaults.albumItemCount(12), '12 items');
      expect(defaults.selectionSummary(2, 1, 10), '2 media · 1 files (max 10)');
    });

    test('options.confirmLabel overrides the one in the strings', () {
      const options = OCBrowseFilesOptions(
        confirmLabel: 'Send',
        strings: OCBrowseFilesStrings(confirmLabel: 'Envoyer'),
      );

      expect(options.text.confirmLabel, 'Send');
      expect(options.strings.confirmLabel, 'Envoyer', reason: 'left as given');
      expect(const OCBrowseFilesOptions().text.confirmLabel, 'Select');
    });
  });

  group('AttachmentTab', () {
    test('a relabelled tab keeps its id, icon and body', () {
      final renamed = OCAttachmentTab.gallery.withLabel('Galerie');

      expect(renamed.label, 'Galerie');
      expect(renamed.id, OCAttachmentTab.galleryId);
      expect(renamed.icon, OCAttachmentTab.gallery.icon);
      expect(renamed.isBuiltIn, isTrue, reason: 'still ours to draw');
      expect(renamed, OCAttachmentTab.gallery, reason: 'identified by id');

      final custom = OCAttachmentTab.poll(
        builder: (context) => const SizedBox.shrink(),
      ).withLabel('Sondage');
      expect(custom.label, 'Sondage');
      expect(custom.isBuiltIn, isFalse, reason: 'body still the host app\'s');
    });
  });
}
