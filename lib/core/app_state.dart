import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'debug_log.dart';
import 'download_notifications.dart';
import 'download_store.dart';
import 'host_factory.dart';
import 'models.dart';
import 'quickjs_source.dart';
import 'source_import.dart';
import 'source_runtime.dart';
import 'translation_service.dart';

String _newTranslationDeviceId() =>
    'apkmesh-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';

class AppState extends ChangeNotifier {
  AppState({SourceHostApi? host}) : _hostOverride = host {
    _sources = [
      ApkSource(
        id: 'apkvision-demo',
        name: 'APKVision',
        homepage: 'apkvision.org',
        version: '1.0.0',
        description: '内置演示源，用于验证 APKVision 搜索、详情和下载接口。',
        status: SourceStatus.enabled,
        builtIn: true,
        homeSource: true,
        lastSync: DateTime.now(),
      ),
    ];
    _downloadNotifications = DownloadNotifications(
      onAction: _handleDownloadNotificationAction,
    );
    _settingsReady = _restoreSettings();
  }

  final SourceHostApi? _hostOverride;
  late List<ApkSource> _sources;
  final SourceRegistry registry = SourceRegistry(
    scripts: [ApkVisionDemoScript()],
  );
  final DebugLogStore debug = DebugLogStore();
  late final SourceHostApi host =
      _hostOverride ?? createPlatformHostApi(debug: debug);
  late final DownloadNotifications _downloadNotifications;
  final Completer<void> _ready = Completer<void>();
  final DownloadStore _downloadStore = createDownloadStore();
  final TranslationService translation = TranslationService();
  final List<DownloadTask> _downloads = [];
  final Map<String, ApkInstallInfo> _installInfos = {};
  final Set<String> _installStateChecks = {};
  final Set<String> _installingDownloads = {};
  final Map<String, String> _translationCache = {};
  final Set<String> _translationPending = {};
  final Set<String> _translationQueue = {};
  Timer? _translationQueueTimer;
  TranslationSettings _translationSettings = const TranslationSettings();
  AppThemeMode _themeMode = AppThemeMode.system;
  InstallMethod _installMethod = InstallMethod.system;
  ShizukuStatus _shizukuStatus = ShizukuStatus.unsupported;
  String _translationDeviceId = _newTranslationDeviceId();
  SharedPreferences? _preferences;
  late final Future<void> _settingsReady;
  final Set<String> _resumeAfterInitialize = {};
  final Map<String, int> _pendingDownloadBytes = {};
  final Map<String, int?> _pendingDownloadTotals = {};
  final Map<String, Timer> _downloadProgressTimers = {};
  final Map<String, ({int received, DateTime timestamp})>
  _downloadProgressSamples = {};
  Future<void> _downloadPersistenceQueue = Future.value();
  Timer? _downloadPersistenceTimer;
  int _downloadSequence = 0;
  bool _isDisposing = false;
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
  TranslationSettings get translationSettings => _translationSettings;
  AppThemeMode get themeMode => _themeMode;
  InstallMethod get installMethod => _installMethod;
  bool get useShizukuInstaller => _installMethod == InstallMethod.shizuku;
  ShizukuStatus get shizukuStatus => _shizukuStatus;
  ApkInstallInfo? installInfoFor(String downloadId) =>
      _installInfos[downloadId];
  bool isInstallingDownload(String downloadId) =>
      _installingDownloads.contains(downloadId);

  String? translatedText(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    return _translationCache[_translationKey(value, _translationSettings)];
  }

  Future<String> translateToEnglish(String text) async {
    final value = text.trim();
    if (value.isEmpty) return '';
    await _settingsReady;
    if (_isDisposing) throw StateError('翻译服务已关闭');
    final settings = _translationSettings.copyWith(targetLanguage: 'en');
    final results = await translation.translate(
      [value],
      settings: settings,
      deviceId: _translationDeviceId,
    );
    if (results.isEmpty || results.first.trim().isEmpty) {
      throw const FormatException('翻译接口没有返回结果');
    }
    return results.first.trim();
  }

