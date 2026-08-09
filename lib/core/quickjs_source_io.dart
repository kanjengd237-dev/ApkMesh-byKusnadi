import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';

import 'models.dart';
import 'source_runtime.dart';
import 'debug_log.dart';

Future<List<String>> discoverSourceAssets() async {
  if (!Platform.isAndroid) return const [];
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final paths = manifest
      .listAssets()
      .where(
        (path) => path.startsWith('assets/sources/') && path.endsWith('.js'),
      )
      .toList();
  paths.sort();
  return paths;
}

Future<ApkSourceScript?> loadQuickJsSourceText(
  String scriptText, {
  required String sourceUrl,
  DebugLogStore? debug,
}) async {
  if (!Platform.isAndroid) return null;
  final source = QuickJsApkSourceScript(
    scriptText,
    sourceUrl: sourceUrl,
    debug: debug,
  );
  await source.initialize();
  return source;
}

Future<ApkSourceScript?> loadQuickJsSource(
  String assetPath, {
  DebugLogStore? debug,
}) async {
  // QuickJS is used for the Android runtime; other native platforms retain the demo source.
  if (!Platform.isAndroid) return null;
  final script = await rootBundle.loadString(assetPath);
  final source = QuickJsApkSourceScript(
    script,
    sourceUrl: assetPath,
    debug: debug,
  );
  await source.initialize();
  return source;
}

