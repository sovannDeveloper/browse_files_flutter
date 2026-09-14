// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pickMedia reaches the host platform', (
    WidgetTester tester,
  ) async {
    // The native side on Android is implemented and on iOS is still a stub.
    // Tighten this to a real `OCMediaItem` once iOS picks up the Photo Picker
    // flow too; until then the only thing worth asserting is that the call is
    // routed and comes back as a typed exception rather than a raw
    // MissingPluginException.
    try {
      final items = await OCBrowseFilesFlutter.instance.pickMedia();
      // Android returns the picked list (possibly empty) and reports nothing
      // as a typed empty list, so reaching here means the call routed.
      expect(items, isA<List<OCMediaItem>>());
    } on OCBrowseFilesException catch (error) {
      expect(
        error.code,
        isIn(<OCBrowseFilesErrorCode>[
          OCBrowseFilesErrorCode.unimplemented,
          OCBrowseFilesErrorCode.unsupported,
        ]),
      );
    }
  });
}