  bool isTranslationLoading(String text) {
    final value = text.trim();
    return value.isNotEmpty &&
        _translationPending.contains(
          _translationKey(value, _translationSettings),
        );
  }

  void ensureTranslations(Iterable<String> texts) {
    if (_isDisposing) return;
    for (final rawText in texts) {
      final text = rawText.trim();
      if (text.isEmpty) continue;
      final key = _translationKey(text, _translationSettings);
      if (_translationCache.containsKey(key) ||
          _translationPending.contains(key)) {
        continue;
      }
      _translationQueue.add(text);
    }
    if (_translationQueue.isNotEmpty && _translationQueueTimer == null) {
      _translationQueueTimer = Timer(
        const Duration(milliseconds: 50),
        _flushTranslationQueue,
      );
    }
  }

  void _flushTranslationQueue() {
    _translationQueueTimer = null;
    if (_translationQueue.isEmpty || _isDisposing) return;
    final texts = _translationQueue.toList(growable: false);
    _translationQueue.clear();
    final settings = _translationSettings;
    final keys = texts
        .map((text) => _translationKey(text, settings))
        .toList(growable: false);
    _translationPending.addAll(keys);
    unawaited(_runTranslations(texts, settings, keys));
  }

  Future<void> _runTranslations(
    List<String> texts,
    TranslationSettings settings,
    List<String> keys,
  ) async {
    try {
      final results = await translation.translate(
        texts,
        settings: settings,
        deviceId: _translationDeviceId,
      );
      for (var index = 0; index < texts.length; index++) {
        final result = results[index].trim();
        if (result.isNotEmpty) _translationCache[keys[index]] = result;
      }
    } catch (error) {
      if (!_isDisposing) {
        debug.add(
          '${settings.provider.label} 翻译失败：$error',
          level: DebugLogLevel.warning,
          category: 'Translation',
        );
      }
    } finally {
      _translationPending.removeAll(keys);
      if (!_isDisposing) notifyListeners();
    }
  }

  String _translationKey(String text, TranslationSettings settings) =>
      '${settings.provider.name}|${translationLanguageCode(settings.targetLanguage, settings.provider)}|$text';

  void setThemeMode(AppThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    unawaited(_persistSettings());
  }

  void setTranslationProvider(TranslationProvider provider) {
    if (_translationSettings.provider == provider) return;
    _translationSettings = _translationSettings.copyWith(provider: provider);
    _translationCache.clear();
    notifyListeners();
    unawaited(_persistSettings());
  }

  void setTranslationLanguage(String language) {
    if (_translationSettings.targetLanguage == language) return;
    _translationSettings = _translationSettings.copyWith(
      targetLanguage: language,
    );
    _translationCache.clear();
    notifyListeners();
    unawaited(_persistSettings());
  }

  void setAutoTranslate(bool enabled) {
    if (_translationSettings.autoTranslate == enabled) return;
    _translationSettings = _translationSettings.copyWith(
      autoTranslate: enabled,
    );
    notifyListeners();
    unawaited(_persistSettings());
  }

  void setGooglePublicKey(String value) {
    final key = value.trim();
    if (_translationSettings.googlePublicKey == key) return;
    _translationSettings = _translationSettings.copyWith(googlePublicKey: key);
    _translationCache.removeWhere(
      (cacheKey, _) => cacheKey.startsWith('google|'),
    );
    notifyListeners();
    unawaited(_persistSettings());
  }

  Future<void> refreshShizukuStatus() async {
    try {
      final status = await host.shizukuStatus();
      if (_isDisposing || _shizukuStatus == status) return;
      _shizukuStatus = status;
      notifyListeners();
    } catch (error) {
      if (!_isDisposing) {
        debug.add(
          '读取 Shizuku 状态失败：$error',
          level: DebugLogLevel.warning,
          category: 'Install',
        );
      }
    }
  }

