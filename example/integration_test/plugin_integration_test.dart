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

  testWidgets('permissionStatus reaches the host platform', (
    WidgetTester tester,
  ) async {
    // The native side is a stub, so the only thing worth asserting today is
    // that the call is routed and comes back as a typed exception rather than
    // a raw MissingPluginException. Tighten this to a real status once
    // permissionStatus is implemented on both platforms.
    await expectLater(
      OCBrowseFilesFlutter.instance.permissionStatus(),
      throwsA(
        isA<OCBrowseFilesException>().having(
          (error) => error.code,
          'code',
          OCBrowseFilesErrorCode.unimplemented,
        ),
      ),
    );
  });
}
