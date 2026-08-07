import 'dart:async';

import 'package:flutter/foundation.dart';

import 'debug_log.dart';
import 'download_notifications.dart';
import 'host_factory.dart';
import 'models.dart';
import 'quickjs_source.dart';
import 'source_import.dart';
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
        homeSource: true,
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
  final DownloadNotifications _downloadNotifications = DownloadNotifications();
  final Completer<void> _ready = Completer<void>();
  final List<DownloadTask> _downloads = [];
  final Map<String, int> _pendingDownloadBytes = {};
  final Map<String, int?> _pendingDownloadTotals = {};
  final Map<String, Timer> _downloadProgressTimers = {};
  int _downloadSequence = 0;
  bool _sourceRuntimeReady = false;
  String? _runtimeError;
  List<ApkSource> get sources => List.unmodifiable(_sources);
  List<DownloadTask> get downloads => List.unmodifiable(_downloads);
  bool get sourceRuntimeReady => _sourceRuntimeReady;
  Future<void> get ready => _ready.future;
  String? get runtimeError => _runtimeError;
  Map<String, String> get sourceErrors => Map.unmodifiable(registry.lastErrors);
  bool get hasEnabledSource =>
      _sources.any((source) => source.status == SourceStatus.enabled);
  String? get homeSourceId {
    for (final source in _sources) {
      if (source.homeSource && source.status == SourceStatus.enabled) {
        return source.id;
      }
    }
    return null;
  }

  List<SourceDebugProject> get debugProjects => registry.debugProjects;

  ApkSource _sourceForScript(ApkSourceScript script, {required bool builtIn}) {
    final SourceManifestProvider? manifest = script is SourceManifestProvider
        ? script as SourceManifestProvider
        : null;
    return ApkSource(
      id: script.id,
      name: script.name,
      homepage: manifest?.homepage ?? '',
      version: manifest?.version ?? '0.0.0',
      description: manifest?.description ?? '内置 QuickJS 源',
      status: SourceStatus.enabled,
      builtIn: builtIn,
      lastSync: DateTime.now(),
    );
  }

  void _registerBuiltInScript(ApkSourceScript script) {
    final source = _sourceForScript(script, builtIn: true);
    final index = _sources.indexWhere((item) => item.id == source.id);
    if (index == -1) {
      _sources = [..._sources, source];
      return;
    }

    final existing = _sources[index];
    _sources[index] = source.copyWith(
      status: existing.status,
      homeSource: existing.homeSource,
    );
  }

  Future<void> initialize() async {
    debug.add('正在扫描内置 QuickJS 源', category: 'App');
    var loadedCount = 0;
    try {
      final assetPaths = await discoverSourceAssets();
      debug.add('发现 ${assetPaths.length} 个内置源脚本', category: 'App');
      for (final assetPath in assetPaths) {
        try {
          final quickJsSource = await loadQuickJsSource(
            assetPath,
            debug: debug,
          );
          if (quickJsSource != null) {
            registry.replace(quickJsSource);
            _registerBuiltInScript(quickJsSource);
            loadedCount += 1;
            debug.add('已加载源：$assetPath', category: 'App');
          }
        } catch (error) {
          _runtimeError = error.toString();
          debug.add(
            'QuickJS 源加载失败（$assetPath）: $error',
            level: DebugLogLevel.error,
            category: 'App',
          );
        }
      }
      if (loadedCount > 0) {
        _sourceRuntimeReady = true;
        notifyListeners();
      }
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<SourceImportResult> importSourceBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    await ready;
    final entries = sourceScriptsFromBytes(bytes, fileName);
    final imported = <ApkSource>[];
    final failures = <String, String>{};
    final loaded = <({String name, ApkSourceScript script})>[];

    for (final entry in entries) {
      try {
        if (entry.error != null || entry.text == null) {
          throw entry.error ?? const FormatException('无法读取 JS 源脚本');
        }
        final script = await loadQuickJsSourceText(
          entry.text!,
          sourceUrl: entry.name,
          debug: debug,
        );
        if (script == null) {
          throw UnsupportedError('当前平台不支持 QuickJS 源导入');
        }
        if (script.id == 'quickjs-source') {
          throw const FormatException('源 manifest 缺少有效 ID');
        }
        loaded.add((name: entry.name, script: script));
      } catch (error) {
        failures[entry.name] = error.toString();
      }
    }

    final acceptedIds = <String>{};
    for (final item in loaded) {
      final duplicate =
          !acceptedIds.add(item.script.id) ||
          _sources.any((source) => source.id == item.script.id);
      if (duplicate) {
        failures[item.name] = '源 ID 已存在：${item.script.id}';
        await item.script.dispose();
        continue;
      }
      registry.replace(item.script);
      final source = _sourceForScript(item.script, builtIn: false);
      _sources = [..._sources, source];
      imported.add(source);
    }

    if (imported.isNotEmpty) {
      notifyListeners();
      debug.add(
        '已导入 ${imported.length} 个源，失败 ${failures.length} 个',
        category: 'App',
      );
    }
    return SourceImportResult(imported: imported, failures: failures);
  }

  Future<SourceImportResult> importSourceUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('源 URL 必须是 HTTPS 地址');
    }
    final bytes = await host.requestBytes(
      uri.toString(),
      policy: SourcePolicy(allowedHosts: {uri.host}),
    );
    final lastSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final fileName = lastSegment.contains('.') ? lastSegment : 'source.js';
    return importSourceBytes(Uint8List.fromList(bytes), fileName);
  }

  Future<List<AppListing>> search(
    String query, {
    void Function(List<AppListing> results)? onSourceResults,
  }) async {
    await ready;
    debug.add('开始聚合搜索：${query.trim()}', category: 'App');
    final results = await registry.search(
      query,
      host,
      enabledSourceIds: _sources
          .where((source) => source.status == SourceStatus.enabled)
          .map((source) => source.id)
          .toSet(),
      onSourceCompleted: (_, sourceResults) {
        if (sourceResults.isNotEmpty) onSourceResults?.call(sourceResults);
      },
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

  Future<AppDetails> details(AppListing app) async {
    await ready;
    return registry.details(app, host);
  }

  Future<SourceHome> home() async {
    await ready;
    return registry.home(
      host,
      enabledSourceIds: homeSourceId == null ? const {} : {homeSourceId!},
    );
  }

  Future<SourceCategory> category(SourceCategory category) async {
    await ready;
    if (category.sourceId != homeSourceId) {
      throw StateError('该分类不属于当前主页源');
    }
    return registry.category(category, host);
  }

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

  DownloadTask? downloadFor(String url) {
    for (final task in _downloads) {
      if (task.file.url == url) return task;
    }
    return null;
  }

  DownloadTask startDownload(SourceDownload file, String sourceId) {
    final existing = downloadFor(file.url);
    if (existing != null && existing.status == DownloadStatus.downloading) {
      return existing;
    }
    if (existing != null && existing.status == DownloadStatus.paused) {
      unawaited(resumeDownload(existing));
      return existing;
    }
    if (existing != null && existing.status == DownloadStatus.completed) {
      return existing;
    }

    final now = DateTime.now();
    late final DownloadTask task;
    if (existing == null) {
      task = DownloadTask(
        id: '${now.microsecondsSinceEpoch}-${_downloadSequence++}',
        file: file,
        sourceId: sourceId,
        status: DownloadStatus.downloading,
        startedAt: now,
      );
      _downloads.insert(0, task);
    } else {
      task = existing.copyWith(
        status: DownloadStatus.downloading,
        startedAt: now,
        received: 0,
        total: null,
        filePath: null,
        error: null,
        completedAt: null,
      );
      _replaceDownload(task, notify: false);
    }

    debug.add('开始下载：${file.label}', category: 'Download');
    notifyListeners();
    unawaited(_runDownload(task.id));
    return task;
  }

  DownloadTask retryDownload(DownloadTask task) {
    if (task.status == DownloadStatus.paused) {
      unawaited(resumeDownload(task));
      return task;
    }
    return startDownload(task.file, task.sourceId);
  }

  Future<void> pauseDownload(DownloadTask task) async {
    final current = _downloadById(task.id);
    if (current?.status != DownloadStatus.downloading) return;
    _replaceDownload(current!.copyWith(status: DownloadStatus.paused));
    debug.add('暂停下载：${current.file.label}', category: 'Download');
    try {
      await host.pauseDownload(current.id);
    } catch (error) {
      _replaceDownload(current.copyWith(status: DownloadStatus.downloading));
      debug.add(
        '暂停下载失败：${current.file.label} · $error',
        level: DebugLogLevel.error,
        category: 'Download',
      );
    }
  }

  Future<void> resumeDownload(DownloadTask task) async {
    final current = _downloadById(task.id);
    if (current?.status != DownloadStatus.paused) return;
    _replaceDownload(current!.copyWith(status: DownloadStatus.downloading));
    debug.add('继续下载：${current.file.label}', category: 'Download');
    try {
      await host.resumeDownload(current.id);
    } catch (error) {
      _replaceDownload(current.copyWith(status: DownloadStatus.paused));
      debug.add(
        '继续下载失败：${current.file.label} · $error',
        level: DebugLogLevel.error,
        category: 'Download',
      );
    }
  }

  Future<void> cancelDownload(DownloadTask task) async {
    final current = _downloadById(task.id);
    if (current == null ||
        (current.status != DownloadStatus.downloading &&
            current.status != DownloadStatus.paused)) {
      return;
    }
    _replaceDownload(
      current.copyWith(
        status: DownloadStatus.canceled,
        error: null,
        completedAt: DateTime.now(),
      ),
    );
    debug.add('取消下载：${current.file.label}', category: 'Download');
    try {
      await host.cancelDownload(current.id);
    } catch (error) {
      debug.add(
        '取消下载清理失败：${current.file.label} · $error',
        level: DebugLogLevel.warning,
        category: 'Download',
      );
    }
  }

  Future<void> _runDownload(String taskId) async {
    final task = _downloadById(taskId);
    if (task == null) return;
    final script = registry.scriptFor(task.sourceId);
    await _downloadNotifications.requestPermission();
    await _downloadNotifications.showProgress(
      id: task.id,
      title: task.file.label,
      received: 0,
      total: null,
    );

    try {
      final path = await host.download(
        task.file.url,
        headers: task.file.headers,
        downloadId: task.id,
        fileName:
            RegExp(
              r'\.(apk|apks|xapk|zip)$',
              caseSensitive: false,
            ).hasMatch(task.file.label)
            ? task.file.label
            : null,
        policy: script.policy,
        onProgress: (received, total) =>
            _queueDownloadProgress(task.id, received, total),
      );
      _flushDownloadProgress(task.id);
      final current = _downloadById(task.id);
      if (current == null) return;
      final completed = current.copyWith(
        status: DownloadStatus.completed,
        filePath: path,
        error: null,
        completedAt: DateTime.now(),
      );
      _replaceDownload(completed);
      debug.add('下载完成：${task.file.label} · $path', category: 'Download');
      await _downloadNotifications.showCompleted(
        id: task.id,
        title: task.file.label,
        path: path,
      );
    } catch (error) {
      _flushDownloadProgress(task.id);
      final current = _downloadById(task.id);
      if (current == null) return;
      if (current.status == DownloadStatus.canceled ||
          error is DownloadCancelledException) {
        if (current.status != DownloadStatus.canceled) {
          _replaceDownload(
            current.copyWith(
              status: DownloadStatus.canceled,
              error: null,
              completedAt: DateTime.now(),
            ),
          );
        }
        debug.add('已取消下载：${task.file.label}', category: 'Download');
        return;
      }
      _replaceDownload(
        current.copyWith(
          status: DownloadStatus.failed,
          error: error.toString(),
          completedAt: DateTime.now(),
        ),
      );
      debug.add(
        '下载失败：${task.file.label} · $error',
        level: DebugLogLevel.error,
        category: 'Download',
      );
      await _downloadNotifications.showFailed(
        id: task.id,
        title: task.file.label,
        error: error.toString(),
      );
    }
  }

  void _queueDownloadProgress(String id, int received, int? total) {
    _pendingDownloadBytes[id] = received;
    _pendingDownloadTotals[id] = total;
    _downloadProgressTimers.putIfAbsent(
      id,
      () => Timer(
        const Duration(milliseconds: 250),
        () => _flushDownloadProgress(id),
      ),
    );
  }

  void _flushDownloadProgress(String id) {
    _downloadProgressTimers.remove(id)?.cancel();
    final received = _pendingDownloadBytes.remove(id);
    final total = _pendingDownloadTotals.remove(id);
    final task = _downloadById(id);
    if (received == null || task?.status != DownloadStatus.downloading) return;
    final updated = task!.copyWith(received: received, total: total);
    _replaceDownload(updated);
    unawaited(
      _downloadNotifications.showProgress(
        id: id,
        title: updated.file.label,
        received: received,
        total: total,
      ),
    );
  }

  DownloadTask? _downloadById(String id) {
    for (final task in _downloads) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _replaceDownload(DownloadTask task, {bool notify = true}) {
    final index = _downloads.indexWhere((item) => item.id == task.id);
    if (index == -1) return;
    _downloads[index] = task;
    if (notify) notifyListeners();
  }

  Future<bool> installTask(DownloadTask task) {
    final path = task.filePath;
    if (path == null) throw StateError('下载文件尚未完成');
    return install(path, task.sourceId);
  }

  Future<bool> install(String path, String sourceId) {
    final script = registry.scriptFor(sourceId);
    return host.install(path, policy: script.policy);
  }

  void setHomeSource(String id) {
    ApkSource? selected;
    for (final source in _sources) {
      if (source.id == id && source.status == SourceStatus.enabled) {
        selected = source;
        break;
      }
    }
    if (selected == null) return;
    _sources = _sources
        .map((item) => item.copyWith(homeSource: item.id == selected!.id))
        .toList();
    notifyListeners();
  }

  void toggleSource(String id, bool enabled) {
    _sources = _sources
        .map(
          (source) => source.id == id
              ? source.copyWith(
                  status: enabled
                      ? SourceStatus.enabled
                      : SourceStatus.disabled,
                  homeSource: enabled ? source.homeSource : false,
                )
              : source,
        )
        .toList();
    notifyListeners();
  }

  void removeSource(String id) {
    final source = _sources.where((item) => item.id == id).firstOrNull;
    if (source == null || source.builtIn) return;
    _sources.removeWhere((item) => item.id == id);
    unawaited(registry.remove(id));
    notifyListeners();
  }

  void addSource(ApkSource source) {
    _sources = [..._sources, source];
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _downloadProgressTimers.values) {
      timer.cancel();
    }
    _downloadProgressTimers.clear();
    host.dispose();
    registry.dispose();
    debug.dispose();
    super.dispose();
  }
}