class QuickJsApkSourceScript
    implements
        ApkSourceScript,
        SourceDetailProgressScript,
        SourceManifestProvider,
        DebugProjectSource,
        SourceCatalogScript,
        SourcePackageLookupScript {
  static const _legacyRecommendedTabId = '__apkmesh_legacy_recommended__';

  QuickJsApkSourceScript(this.scriptText, {String? sourceUrl, this._debug})
    : _sourceUrl = sourceUrl ?? 'quickjs-source.js' {
    _runtime = getJavascriptRuntime(forceJavascriptCoreOnAndroid: false);
    _installBridge();
  }

  final String scriptText;
  final String _sourceUrl;
  final DebugLogStore? _debug;
  late final JavascriptRuntime _runtime;
  late final SourcePolicy _policy;
  String? _sourceId;
  String? _sourceName;
  String? _sourceVersion;
  String? _sourceHomepage;
  String? _sourceDescription;
  List<SourceDebugProject> _debugProjects = const [];
  SourceHostApi? _host;
  bool _hasCatalog = false;
  bool _hasLegacyCatalog = false;
  bool _hasPackageLookup = false;
  bool _hasDetailProgress = false;
  List<AppListing> _legacyRecommended = const [];
  final Map<String, List<AppListing>> _legacyCatalogPages = {};
  final Map<String, void Function(Map<String, dynamic> payload)>
  _detailProgressCallbacks = {};
  bool _disposed = false;

  @override
  String get version => _sourceVersion ?? '0.0.0';

  @override
  String get homepage => _sourceHomepage ?? '';

  @override
  String get description => _sourceDescription ?? '内置 QuickJS 源';

  void _log(String message, {DebugLogLevel level = DebugLogLevel.info}) {
    debugPrint('[APK Mesh] $message');
    _debug?.add(message, level: level, category: 'QuickJS');
  }

  Future<void> initialize() => _evaluateScript();

  @override
  String get id => _sourceId ?? 'quickjs-source';

  @override
  String get name => _sourceName ?? 'QuickJS 源';

  @override
  SourcePolicy get policy => _policy;

  void _installBridge() {
    _runtime.onMessage('apkmesh.request', (args) async {
      final payload = _payload(args);
      final body = await _host!.request(
        payload['url'] as String,
        headers: _stringMap(payload['headers']),
        policy: _policy,
      );
      return body;
    });
    _runtime.onMessage('apkmesh.browser.open', (args) async {
      final payload = _payload(args);
      return _host!.browserOpen(payload['url'] as String, policy: _policy);
    });
    _runtime.onMessage('apkmesh.browser.waitFor', (args) async {
      final payload = _payload(args);
      await _host!.browserWaitFor(
        payload['tabId'] as String,
        payload['selector'] as String,
      );
      return true;
    });
    _runtime.onMessage('apkmesh.browser.waitForUrlChange', (args) async {
      final payload = _payload(args);
      return _host!.browserWaitForUrlChange(
        payload['tabId'] as String,
        payload['previousUrl'] as String,
      );
    });
    _runtime.onMessage('apkmesh.browser.query', (args) async {
      final payload = _payload(args);
      return _host!.browserQuery(
        payload['tabId'] as String,
        _dynamicMap(payload['selectors']),
      );
    });
    _runtime.onMessage('apkmesh.browser.queryAll', (args) async {
      final payload = _payload(args);
      return _host!.browserQueryAll(
        payload['tabId'] as String,
        payload['rootSelector'] as String,
        _dynamicMap(payload['selectors']),
      );
    });
    _runtime.onMessage('apkmesh.browser.close', (args) async {
      await _host!.browserClose(_payload(args)['tabId'] as String);
      return true;
    });
    _runtime.onMessage('apkmesh.download', (args) async {
      final payload = _payload(args);
      return _host!.download(
        payload['url'] as String,
        headers: _stringMap(payload['headers']),
        fileName: payload['fileName'] as String?,
        policy: _policy,
      );
    });
    _runtime.onMessage('apkmesh.detailProgress', (args) {
      final payload = _payload(args);
      final requestId = payload['requestId']?.toString() ?? '';
      final update = _dynamicMap(payload['update']);
      final callback = _detailProgressCallbacks[requestId];
      callback?.call(update);
      return true;
    });
    _runtime.onMessage('apkmesh.install', (args) async {
      final payload = _payload(args);
      return _host!.install(payload['filePath'] as String, policy: _policy);
    });
  }

  Map<String, dynamic> _payload(dynamic args) {
    if (args is String) {
      return (jsonDecode(args) as Map).cast<String, dynamic>();
    }
    if (args is Map) return args.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Map<String, String> _stringMap(dynamic value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item.toString()))
      : <String, String>{};
  Map<String, dynamic> _dynamicMap(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

  Future<void> _evaluateScript() async {
    final bootstrap = '''
      globalThis.apkmesh = {
        request: (url, options = {}) => sendMessage('apkmesh.request', JSON.stringify({url, headers: options.headers || {}})),
        browser: {
          open: async (url) => {
            const tabId = await sendMessage('apkmesh.browser.open', JSON.stringify({url}));
            return {
              id: tabId,
              waitFor: (selector) => sendMessage('apkmesh.browser.waitFor', JSON.stringify({tabId, selector})),
              waitForUrlChange: (previousUrl) => sendMessage('apkmesh.browser.waitForUrlChange', JSON.stringify({tabId, previousUrl})),
              query: (selectors) => sendMessage('apkmesh.browser.query', JSON.stringify({tabId, selectors})),
              queryAll: (rootSelector, selectors) => sendMessage('apkmesh.browser.queryAll', JSON.stringify({tabId, rootSelector, selectors})),
              close: () => sendMessage('apkmesh.browser.close', JSON.stringify({tabId})),
            };
          },
        },
        download: (url, options = {}) => sendMessage('apkmesh.download', JSON.stringify({url, fileName: options.fileName, headers: options.headers || {}})),
        detailProgress: (requestId, update) => sendMessage(
          'apkmesh.detailProgress',
          JSON.stringify({requestId, update}),
        ),
        install: (filePath) => sendMessage('apkmesh.install', JSON.stringify({filePath})),
      };
    ''';
    _runtime.evaluate(bootstrap);
    _runtime.evaluate(scriptText, sourceUrl: _sourceUrl);
    final manifestResult = await _evaluateJson(
      'JSON.stringify(source.manifest)',
    );
    final manifest = (manifestResult as Map).cast<String, dynamic>();
    _sourceId = manifest['id'] as String?;
    _sourceName = manifest['name'] as String?;
    _sourceVersion = manifest['version']?.toString();
    _sourceHomepage = manifest['homepage']?.toString();
    _sourceDescription = manifest['description']?.toString();
    _debugProjects = _parseDebugProjects(manifest['debugProjects']);
    final permissions = _dynamicMap(manifest['permissions']);
    _hasCatalog =
        await _evaluateJson(
          'JSON.stringify(typeof source.catalog === "function" && typeof source.catalogPage === "function")',
        ) ==
        true;
    _hasLegacyCatalog =
        await _evaluateJson(
          'JSON.stringify(typeof source.home === "function" && typeof source.category === "function")',
        ) ==
        true;
    _hasDetailProgress =
        await _evaluateJson(
          'JSON.stringify(typeof source.detailsMetadata === "function" && typeof source.resolveDownloads === "function")',
        ) ==
        true;
    _hasPackageLookup =
        manifest['packageLookup'] == true &&
        await _evaluateJson(
              'JSON.stringify(typeof source.packageLookupUrl === "function")',
            ) ==
            true;
    final hosts = (permissions['network'] as List? ?? const [])
        .map((item) => item.toString())
        .toSet();
    _policy = SourcePolicy(
      allowedHosts: hosts,
      allowBrowser: permissions['browser'] == true,
      allowDownload: permissions['download'] == true,
      allowInstall: permissions['install'] == true,
    );
  }

  List<SourceDebugProject> _parseDebugProjects(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) {
              final project = item.cast<String, dynamic>();
              return SourceDebugProject(
                sourceId: id,
                sourceName: name,
                id: (project['id'] ?? '').toString(),
                name: (project['name'] ?? '').toString(),
                description: (project['description'] ?? '').toString(),
                inputLabel: (project['inputLabel'] ?? '输入').toString(),
                placeholder: (project['placeholder'] ?? '').toString(),
                defaultInput: (project['defaultInput'] ?? '').toString(),
              );
            })
            .where((project) => project.id.isNotEmpty)
            .toList()
      : const [];

  @override
  List<SourceDebugProject> get debugProjects => _debugProjects;

  @override
  Future<DebugProjectResult> runDebugProject(
    SourceDebugProject project,
    String input,
    SourceHostApi host,
  ) async {
    final value = await _callWithArguments('debug', [project.id, input], host);
    final result = _dynamicMap(value);
    return DebugProjectResult(
      projectId: project.id,
      sourceId: id,
      title: (result['title'] ?? project.name).toString(),
      summary: (result['summary'] ?? '调试项目执行完成').toString(),
      data: result['data'] ?? value,
    );
  }

  Future<dynamic> _evaluateJson(String expression) async {
    var result = await _runtime.evaluateAsync(
      expression,
      sourceUrl: _sourceUrl,
    );
    _runtime.executePendingJob();
    if (result.stringResult == '[object Promise]' ||
        result.stringResult.contains("Instance of 'Future")) {
      result = await _runtime
          .handlePromise(result)
          .timeout(const Duration(minutes: 2));
    }
    final value = result.stringResult;
    final decoded = jsonDecode(value);
    if (decoded is String) {
      final nested = decoded.trimLeft();
      if (nested.startsWith('{') || nested.startsWith('[')) {
        return jsonDecode(decoded);
      }
    }
    return decoded;
  }

  Future<dynamic> _call(String method, dynamic argument, SourceHostApi host) =>
      _callWithArguments(method, [argument], host);

  Future<dynamic> _callWithArguments(
    String method,
    List<dynamic> arguments,
    SourceHostApi host,
  ) async {
    if (_disposed) throw StateError('源已释放');
    _host = host;
    _log('QuickJS call $method');
    if (_sourceId == null) {
      await _evaluateScript();
    }
    try {
      final result = await _evaluateJson(
        '(async () => { '
        'const value = await source.$method(${arguments.map(jsonEncode).join(', ')}); '
        'return JSON.stringify({__apkmeshResult: value === undefined ? null : value}); '
        '})()',
      );
      if (result is! Map || !result.containsKey('__apkmeshResult')) {
        throw const FormatException('QuickJS 调用结果格式无效');
      }
      final value = result['__apkmeshResult'];
      _log('QuickJS call $method completed');
      return value;
    } catch (error) {
      _log('QuickJS call $method failed: $error', level: DebugLogLevel.error);
      rethrow;
    }
  }

  @override
  bool get supportsCatalog => _hasCatalog || _hasLegacyCatalog;

  @override
  Future<SourceCatalog> catalog(SourceHostApi host) async {
    if (_hasCatalog) {
      final value = await _callWithArguments('catalog', const [], host);
      final item = _dynamicMap(value);
      final tabs = _dynamicList(item['tabs'])
          .map(_catalogTab)
          .where((tab) => tab.id.isNotEmpty && tab.name.isNotEmpty)
          .toList(growable: false);
      final requestedDefault = item['defaultTabId']?.toString().trim();
      final defaultTabId = tabs.any((tab) => tab.id == requestedDefault)
          ? requestedDefault
          : tabs.firstOrNull?.id;
      return SourceCatalog(tabs: tabs, defaultTabId: defaultTabId);
    }

    final value = await _callWithArguments('home', const [], host);
    final item = _dynamicMap(value);
    _legacyRecommended = _dynamicList(
      item['recommended'],
    ).map(_listing).toList(growable: false);
    _legacyCatalogPages.clear();
    final tabs = <SourceCatalogTab>[];
    if (_legacyRecommended.isNotEmpty) {
      tabs.add(
        SourceCatalogTab(
          id: _legacyRecommendedTabId,
          name: '推荐',
          sourceId: id,
          sourceName: name,
          paged: false,
        ),
      );
    }
    for (final value in _dynamicList(item['categories'])) {
      final category = _dynamicMap(value);
      final tab = _catalogTab(category, paged: false);
      if (tab.id.isEmpty || tab.name.isEmpty) continue;
      tabs.add(tab);
      final apps = _dynamicList(
        category['apps'],
      ).map(_listing).toList(growable: false);
      if (apps.isNotEmpty) _legacyCatalogPages[tab.id] = apps;
    }
    return SourceCatalog(tabs: tabs, defaultTabId: tabs.firstOrNull?.id);
  }

  @override
  Future<SourceCatalogPage> catalogPage(
    String tabId,
    SourceHostApi host, {
    int page = 1,
  }) async {
    if (_hasCatalog) {
      final value = await _callWithArguments('catalogPage', [
        tabId,
        page,
      ], host);
      final item = _dynamicMap(value);
      return SourceCatalogPage(
        tabId: tabId,
        sourceId: id,
        sourceName: name,
        page: page,
        apps: _dynamicList(item['apps']).map(_listing).toList(growable: false),
        hasMore: item['hasMore'] == true,
      );
    }

    if (page > 1) {
      return SourceCatalogPage(
        tabId: tabId,
        sourceId: id,
        sourceName: name,
        page: page,
        apps: const [],
        hasMore: false,
      );
    }
    if (tabId == _legacyRecommendedTabId) {
      return SourceCatalogPage(
        tabId: tabId,
        sourceId: id,
        sourceName: name,
        page: page,
        apps: _legacyRecommended,
        hasMore: false,
      );
    }
    var apps = _legacyCatalogPages[tabId];
    if (apps == null) {
      final value = await _call('category', tabId, host);
      apps = _dynamicList(
        _dynamicMap(value)['apps'],
      ).map(_listing).toList(growable: false);
      _legacyCatalogPages[tabId] = apps;
    }
    return SourceCatalogPage(
      tabId: tabId,
      sourceId: id,
      sourceName: name,
      page: page,
      apps: apps,
      hasMore: false,
    );
  }

  @override
  bool get supportsPackageLookup => _hasPackageLookup;

  @override
  Future<String?> packageLookupUrl(
    String packageName,
    SourceHostApi host,
  ) async {
    final value = await _callWithArguments('packageLookupUrl', [
      packageName,
    ], host);
    final url = value?.toString().trim() ?? '';
    return url.isEmpty ? null : url;
  }

  @override
  Future<List<AppListing>> search(
    String query,
    SourceHostApi host, {
    int page = 1,
  }) async {
    final value = await _callWithArguments('search', [query, page], host);
    return (value as List).map((item) => _listing(_dynamicMap(item))).toList();
  }

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async {
    final value = await _call('details', appId, host);
    return _details(_dynamicMap(value));
  }

  @override
  bool get supportsDetailProgress => _hasDetailProgress;

  @override
  Future<SourceDetailsMetadata> detailsMetadata(
    String appId,
    SourceHostApi host,
  ) async {
    final value = await _call('detailsMetadata', appId, host);
    final item = _dynamicMap(value);
    return SourceDetailsMetadata(
      details: _details(item),
      downloads: _dynamicList(item['downloadCandidates'])
          .map(_candidate)
          .where((candidate) => candidate.url.isNotEmpty)
          .toList(growable: false),
    );
  }

  @override
  Future<List<SourceDownload>> resolveDownloads(
    List<SourceDownloadCandidate> candidates,
    SourceHostApi host, {
    required void Function(
      int index,
      List<SourceDownload>? files,
      String? error,
    )
    onProgress,
  }) async {
    if (!_hasDetailProgress) {
      throw UnsupportedError('源未声明分阶段详情能力');
    }
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    _detailProgressCallbacks[requestId] = (update) {
      final index = int.tryParse(update['index']?.toString() ?? '');
      if (index == null) return;
      final rawDownloads = update['downloads'];
      final files = rawDownloads is List
          ? rawDownloads
                .whereType<Map>()
                .map((item) => _download(item.cast<String, dynamic>()))
                .toList(growable: false)
          : update['download'] is Map
          ? [_download(_dynamicMap(update['download']))]
          : null;
      final error = update['error']?.toString();
      onProgress(index, files, error?.isEmpty == true ? null : error);
    };
    try {
      final value = await _callWithArguments('resolveDownloads', [
        candidates.map((candidate) => candidate.toJson()).toList(),
        requestId,
      ], host);
      return _dynamicList(value).map(_download).toList(growable: false);
    } finally {
      _detailProgressCallbacks.remove(requestId);
    }
  }

  SourceDownloadCandidate _candidate(Map<String, dynamic> item) =>
      SourceDownloadCandidate(
        label: (item['label'] ?? '').toString(),
        url: (item['url'] ?? '').toString(),
        size: (item['size'] ?? '').toString(),
        headers: _stringMap(item['headers']),
      );

  SourceDownload _download(Map<String, dynamic> item) => SourceDownload(
    label: (item['label'] ?? '').toString(),
    url: (item['url'] ?? '').toString(),
    size: (item['size'] ?? '').toString(),
    headers: _stringMap(item['headers']),
  );

  String _firstText(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  AppListing _listing(Map<String, dynamic> item) => AppListing(
    id: (item['id'] ?? item['url'] ?? '').toString(),
    sourceId: id,
    name: (item['name'] ?? '').toString(),
    packageName: (item['packageName'] ?? '').toString(),
    version: (item['version'] ?? '').toString(),
    size: (item['size'] ?? '').toString(),
    updatedAt: (item['updatedAt'] ?? '').toString(),
    category: (item['category'] ?? '').toString(),
    sourceName: name,
    iconUrl: (item['iconUrl'] ?? '').toString(),
    description: _firstText(item, ['description', 'desc', 'info']),
    rating: _firstText(item, ['rating', 'score']),
    author: _firstText(item, ['author', 'developer']),
  );

  SourceCatalogTab _catalogTab(Map<String, dynamic> item, {bool? paged}) =>
      SourceCatalogTab(
        id: (item['id'] ?? item['url'] ?? '').toString(),
        name: (item['name'] ?? '').toString(),
        sourceId: id,
        sourceName: name,
        paged: paged ?? item['paged'] == true,
        description: (item['description'] ?? '').toString(),
      );

  AppDetails _details(Map<String, dynamic> item) => AppDetails(
    id: (item['id'] ?? item['url'] ?? '').toString(),
    sourceId: id,
    name: (item['name'] ?? '').toString(),
    packageName: (item['packageName'] ?? '').toString(),
    version: (item['version'] ?? '').toString(),
    size: (item['size'] ?? '').toString(),
    updatedAt: (item['updatedAt'] ?? '').toString(),
    category: (item['category'] ?? '').toString(),
    sourceName: name,
    iconUrl: (item['iconUrl'] ?? '').toString(),
    summary: (item['summary'] ?? '').toString(),
    description: _firstText(item, ['description', 'desc', 'info']),
    rating: _firstText(item, ['rating', 'score']),
    author: _firstText(item, ['author', 'developer']),
    screenshots: _strings(item['screenshots']),
    comments: _strings(item['comments']),
    downloads: _dynamicList(item['downloads'])
        .map(
          (download) => SourceDownload(
            label: (download['label'] ?? '').toString(),
            url: (download['url'] ?? '').toString(),
            size: (download['size'] ?? '').toString(),
            headers: _stringMap(download['headers']),
          ),
        )
        .toList(),
  );

  List<String> _strings(dynamic value) => value is List
      ? value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
      : const [];
  List<Map<String, dynamic>> _dynamicList(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList()
      : const [];

  @override
  Future<void> dispose() async {
    _disposed = true;
    _runtime.dispose();
  }
}
