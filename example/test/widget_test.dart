import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:browse_files_flutter_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts with nothing called', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Nothing called yet.'), findsOneWidget);
    expect(find.text('Run library calls'), findsOneWidget);
  });

  testWidgets('the attach button opens the sheet', (WidgetTester tester) async {
    _useFakePlatform();

    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Attach files'));
    await tester.pumpAndSettle();

    // The sheet is pushed onto the app's Navigator, so this fails outright if
    // the screen is ever hoisted above MaterialApp again.
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
  });

  testWidgets('the browse button opens the page', (WidgetTester tester) async {
    _useFakePlatform();

    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Browse all files'));
    await tester.pumpAndSettle();

    expect(find.text('Photos & videos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
  });

  testWidgets('offers the permission calls, status unknown until asked', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('unknown'), findsOneWidget);
    expect(
      find.text('Unknown — nothing has been asked, or the last call failed.'),
      findsOneWidget,
    );
    for (final label in [
      'Check status',
      'Grant permission',
      'Select more',
      'Open settings',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label button');
    }
    // Nothing granted yet, so asking is the recommended call.
    expect(
      find.widgetWithText(FilledButton, 'Grant permission'),
      findsOneWidget,
    );
  });

  testWidgets('granting adopts the status the platform reports', (
    WidgetTester tester,
  ) async {
    final platform = _useFakePlatform(OCMediaPermissionStatus.limited);

    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('Grant permission'));
    await tester.pumpAndSettle();

    expect(platform.requests, 1);
    expect(find.text('limited'), findsOneWidget);
    expect(find.text('requestPermission'), findsOneWidget);
    expect(find.text('${OCMediaPermissionStatus.limited}'), findsOneWidget);
    // A limited grant is a grant: the next call on offer widens it.
    expect(find.widgetWithText(FilledButton, 'Select more'), findsOneWidget);
  });
}

/// Installs [_FakePlatform] for one test and puts the real one back after.
///
/// Anything that opens the sheet or the page needs this: a method channel with
/// no native side behind it never completes inside a widget test's fake async,
/// so the grid would sit on its spinner until `pumpAndSettle` gave up.
_FakePlatform _useFakePlatform([
  OCMediaPermissionStatus status = OCMediaPermissionStatus.denied,
]) {
  final platform = _FakePlatform(status);
  OCBrowseFilesFlutterPlatform.instance = platform;
  addTearDown(
    () => OCBrowseFilesFlutterPlatform.instance =
        OCMethodChannelBrowseFilesFlutter(),
  );
  return platform;
}

/// A platform that answers [status] without touching a channel, and reports an
/// empty library for everything else.
class _FakePlatform extends OCBrowseFilesFlutterPlatform {
  _FakePlatform(this.status);

  final OCMediaPermissionStatus status;
  int requests = 0;

  @override
  Future<OCMediaPermissionStatus> permissionStatus({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async => status;

  @override
  Future<OCMediaPermissionStatus> requestPermission({
    Set<OCMediaType> types = kAllMediaTypes,
  }) async {
    requests++;
    return status;
  }

  @override
  Future<OCMediaPage> fetchMedia({
    String? albumId,
    Set<OCMediaType> types = kAllMediaTypes,
    int offset = 0,
    int limit = 60,
  }) async => OCMediaPage.empty;

  @override
  Future<OCDocumentPage> fetchDocuments({
    List<String> mimeTypes = const [],
    int offset = 0,
    int limit = 60,
  }) async => OCDocumentPage.empty;

  @override
  Future<List<String>> pickDocuments({
    List<String> mimeTypes = const [],
    bool allowMultiple = true,
  }) async => const <String>[];
}
