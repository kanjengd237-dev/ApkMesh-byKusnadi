import 'package:flutter/foundation.dart';

import 'host_factory.dart';
import 'models.dart';
import 'quickjs_source.dart';
import 'source_runtime.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _sources = [
      ApkSource(
        id: 'apkaward-demo',
        name: 'APK Award（测试源）',
        homepage: 'apkaward.com',
        version: '0.1.0',
        description: '内置演示源，用于验证搜索、详情和下载接口。',
        status: SourceStatus.enabled,
        builtIn: true,
        lastSync: DateTime.now(),
      ),
    ];
  }

  late List<ApkSource> _sources;
  final SourceRegistry registry = SourceRegistry(
    scripts: [ApkAwardDemoScript()],
  );
  final SourceHostApi host = createPlatformHostApi();
  bool _sourceRuntimeReady = false;
  List<ApkSource> get sources => List.unmodifiable(_sources);
  bool get sourceRuntimeReady => _sourceRuntimeReady;
  bool get hasEnabledSource =>
      _sources.any((source) => source.status == SourceStatus.enabled);

  Future<void> initialize() async {
    try {
      final quickJsSource = await loadQuickJsSource(
        'assets/sources/apkaward.js',
      );
      if (quickJsSource != null) {
        registry.replace(quickJsSource);
        _sourceRuntimeReady = true;
        notifyListeners();
      }
    } catch (_) {
      // Keep the deterministic demo source available when native services are unavailable.
    }
  }

  Future<List<AppListing>> search(String query) => registry.search(
    query,
    host,
    enabledSourceIds: _sources
        .where((source) => source.status == SourceStatus.enabled)
        .map((source) => source.id)
        .toSet(),
  );

  Future<AppDetails> details(AppListing app) => registry.details(app, host);

  Future<String> download(
    SourceDownload file,
    String sourceId, {
    void Function(int received, int? total)? onProgress,
  }) {
    final script = registry.scriptFor(sourceId);
    return host.download(
      file.url,
      fileName:
          RegExp(
            r'\.(apk|apks|xapk|zip)$',
            caseSensitive: false,
          ).hasMatch(file.label)
          ? file.label
          : null,
      policy: script.policy,
      onProgress: onProgress,
    );
  }

  Future<bool> install(String path, String sourceId) {
    final script = registry.scriptFor(sourceId);
    return host.install(path, policy: script.policy);
  }

  void toggleSource(String id, bool enabled) {
    _sources = _sources
        .map(
          (source) => source.id == id
              ? source.copyWith(
                  status: enabled
                      ? SourceStatus.enabled
                      : SourceStatus.disabled,
                )
              : source,
        )
        .toList();
    notifyListeners();
  }

  void removeSource(String id) {
    _sources.removeWhere((source) => source.id == id && !source.builtIn);
    notifyListeners();
  }

  void addSource(ApkSource source) {
    _sources = [..._sources, source];
    notifyListeners();
  }

  @override
  void dispose() {
    host.dispose();
    registry.dispose();
    super.dispose();
  }
}
