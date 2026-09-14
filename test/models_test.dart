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
        'id': 'content://media/picker/0/42',
        'type': 'video',
        'width': 1920,
        'height': 1080,
        'createdAtMs': 1700000000000,
        'durationMs': 5567000,
        'mimeType': 'video/mp4',
        'name': 'clip.mp4',
        'sizeBytes': 1024,
      });

      expect(item.id, 'content://media/picker/0/42');
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
        'id': 'content://media/picker/0/7',
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
        'id': 'content://media/picker/0/7',
        'type': 'image',
        'createdAtMs': 0,
      });

      expect(item.aspectRatio, 1);
    });
  });

  group('DocumentItem', () {
    test('parses the channel representation', () {
      final item = OCDocumentItem.fromMap(const {
        'id': '7',
        'name': 'notes.pdf',
        'mimeType': 'application/pdf',
        'sizeBytes': 512,
      });

      expect(item.id, '7');
      expect(item.name, 'notes.pdf');
      expect(item.mimeType, 'application/pdf');
      expect(item.sizeBytes, 512);
    });

    test('a path produces a fully-resolved item', () {
      final item = OCDocumentItem.fromPath('/cache/notes.pdf', sizeBytes: 9);

      expect(item.id, '/cache/notes.pdf');
      expect(item.name, 'notes.pdf');
      expect(item.path, '/cache/notes.pdf');
      expect(item.isResolved, isTrue);
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

  group('BrowseFilesResult', () {
    test('isEmpty is true when nothing was picked', () {
      const result = OCBrowseFilesResult();

      expect(result.isEmpty, isTrue);
      expect(result.isNotEmpty, isFalse);
      expect(result.length, 0);
    });

    test('isEmpty is false once media or documents are present', () {
      final result = OCBrowseFilesResult(
        media: <OCMediaItem>[
          OCMediaItem(
            id: 'a',
            type: OCMediaType.image,
            width: 1,
            height: 1,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      expect(result.isEmpty, isFalse);
      expect(result.isNotEmpty, isTrue);
      expect(result.length, 1);
    });
  });

  group('BrowseFilesStrings', () {
    test('leaves the strings it was not given alone', () {
      const defaults = OCBrowseFilesStrings();
      final translated = defaults.copyWith(confirmLabel: 'Envoyer');

      expect(translated.confirmLabel, 'Envoyer');
      expect(translated.retryLabel, defaults.retryLabel);
      expect(translated.confirmButton('Envoyer', 3), 'Envoyer (3)');
      expect(defaults.selectionSummary(2, 1, 10), '2 media · 1 files (max 10)');
      expect(defaults.galleryEmptyTitle, isNotEmpty);
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
