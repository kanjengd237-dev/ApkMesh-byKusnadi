import 'package:flutter/foundation.dart';

import 'debug_log.dart';
import 'host_factory.dart';
import 'models.dart';
import 'quickjs_source.dart';
import 'source_runtime.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _sources = [
      ApkSource(
        id: 'apkvision-demo',
        name: 'APKVision（测试源）',
        homepage: 'apkvision.org',
        version: '1.0.0',
        description: '内置演示源，用于验证 APKVision 搜索、详情和下载接口。',
        status: SourceStatus.enabled,
        builtIn: true,
        lastSync: DateTime.now(),
      ),
    ];
  }

  late List<ApkSource> _sources;
  final SourceRegistry registry = SourceRegistry(
    scripts: [ApkVisionDemoScript()],
  );
  final DebugLogStore debug = DebugLogStore();
  late final SourceHostApi host = createPlatformHostApi(debug: debug);
  bool _sourceRuntimeReady = false;
  String? _runtimeError;
  List<ApkSource> get sources => List.unmodifiable(_sources);
  bool get sourceRuntimeReady => _sourceRuntimeReady;
  String? get runtimeError => _runtimeError;
  Map<String, String> get sourceErrors => Map.unmodifiable(registry.lastErrors);
  bool get hasEnabledSource =>
      _sources.any((source) => source.status == SourceStatus.enabled);
  List<SourceDebugProject> get debugProjects => registry.debugProjects;

  Future<void> initialize() async {
    debug.add('正在加载内置 QuickJS 源', category: 'App');
    try {
      final quickJsSource = await loadQuickJsSource(
        'assets/sources/apkvision.js',
        debug: debug,
      );
      if (quickJsSource != null) {
        registry.replace(quickJsSource);
        _sourceRuntimeReady = true;
        debug.add('内置 QuickJS 源加载完成', category: 'App');
        notifyListeners();
      }
    } catch (error) {
      // Keep the deterministic demo source available when native services are unavailable.
      _runtimeError = error.toString();
      debug.add(
        'QuickJS 源加载失败: $error',
        level: DebugLogLevel.error,
        category: 'App',
      );
      notifyListeners();
    }
  }

  Future<List<AppListing>> search(String query) async {
    debug.add('开始聚合搜索：${query.trim()}', category: 'App');
    final results = await registry.search(
      query,
      host,
      enabledSourceIds: _sources
          .where((source) => source.status == SourceStatus.enabled)
          .map((source) => source.id)
          .toSet(),
    );
    for (final entry in sourceErrors.entries) {
      debug.add(
        '${entry.key} 执行失败：${entry.value}',
        level: DebugLogLevel.error,
        category: 'Source',
      );
    }
    debug.add('聚合搜索完成，结果 ${results.length} 条', category: 'App');
    return results;
  }

  Future<AppDetails> details(AppListing app) => registry.details(app, host);

  Future<DebugProjectResult> runDebugProject(
    SourceDebugProject project,
    String input,
  ) async {
    final enabled = _sources.any(
      (source) =>
          source.id == project.sourceId &&
          source.status == SourceStatus.enabled,
    );
    if (!enabled) throw StateError('源未启用：${project.sourceName}');
    debug.add(
      '开始调试项目：${project.name} · ${project.sourceName}',
      category: 'Debug',
    );
    try {
      final result = await registry.runDebugProject(project, input, host);
      debug.add(result.summary, category: 'Debug');
      return result;
    } catch (error) {
      debug.add(
        '调试项目失败：${project.name} · $error',
        level: DebugLogLevel.error,
        category: 'Debug',
      );
      rethrow;
    }
  }

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
    debug.dispose();
    super.dispose();
  }
}