  Future<void> refreshInstallState(DownloadTask task) async {
    final path = task.filePath;
    if (task.status != DownloadStatus.completed || path == null) return;
    if (!_installStateChecks.add(task.id)) return;
    try {
      final info = await host.inspectInstall(path);
      final current = _downloadById(task.id);
      if (_isDisposing || current?.filePath != path) return;
      _installInfos[task.id] = info;
      notifyListeners();
    } catch (error) {
      if (!_isDisposing) {
        debug.add(
          '读取安装状态失败：${task.file.label} · $error',
          level: DebugLogLevel.warning,
          category: 'Install',
        );
      }
    } finally {
      _installStateChecks.remove(task.id);
    }
  }

  Future<void> refreshInstallStates() async {
    final completed = _downloads
        .where(
          (task) =>
              task.status == DownloadStatus.completed && task.filePath != null,
        )
        .toList(growable: false);
    for (final task in completed) {
      await refreshInstallState(task);
    }
  }

  Future<void> openInstalledTask(DownloadTask task) async {
    var info = _installInfos[task.id];
    if (info == null || !info.versionMatches) {
      await refreshInstallState(task);
      info = _installInfos[task.id];
    }
    final packageName = info?.packageName;
    if (info == null || !info.versionMatches || packageName == null) {
      throw StateError(info?.error ?? '当前 APK 版本尚未安装或无法打开');
    }
    if (!await host.openInstalled(packageName)) {
      throw StateError('无法打开已安装的应用');
    }
  }

  Future<bool> setUseShizukuInstaller(bool enabled) async {
    await _settingsReady;
    if (_isDisposing) return false;
    if (!enabled) {
      if (_installMethod == InstallMethod.system) return true;
      _installMethod = InstallMethod.system;
      host.setInstallMethod(_installMethod);
      notifyListeners();
      await _persistSettings();
      return true;
    }

    final status = await host.requestShizukuPermission();
    if (_isDisposing) return false;
    _shizukuStatus = status;
    if (status != ShizukuStatus.authorized) {
      notifyListeners();
      return false;
    }
    _installMethod = InstallMethod.shizuku;
    host.setInstallMethod(_installMethod);
    notifyListeners();
    await _persistSettings();
    return true;
  }

