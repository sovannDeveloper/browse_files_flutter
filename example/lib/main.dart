import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flu_wake_lock/flu_wake_lock.dart';

import 'example_camera.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FluWakeLock().enable();
  runApp(const MyApp());
}

/// A harness for the platform API, ahead of the sheet UI existing.
///
/// Every call is expected to fail with [OCBrowseFilesErrorCode.unimplemented]
/// until the native side lands — the point of this screen is to show, per
/// method, exactly where the implementation has got to.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Browse Files Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2CB5A0),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// The harness screen.
///
/// It is a widget of its own rather than the thing that builds [MaterialApp]:
/// a State that builds MaterialApp sits *above* the Navigator, and its context
/// cannot push a route or a sheet — which is exactly the error you get if you
/// try.
class HomePage extends StatefulWidget {
  /// Creates the harness screen.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _plugin = OCBrowseFilesFlutter.instance;
  final _results = <String, String>{};
  OCBrowseFilesResult? _lastResult;

  /// The access level last reported, or `null` while it is unknown: nothing
  /// asked yet, or the call itself failed.
  OCMediaPermissionStatus? _permission;

  /// How many calls are in flight — the buttons are disabled while any is.
  int _busy = 0;

  bool get _running => _busy > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Settings and the photo picker both hand control back with the grant
    // possibly changed, and neither of them tells us so.
    if (state == AppLifecycleState.resumed && _permission != null) {
      _runPermission('permissionStatus', () => _plugin.permissionStatus());
    }
  }

  /// Runs [call], logging its outcome under [label], and hands back its value,
  /// or `null` when it failed.
  Future<T?> _run<T>(String label, Future<T> Function() call) async {
    setState(() {
      _busy++;
      _results[label] = 'running…';
    });
    T? value;
    String outcome;
    try {
      value = await call();
      outcome = '$value';
    } on OCBrowseFilesException catch (error) {
      outcome = '${error.code.name}: ${error.message}';
    }
    if (!mounted) return value;
    setState(() {
      _busy--;
      _results[label] = outcome;
    });
    return value;
  }

  /// Runs a permission call and adopts the access level it reports.
  ///
  /// A failed call leaves the status unknown rather than guessing at it; the
  /// log below says why it failed.
  Future<void> _runPermission(
    String label,
    Future<OCMediaPermissionStatus> Function() call,
  ) async {
    final status = await _run(label, call);
    if (!mounted) return;
    setState(() => _permission = status);
  }

  /// The sheet's camera cell, wired to this app's own camera.
  ///
  /// This is the extension point the package leaves open: the shot is saved
  /// into the library, so it comes back as an id `resolveFile` turns into a
  /// path like any other asset — and the grid shows it next time it reloads.
  Future<void> _capture() async {
    setState(() => _results['camera'] = 'opening the camera…');
    String outcome;
    try {
      final id = await const ExampleCamera().capture();
      outcome = id == null
          ? 'cancelled'
          : 'captured $id → ${await _plugin.resolveFile(id)}';
    } on OCBrowseFilesException catch (error) {
      outcome = '${error.code.name}: ${error.message}';
    } on PlatformException catch (error) {
      outcome = '${error.code}: ${error.message ?? 'the camera failed'}';
    }
    if (!mounted) return;
    setState(() => _results['camera'] = outcome);
  }

  /// The package's actual entry point: the attachment sheet, dressed the way
  /// Telegram dresses it — dark chrome, a camera cell, the full tab row.
  ///
  /// Only Gallery and File have bodies of their own; the other four are this
  /// app's, handed in as builders.
  Future<void> _openSheet() async {
    final result = await OCBrowseFiles.show(
      context,
      options: OCBrowseFilesOptions(
        maxSelection: 1,
        backgroundColor: const Color(0xFF111112),
        accentColor: const Color(0xFF2CB5A0),
        pageSize: 20,
        onCameraTap: _capture,
        types: {OCMediaType.image, OCMediaType.video},
        tabs: [OCAttachmentTab.gallery, OCAttachmentTab.file],
      ),
    );
    if (!mounted) return;
    setState(() {
      _results['BrowseFiles.show'] = _describeResult(result);
      _lastResult = result;
    });
    if (result != null && !result!.isEmpty) {
      _showResultDialog();
    }
  }

  void _showResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selected Files'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_lastResult!.media.isNotEmpty)
                ..._lastResult!.media.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: const Icon(Icons.image),
                      ),
                      title: Text('Media: ${item.id}'),
                      subtitle: Text('Type: ${item.type}'),
                    ),
                  ),
                ),
              if (_lastResult!.documents.isNotEmpty)
                ..._lastResult!.documents.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: const Icon(Icons.folder),
                      ),
                      title: Text('Document: $path'),
                    ),
                  ),
                ),
              if (_lastResult!.media.isEmpty && _lastResult!.documents.isEmpty)
                const Text('No files selected'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// The full-screen browser: photos and videos in one tab, other files in the
  /// next. Same result type as the sheet.
  Future<void> _openPage() async {
    final result = await OCBrowseFiles.showPage(
      context,
      title: 'All files',
      options: const OCBrowseFilesOptions(
        maxSelection: 10,
        allowMultipleDocuments: false,
        types: {OCMediaType.video},
        // documentMimeTypes: ['image/*', 'video/*'],
      ),
    );
    if (!mounted) return;
    setState(() => _results['BrowseFiles.showPage'] = _describeResult(result));
  }

  String _describeResult(OCBrowseFilesResult? result) => switch (result) {
    null => 'dismissed',
    final picked when picked.isEmpty => 'confirmed with nothing',
    final picked =>
      '${picked.media.length} media, ${picked.documents.length} documents'
          '${picked.media.isEmpty ? '' : ' — ${picked.media.map((item) => item.id).join(', ')}'}'
          '${picked.documents.isEmpty ? '' : ' — ${picked.documents.join(', ')}'}',
  };

  /// Asks the platform for one thumbnail and reports what came back.
  ///
  /// A blank tile in the sheet can be a request still in flight, an asset with
  /// no thumbnail, or bytes that are not an image; only the platform's own
  /// answer tells them apart.
  Future<void> _probeThumbnail() async {
    await _run('loadThumbnail', () async {
      final page = await _plugin.fetchMedia(limit: 1);
      if (page.items.isEmpty) return 'the library is empty';
      final item = page.items.first;
      final started = DateTime.now();
      final bytes = await _plugin.loadThumbnail(
        item.id,
        width: 256,
        height: 256,
      );
      final took = DateTime.now().difference(started).inMilliseconds;
      if (bytes == null) return '${item.id}: null after ${took}ms';
      return '${item.id}: ${bytes.length} bytes in ${took}ms';
    });
  }

  Future<void> _runAll() async {
    setState(() => _busy++);
    await _run('fetchAlbums', () => _plugin.fetchAlbums());
    await _run('fetchMedia', () => _plugin.fetchMedia(limit: 12));
    await _run('fetchDocuments', () => _plugin.fetchDocuments(limit: 12));
    if (!mounted) return;
    setState(() => _busy--);
  }

  @override
  Widget build(BuildContext context) {
    final labels = _results.keys.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Files Flutter'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _permissionCard(context),
                const SizedBox(height: 16),
                _actionButtons(context),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: labels.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Nothing called yet',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        Text(
                          'Tap the buttons above to get started',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: labels.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _ResultItem(
                      title: labels[index],
                      subtitle: _results[labels[index]]!,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About'),
        content: const Text(
          'Browse Files Flutter is a platform API harness for file and media selection.\n\n'
          'This example app demonstrates the plugin\'s capabilities including:\n'
          '• File and media browsing\n'
          '• Permission management\n'
          '• Thumbnail loading\n'
          '• Camera integration',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _running ? null : _openSheet,
          icon: const Icon(Icons.attach_file, size: 20),
          label: const Text('Attach files'),
        ),
        FilledButton.tonalIcon(
          onPressed: _running ? null : _openPage,
          icon: const Icon(Icons.folder_copy_outlined, size: 20),
          label: const Text('Browse all files'),
        ),
        OutlinedButton(
          onPressed: _running ? null : _runAll,
          child: const Text('Run library calls'),
        ),
        OutlinedButton(
          onPressed: _running ? null : _probeThumbnail,
          child: const Text('Probe thumbnail'),
        ),
        OutlinedButton(
          onPressed: _running
              ? null
              : () => _run('pickDocuments', () => _plugin.pickDocuments()),
          child: const Text('Pick documents'),
        ),
      ],
    );
  }

  /// The permission panel: what the app may read, and the calls that change it.
  ///
  /// The action the current status calls for is the filled button — that is
  /// the decision the sheet itself will have to make once it exists.
  Widget _permissionCard(BuildContext context) {
    final theme = Theme.of(context);
    final status = _permission;
    final next = _recommendedCall(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _statusIcon(status),
                  color: _statusColor(theme, status),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status?.name ?? 'unknown',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _statusColor(theme, status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _describe(status),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _action(
                  'permissionStatus',
                  'Check status',
                  next,
                  () => _runPermission(
                    'permissionStatus',
                    () => _plugin.permissionStatus(),
                  ),
                ),
                _action(
                  'requestPermission',
                  'Grant permission',
                  next,
                  () => _runPermission(
                    'requestPermission',
                    () => _plugin.requestPermission(),
                  ),
                ),
                _action(
                  'presentLimitedPicker',
                  'Select more',
                  next,
                  () => _runPermission(
                    'presentLimitedPicker',
                    () => _plugin.presentLimitedPicker(),
                  ),
                ),
                _action(
                  'openSettings',
                  'Open settings',
                  next,
                  () => _run('openSettings', () => _plugin.openSettings()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One permission button, filled when it is the [recommended] next call.
  Widget _action(
    String method,
    String label,
    String? recommended,
    VoidCallback onPressed,
  ) {
    final child = Text(label);
    final handler = _running ? null : onPressed;
    return method == recommended
        ? FilledButton(onPressed: handler, child: child)
        : OutlinedButton(onPressed: handler, child: child);
  }

  /// The call worth making next, or `null` when there is nothing left to ask
  /// for.
  String? _recommendedCall(OCMediaPermissionStatus? status) => switch (status) {
    OCMediaPermissionStatus.granted => null,
    OCMediaPermissionStatus.limited => 'presentLimitedPicker',
    OCMediaPermissionStatus.permanentlyDenied ||
    OCMediaPermissionStatus.restricted => 'openSettings',
    _ => 'requestPermission',
  };

  String _describe(OCMediaPermissionStatus? status) => switch (status) {
    null => 'Unknown — nothing has been asked, or the last call failed.',
    OCMediaPermissionStatus.granted => 'The whole library is readable.',
    OCMediaPermissionStatus.limited =>
      'Only the shared subset is readable. The grid shows it plus a way to '
          'widen the grant — that is a grant, not a refusal.',
    OCMediaPermissionStatus.denied => 'Refused, but asking again is allowed.',
    OCMediaPermissionStatus.permanentlyDenied =>
      'Refused for good; only system settings can change it.',
    OCMediaPermissionStatus.restricted =>
      'Blocked by policy or parental controls, so no prompt would help.',
    OCMediaPermissionStatus.notDetermined => 'Nothing has been asked yet.',
  };

  IconData _statusIcon(OCMediaPermissionStatus? status) => switch (status) {
    null || OCMediaPermissionStatus.notDetermined => Icons.help_outline,
    OCMediaPermissionStatus.granted => Icons.check_circle_outline,
    OCMediaPermissionStatus.limited => Icons.rule,
    OCMediaPermissionStatus.denied => Icons.block,
    OCMediaPermissionStatus.permanentlyDenied => Icons.settings_outlined,
    OCMediaPermissionStatus.restricted => Icons.lock_outline,
  };

  Color _statusColor(ThemeData theme, OCMediaPermissionStatus? status) =>
      switch (status) {
        null || OCMediaPermissionStatus.notDetermined =>
          theme.colorScheme.onSurfaceVariant,
        _ when status.canBrowse => theme.colorScheme.primary,
        _ => theme.colorScheme.error,
      };
}

/// A list item to display results.
class _ResultItem extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ResultItem({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.list_alt,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        trailing: subtitle.contains('running')
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
    );
  }
}
