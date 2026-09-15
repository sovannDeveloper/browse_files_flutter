import 'package:browse_files_flutter/browse_files_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

/// A harness for the plugin.
///
/// The menu is the package's entry point; below it sit the lower-level calls
/// a host app can make directly — `pickMedia` (the gallery), `captureMedia`
/// (the camera), the document picker, and `loadThumbnail` for tiles that came
/// back without bytes.
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
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _plugin = OCBrowseFilesFlutter.instance;
  final _results = <String, String>{};
  OCBrowseFilesResult? _lastResult;

  /// How many calls are in flight — the buttons are disabled while any is.
  int _busy = 0;

  bool get _running => _busy > 0;

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
    } catch (error) {
      // A programmer error (an ArgumentError, say) is still an outcome to
      // show — and the buttons must come back either way.
      outcome = 'error: $error';
    }
    if (!mounted) return value;
    setState(() {
      _busy--;
      _results[label] = outcome;
    });
    return value;
  }

  /// The short menu: take photo · record video · select photos & videos ·
  /// select files. The menu closes before the camera or picker opens.
  Future<void> _openActions() async {
    OCBrowseFilesResult? result;
    String? failure;
    try {
      result = await OCBrowseFiles.showActions(
        context,
        options: const OCBrowseFilesOptions(
          maxSelection: 5,
          accentColor: Color(0xFF2CB5A0),
        ),
      );
    } on OCBrowseFilesException catch (error) {
      failure = '${error.code.name}: ${error.message}';
    }
    if (!mounted) return;
    setState(() {
      _results['BrowseFiles.showActions'] = failure ?? _describeResult(result);
      _lastResult = result;
    });
    if (result != null && result.isNotEmpty) {
      _showResultDialog();
    }
  }

  void _showResultDialog() {
    final result = _lastResult;
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
              if (result!.media.isNotEmpty)
                ...result.media.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: const Icon(Icons.image),
                      ),
                      title: Text(
                        item.name ?? item.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${item.type.name} · ${item.id}'),
                    ),
                  ),
                ),
              if (result.documents.isNotEmpty)
                ...result.documents.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: const Icon(Icons.folder),
                      ),
                      title: Text(
                        path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              if (result.media.isEmpty && result.documents.isEmpty)
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

  /// Opens the system media picker directly, without the menu.
  Future<void> _pickMedia() async {
    final picked = await _run('pickMedia', () => _plugin.pickMedia());
    if (picked == null || !mounted) return;
    setState(() {
      _results['pickMedia'] =
          '${picked.length} item(s): ${picked.map((i) => i.id).join(', ')}';
    });
  }

  /// Opens the system camera directly, without the menu.
  Future<void> _capture(OCMediaType type) async {
    final item = await _run(
      'captureMedia(${type.name})',
      () => _plugin.captureMedia(type: type),
    );
    if (item == null || !mounted) return;
    setState(() {
      _results['captureMedia(${type.name})'] =
          '${item.type.name} ${item.width}x${item.height}'
          '${item.duration == null ? '' : ' ${item.duration}'} → ${item.id}';
    });
  }

  /// Asks for the camera without opening it — what the sheet does first.
  Future<void> _requestCamera(OCMediaType type) async {
    final status = await _run(
      'requestCameraPermission(${type.name})',
      () => _plugin.requestCameraPermission(type: type),
    );
    if (status == null || !mounted) return;
    setState(() {
      _results['requestCameraPermission(${type.name})'] = status.name;
    });
  }

  String _describeResult(OCBrowseFilesResult? result) => switch (result) {
    null => 'dismissed',
    final picked when picked.isEmpty => 'confirmed with nothing',
    final picked =>
      '${picked.media.length} media, ${picked.documents.length} documents',
  };

  /// Probes the thumbnail pipeline: picks one item, asks the platform to
  /// produce a 256x256 JPEG, and reports how long it took.
  Future<void> _probeThumbnail() async {
    await _run('loadThumbnail', () async {
      final picked = await _plugin.pickMedia(allowMultiple: false);
      if (picked.isEmpty) return 'no item picked';
      final item = picked.first;
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
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _running ? null : _openActions,
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text('Attach'),
                ),
                OutlinedButton.icon(
                  onPressed: _running ? null : _pickMedia,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('pickMedia()'),
                ),
                OutlinedButton.icon(
                  onPressed: _running
                      ? null
                      : () => _capture(OCMediaType.image),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('captureMedia(image)'),
                ),
                OutlinedButton.icon(
                  onPressed: _running
                      ? null
                      : () => _capture(OCMediaType.video),
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('captureMedia(video)'),
                ),
                OutlinedButton.icon(
                  onPressed: _running
                      ? null
                      : () => _requestCamera(OCMediaType.video),
                  icon: const Icon(Icons.lock_open_outlined, size: 18),
                  label: const Text('requestCameraPermission(video)'),
                ),
                OutlinedButton.icon(
                  onPressed: _running ? null : _probeThumbnail,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('loadThumbnail()'),
                ),
                OutlinedButton.icon(
                  onPressed: _running
                      ? null
                      : () => _run(
                          'pickDocuments',
                          () => _plugin.pickDocuments(),
                        ),
                  icon: const Icon(Icons.folder_outlined, size: 18),
                  label: const Text('pickDocuments()'),
                ),
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
                          'Tap a button above to get started',
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
          'Browse Files Flutter is a permissionless Telegram-style attach '
          'sheet. It uses the system Photo Picker, the Storage Access '
          'Framework and the system camera app, so the app declares no '
          'READ_MEDIA_*, READ_EXTERNAL_STORAGE or CAMERA permissions and '
          'ships without a Google Play Permissions Declaration Form.',
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
}

/// A list item to display results.
class _ResultItem extends StatelessWidget {
  const _ResultItem({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

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
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
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