  Future<void> _restoreSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (_isDisposing) return;
      _preferences = preferences;
      final providerIndex = preferences.getInt('translation.provider') ?? 0;
      final provider =
          providerIndex >= 0 &&
              providerIndex < TranslationProvider.values.length
          ? TranslationProvider.values[providerIndex]
          : TranslationProvider.microsoft;
      final themeModeIndex =
          preferences.getInt('theme.mode') ?? AppThemeMode.system.index;
      _themeMode =
          themeModeIndex >= 0 && themeModeIndex < AppThemeMode.values.length
          ? AppThemeMode.values[themeModeIndex]
          : AppThemeMode.system;
      _installMethod = switch (preferences.getString('install.method')) {
        'shizuku' => InstallMethod.shizuku,
        _ => InstallMethod.system,
      };
      host.setInstallMethod(_installMethod);
      _translationSettings = TranslationSettings(
        provider: provider,
        targetLanguage:
            preferences.getString('translation.language') ?? 'system',
        autoTranslate: preferences.getBool('translation.auto') ?? true,
        googlePublicKey: preferences.getString('translation.googleKey') ?? '',
      );
      _translationDeviceId =
          preferences.getString('translation.deviceId') ??
          _newTranslationDeviceId();
      await preferences.setString('translation.deviceId', _translationDeviceId);
      try {
        _shizukuStatus = await host.shizukuStatus();
      } catch (error) {
        debug.add(
          '读取 Shizuku 状态失败：$error',
          level: DebugLogLevel.warning,
          category: 'Install',
        );
      }
      if (!_isDisposing) notifyListeners();
    } catch (error) {
      _translationDeviceId = _newTranslationDeviceId();
      if (!_isDisposing) {
        debug.add(
          '读取翻译设置失败：$error',
          level: DebugLogLevel.warning,
          category: 'Translation',
        );
      }
    }
  }

  Future<void> _persistSettings() async {
    await _settingsReady;
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setInt(
      'translation.provider',
      _translationSettings.provider.index,
    );
    await preferences.setString(
      'translation.language',
      _translationSettings.targetLanguage,
    );
    await preferences.setBool(
      'translation.auto',
      _translationSettings.autoTranslate,
    );
    await preferences.setString(
      'translation.googleKey',
      _translationSettings.googlePublicKey,
    );
    await preferences.setInt('theme.mode', _themeMode.index);
    await preferences.setString('install.method', _installMethod.name);
  }

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
      supportsPackageLookup:
          script is SourcePackageLookupScript &&
          (script as SourcePackageLookupScript).supportsPackageLookup,
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

  Future<void> _restoreDownloads() async {
    try {
      final restored = await _downloadStore.load();
      final ids = <String>{};
      for (final task in restored) {
        if (!ids.add(task.id)) continue;
        if (task.status == DownloadStatus.downloading) {
          _resumeAfterInitialize.add(task.id);
          _downloads.add(
            task.copyWith(
              status: DownloadStatus.paused,
              speedBytesPerSecond: null,
            ),
          );
        } else {
          _downloads.add(task);
        }
      }
      if (_downloads.isNotEmpty) notifyListeners();
      debug.add('恢复 ${_downloads.length} 条下载任务', category: 'Download');
    } catch (error) {
      debug.add(
        '读取下载任务失败：$error',
        level: DebugLogLevel.error,
        category: 'Download',
      );
    }
  }

  void _scheduleDownloadPersistence({bool immediate = false}) {
    if (_isDisposing && !immediate) return;
    if (immediate) {
      _downloadPersistenceTimer?.cancel();
      _downloadPersistenceTimer = null;
      _persistDownloadsNow();
      return;
    }
    if (_downloadPersistenceTimer != null) return;
    _downloadPersistenceTimer = Timer(
      const Duration(milliseconds: 500),
      _persistDownloadsNow,
    );
  }

  void _persistDownloadsNow() {
    _downloadPersistenceTimer?.cancel();
    _downloadPersistenceTimer = null;
    final snapshot = List<DownloadTask>.unmodifiable(_downloads);
    _downloadPersistenceQueue = _downloadPersistenceQueue.then((_) async {
      try {
        await _downloadStore.save(snapshot);
      } catch (error) {
        debugPrint('[APK Mesh] 保存下载任务失败：$error');
      }
    });
  }

  Future<void> _resumeRestoredDownloads() async {
    final ids = _resumeAfterInitialize.toList(growable: false);
    _resumeAfterInitialize.clear();
    for (final id in ids) {
      if (_isDisposing) return;
      final task = _downloadById(id);
      if (task == null) continue;
      try {
        _policyForTask(task);
      } catch (_) {
        _replaceDownload(
          task.copyWith(
            status: DownloadStatus.failed,
            error: '下载源未恢复，请重新导入源后重试',
            completedAt: DateTime.now(),
          ),
        );
        continue;
      }
      _replaceDownload(
        task.copyWith(
          status: DownloadStatus.downloading,
          speedBytesPerSecond: null,
          error: null,
          completedAt: null,
        ),
      );
      unawaited(_runDownload(id));
    }
  }

  Future<void> initialize() async {
    unawaited(_settingsReady);
    await _restoreDownloads();
    unawaited(refreshInstallStates());
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
      unawaited(_resumeRestoredDownloads());
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

  Future<List<SourceTestResult>> testAllSources({
    String query = 'hello',
    Set<String>? sourceIds,
  }) async {
    await ready;
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];

    final sourceSnapshot = _sources
        .where(
          (source) =>
              source.status == SourceStatus.enabled &&
              (sourceIds == null || sourceIds.contains(source.id)),
        )
        .toList(growable: false);
    final availableSourceIds = sourceSnapshot
        .map((source) => source.id)
        .toSet();
    debug.add('开始批量测试源：搜索“$normalized”', category: 'Source');
    final pages = await registry.searchPage(
      normalized,
      host,
      enabledSourceIds: availableSourceIds,
      clearErrors: true,
    );
    final pagesBySource = {for (final page in pages) page.sourceId: page};
    final results = sourceSnapshot
        .map((source) {
          final page = pagesBySource[source.id];
          if (page == null) {
            return SourceTestResult(
              sourceId: source.id,
              sourceName: source.name,
              resultCount: 0,
              error: '源运行时未加载',
            );
          }
          return SourceTestResult(
            sourceId: source.id,
            sourceName: source.name,
            resultCount: page.results.length,
            error: page.error,
          );
        })
        .toList(growable: false);
    final failed = results.where((result) => !result.succeeded).length;
    debug.add(
      '批量测试完成：可用 ${results.length - failed} 个，失败 $failed 个',
      category: 'Source',
    );
    return results;
  }

  Future<List<AppListing>> search(
    String query, {
    Set<String>? sourceIds,
    void Function(List<AppListing> results)? onSourceResults,
  }) async {
    await ready;
    debug.add('开始聚合搜索：${query.trim()}', category: 'App');
    final enabledSourceIds = _sources
        .where(
          (source) =>
              source.status == SourceStatus.enabled &&
              (sourceIds == null || sourceIds.contains(source.id)),
        )
        .map((source) => source.id)
        .toSet();
    final results = await registry.search(
      query,
      host,
      enabledSourceIds: enabledSourceIds,
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

  Future<List<AppListing>> lookupByPackageName(String packageName) async {
    await ready;
    final normalized = packageName.trim();
    if (normalized.isEmpty) return const [];
    debug.add('开始按包名查找：$normalized', category: 'App');
    final enabledSourceIds = _sources
        .where((source) => source.status == SourceStatus.enabled)
        .map((source) => source.id)
        .toSet();
    final results = await registry.lookupByPackageName(
      normalized,
      host,
      enabledSourceIds: enabledSourceIds,
    );
    for (final entry in sourceErrors.entries) {
      debug.add(
        '${entry.key} 执行失败：${entry.value}',
        level: DebugLogLevel.error,
        category: 'Source',
      );
    }
    debug.add('按包名查找完成，结果 ${results.length} 条', category: 'App');
    return results;
  }

  Future<List<SourceSearchPage>> searchPage(
    String query, {
    int page = 1,
    Set<String>? sourceIds,
    void Function(SourceSearchPage page)? onSourcePage,
  }) async {
    await ready;
    debug.add(
      page == 1 ? '开始聚合搜索：${query.trim()}' : '开始加载搜索第 $page 页：${query.trim()}',
      category: 'App',
    );
    final enabledSourceIds = _sources
        .where(
          (source) =>
              source.status == SourceStatus.enabled &&
              (sourceIds == null || sourceIds.contains(source.id)),
        )
        .map((source) => source.id)
        .toSet();
    final pages = await registry.searchPage(
      query,
      host,
      page: page,
      enabledSourceIds: enabledSourceIds,
      clearErrors: page == 1,
      onSourcePageCompleted: (_, result) => onSourcePage?.call(result),
    );
    for (final entry in sourceErrors.entries) {
      debug.add(
        '${entry.key} 执行失败：${entry.value}',
        level: DebugLogLevel.error,
        category: 'Source',
      );
    }
    debug.add(
      '搜索第 $page 页完成，结果 ${pages.fold<int>(0, (total, item) => total + item.results.length)} 条',
      category: 'App',
    );
    return pages;
  }

  Future<void> loadDetails(
    AppListing app, {
    required void Function(AppDetailsProgress progress) onProgress,
  }) async {
    await ready;
    return registry.loadDetails(app, host, onProgress: onProgress);
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

  void _handleDownloadNotificationAction(String id, String action) {
    final task = _downloadById(id);
    if (task == null) return;
    switch (action) {
      case 'pause':
        unawaited(pauseDownload(task));
      case 'resume':
        unawaited(resumeDownload(task));
      case 'stop':
        unawaited(cancelDownload(task));
      case 'install':
        unawaited(_installFromNotification(task));
    }
  }

  Future<void> _installFromNotification(DownloadTask task) async {
    try {
      await installTask(task);
    } catch (error) {
      debug.add(
        '通知安装失败：${task.file.label} · $error',
        level: DebugLogLevel.error,
        category: 'Download',
      );
    }
  }

  DownloadTask? downloadFor(String url) {
    for (final task in _downloads) {
      if (task.file.url == url) return task;
    }
    return null;
  }

  DownloadPolicySnapshot _policySnapshot(SourcePolicy policy) =>
      DownloadPolicySnapshot(
        allowedHosts: List<String>.unmodifiable(policy.allowedHosts),
        allowInstall: policy.allowInstall,
      );

  SourcePolicy _policyForTask(DownloadTask task) {
    try {
      return registry.scriptFor(task.sourceId).policy;
    } catch (_) {
      final snapshot = task.policy;
      if (snapshot == null) {
        throw StateError('下载源未恢复，请重新导入源后重试');
      }
      return SourcePolicy(
        allowedHosts: snapshot.allowedHosts.toSet(),
        allowDownload: true,
        allowInstall: snapshot.allowInstall,
      );
    }
  }

  DownloadTask startDownload(
    SourceDownload file,
    String sourceId, {
    AppListing? app,
  }) {
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
    final policySnapshot = _policySnapshot(
      existing == null
          ? registry.scriptFor(sourceId).policy
          : _policyForTask(existing),
    );
    late final DownloadTask task;
    if (existing == null) {
      task = DownloadTask(
        id: '${now.microsecondsSinceEpoch}-${_downloadSequence++}',
        file: file,
        sourceId: sourceId,
        status: DownloadStatus.downloading,
        startedAt: now,
        policy: policySnapshot,
        app: app,
      );
      _downloads.insert(0, task);
    } else {
      task = existing.copyWith(
        status: DownloadStatus.downloading,
        startedAt: now,
        received: 0,
        total: null,
        speedBytesPerSecond: null,
        policy: policySnapshot,
        filePath: null,
        error: null,
        completedAt: null,
        app: app ?? existing.app,
      );
      _replaceDownload(task, notify: false);
    }

    _downloadProgressSamples.remove(task.id);
    _installInfos.remove(task.id);
    _installStateChecks.remove(task.id);
    _scheduleDownloadPersistence();
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
    _downloadProgressSamples.remove(current!.id);
    _replaceDownload(
      current.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSecond: null,
      ),
    );
    debug.add('暂停下载：${current.file.label}', category: 'Download');
    try {
      await host.pauseDownload(current.id);
      final paused = _downloadById(current.id);
      if (paused?.status == DownloadStatus.paused) {
        await _downloadNotifications.showPaused(
          id: paused!.id,
          title: paused.file.label,
          received: paused.received,
          total: paused.total,
        );
      }
    } catch (error) {
      _replaceDownload(
        current.copyWith(
          status: DownloadStatus.downloading,
          speedBytesPerSecond: null,
        ),
      );
      final restored = _downloadById(current.id);
      if (restored != null) {
        unawaited(
          _downloadNotifications.showProgress(
            id: restored.id,
            title: restored.file.label,
            received: restored.received,
            total: restored.total,
          ),
        );
      }
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
    _downloadProgressSamples.remove(current!.id);
    _replaceDownload(
      current.copyWith(
        status: DownloadStatus.downloading,
        speedBytesPerSecond: null,
      ),
    );
    debug.add('继续下载：${current.file.label}', category: 'Download');
    if (!host.hasDownloadSession(current.id)) {
      unawaited(_runDownload(current.id));
      return;
    }
    try {
      await host.resumeDownload(current.id);
      final resumed = _downloadById(current.id);
      if (resumed?.status == DownloadStatus.downloading) {
        unawaited(
          _downloadNotifications.showProgress(
            id: resumed!.id,
            title: resumed.file.label,
            received: resumed.received,
            total: resumed.total,
          ),
        );
      }
    } catch (error) {
      _replaceDownload(current.copyWith(status: DownloadStatus.paused));
      final paused = _downloadById(current.id);
      if (paused != null) {
        unawaited(
          _downloadNotifications.showPaused(
            id: paused.id,
            title: paused.file.label,
            received: paused.received,
            total: paused.total,
          ),
        );
      }
      debug.add(
        '继续下载失败：${current.file.label} · $error',
        level: DebugLogLevel.error,
        category: 'Download',
      );
    }
  }

  Future<void> cancelDownload(DownloadTask task) async {
    final current = _downloadById(task.id);
    if (current == null) return;
    if (current.status != DownloadStatus.downloading &&
        current.status != DownloadStatus.paused) {
      return;
    }
    _removeDownload(current.id);
    debug.add('取消下载：${current.file.label}', category: 'Download');
    await _downloadNotifications.cancel(current.id);
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

  Future<void> deleteDownload(DownloadTask task) async {
    final current = _downloadById(task.id);
    if (current == null ||
        (current.status != DownloadStatus.completed &&
            current.status != DownloadStatus.failed) ||
        _installingDownloads.contains(current.id)) {
      return;
    }

    await _downloadNotifications.cancel(current.id);
    try {
      await host.removeDownloadFiles(current.id, filePath: current.filePath);
    } catch (error) {
      debug.add(
        '删除下载文件失败：${current.file.label} · $error',
        level: DebugLogLevel.warning,
        category: 'Download',
      );
    }
    _removeDownload(current.id);
    debug.add('删除下载：${current.file.label}', category: 'Download');
  }

  Future<void> clearDownloads({required bool completedOnly}) async {
    final targets = _downloads
        .where(
          (task) => !completedOnly || task.status == DownloadStatus.completed,
        )
        .toList(growable: false);
    if (targets.isEmpty) return;

    for (final task in targets) {
      if (task.status != DownloadStatus.downloading &&
          task.status != DownloadStatus.paused) {
        continue;
      }
      await _downloadNotifications.cancel(task.id);
      try {
        await host.cancelDownload(task.id);
      } catch (error) {
        debug.add(
          '清理下载会话失败：${task.file.label} · $error',
          level: DebugLogLevel.warning,
          category: 'Download',
        );
      }
    }

    for (final task in targets) {
      try {
        await host.removeDownloadFiles(task.id, filePath: task.filePath);
      } catch (error) {
        debug.add(
          '删除下载文件失败：${task.file.label} · $error',
          level: DebugLogLevel.warning,
          category: 'Download',
        );
      }
      _removeDownload(task.id, notify: false);
    }
    notifyListeners();
    _scheduleDownloadPersistence(immediate: true);
  }

  Future<void> _runDownload(String taskId) async {
    if (_isDisposing) return;
    final task = _downloadById(taskId);
    if (task == null) return;
    await _downloadNotifications.requestPermission();
    final beforeNotification = _downloadById(task.id);
    if (beforeNotification == null ||
        beforeNotification.status != DownloadStatus.downloading) {
      await _downloadNotifications.cancel(task.id);
      return;
    }
    await _downloadNotifications.showProgress(
      id: task.id,
      title: task.file.label,
      received: beforeNotification.received,
      total: beforeNotification.total,
    );
    final beforeStart = _downloadById(task.id);
    if (beforeStart == null ||
        beforeStart.status != DownloadStatus.downloading) {
      await _downloadNotifications.cancel(task.id);
      return;
    }

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
        policy: _policyForTask(task),
        onProgress: (received, total) =>
            _queueDownloadProgress(task.id, received, total),
      );
      _flushDownloadProgress(task.id);
      final current = _downloadById(task.id);
      if (current == null) return;
      if (current.status == DownloadStatus.canceled) {
        await _downloadNotifications.cancel(task.id);
        return;
      }
      _downloadProgressSamples.remove(task.id);
      final completed = current.copyWith(
        status: DownloadStatus.completed,
        filePath: path,
        speedBytesPerSecond: null,
        error: null,
        completedAt: DateTime.now(),
      );
      _replaceDownload(completed);
      debug.add('下载完成：${task.file.label}', category: 'Download');
      await _downloadNotifications.showCompleted(
        id: task.id,
        title: task.file.label,
      );
    } catch (error) {
      if (_isDisposing) return;
      _flushDownloadProgress(task.id);
      final current = _downloadById(task.id);
      if (current == null) return;
      if (error is DownloadCancelledException) {
        _removeDownload(current.id);
        debug.add('已取消下载：${task.file.label}', category: 'Download');
        await _downloadNotifications.cancel(task.id);
        return;
      }
      _downloadProgressSamples.remove(task.id);
      _replaceDownload(
        current.copyWith(
          status: DownloadStatus.failed,
          speedBytesPerSecond: null,
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
    if (received == null ||
        task == null ||
        task.status != DownloadStatus.downloading) {
      return;
    }

    final now = DateTime.now();
    final previous = _downloadProgressSamples[id];
    final elapsed = previous == null
        ? null
        : now.difference(previous.timestamp).inMilliseconds;
    final delta = previous == null ? null : received - previous.received;
    _downloadProgressSamples[id] = (received: received, timestamp: now);

    final measuredSpeed =
        elapsed != null && elapsed > 0 && delta != null && delta >= 0
        ? (delta * 1000 / elapsed).round()
        : null;
    final speed = measuredSpeed == null
        ? task.speedBytesPerSecond
        : task.speedBytesPerSecond == null
        ? measuredSpeed
        : (task.speedBytesPerSecond! * .7 + measuredSpeed * .3).round();
    final updated = task.copyWith(
      received: received,
      total: total,
      speedBytesPerSecond: speed,
    );
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
    _scheduleDownloadPersistence();
    if (notify) notifyListeners();
  }

  void _removeDownload(String id, {bool notify = true}) {
    final index = _downloads.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _downloadProgressTimers.remove(id)?.cancel();
    _pendingDownloadBytes.remove(id);
    _pendingDownloadTotals.remove(id);
    _downloadProgressSamples.remove(id);
    _installInfos.remove(id);
    _installStateChecks.remove(id);
    _installingDownloads.remove(id);
    _downloads.removeAt(index);
    _scheduleDownloadPersistence();
    if (notify) notifyListeners();
  }

  Future<bool> installTask(DownloadTask task) async {
    await _settingsReady;
    final current = _downloadById(task.id) ?? task;
    final path = current.filePath;
    if (path == null) throw StateError('下载文件尚未完成');
    if (!_installingDownloads.add(current.id)) {
      throw StateError('该安装任务正在进行');
    }
    notifyListeners();
    try {
      final installed = await host.install(
        path,
        policy: _policyForTask(current),
        userInitiated: true,
      );
      if (installed) await refreshInstallState(current);
      return installed;
    } finally {
      _installingDownloads.remove(current.id);
      if (!_isDisposing) notifyListeners();
    }
  }

  Future<bool> install(String path, String sourceId) async {
    await _settingsReady;
    final script = registry.scriptFor(sourceId);
    return host.install(path, policy: script.policy, userInitiated: true);
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

  void setSourcesEnabled(Iterable<String> ids, bool enabled) {
    final sourceIds = ids.toSet();
    if (sourceIds.isEmpty) return;
    var changed = false;
    _sources = _sources.map((source) {
      if (!sourceIds.contains(source.id)) return source;
      final nextStatus = enabled ? SourceStatus.enabled : SourceStatus.disabled;
      if (source.status == nextStatus && (enabled || !source.homeSource)) {
        return source;
      }
      changed = true;
      return source.copyWith(
        status: nextStatus,
        homeSource: enabled ? source.homeSource : false,
      );
    }).toList();
    if (changed) notifyListeners();
  }

  void enableSources(Iterable<String> ids) => setSourcesEnabled(ids, true);

  void disableSources(Iterable<String> ids) => setSourcesEnabled(ids, false);

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
    _isDisposing = true;
    _downloadPersistenceTimer?.cancel();
    _downloadPersistenceTimer = null;
    if (_downloads.isNotEmpty) _persistDownloadsNow();
    for (final timer in _downloadProgressTimers.values) {
      timer.cancel();
    }
    _downloadProgressTimers.clear();
    _downloadProgressSamples.clear();
    for (final task in _downloads) {
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.paused) {
        unawaited(_downloadNotifications.cancel(task.id));
      }
    }
    _translationQueueTimer?.cancel();
    _translationQueueTimer = null;
    translation.dispose();
    unawaited(host.dispose());
    registry.dispose();
    debug.dispose();
    super.dispose();
  }
}
