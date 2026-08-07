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
        SourceManifestProvider,
        DebugProjectSource,
        SourceCatalogScript {
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
              query: (selectors) => sendMessage('apkmesh.browser.query', JSON.stringify({tabId, selectors})),
              queryAll: (rootSelector, selectors) => sendMessage('apkmesh.browser.queryAll', JSON.stringify({tabId, rootSelector, selectors})),
              close: () => sendMessage('apkmesh.browser.close', JSON.stringify({tabId})),
            };
          },
        },
        download: (url, options = {}) => sendMessage('apkmesh.download', JSON.stringify({url, fileName: options.fileName, headers: options.headers || {}})),
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
          'JSON.stringify(typeof source.home === "function" && typeof source.category === "function")',
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
        '(async () => JSON.stringify(await source.$method(${arguments.map(jsonEncode).join(', ')})))()',
      );
      _log('QuickJS call $method completed');
      return result;
    } catch (error) {
      _log('QuickJS call $method failed: $error', level: DebugLogLevel.error);
      rethrow;
    }
  }

  @override
  bool get supportsCatalog => _hasCatalog;

  @override
  Future<SourceHome> home(SourceHostApi host) async {
    final value = await _callWithArguments('home', const [], host);
    final item = _dynamicMap(value);
    return SourceHome(
      recommended: _dynamicList(item['recommended']).map(_listing).toList(),
      categories: _dynamicList(item['categories']).map(_category).toList(),
    );
  }

  @override
  Future<SourceCategory> category(String categoryId, SourceHostApi host) async {
    final value = await _call('category', categoryId, host);
    return _category(_dynamicMap(value));
  }

  @override
  Future<List<AppListing>> search(String query, SourceHostApi host) async {
    final value = await _call('search', query, host);
    return (value as List).map((item) => _listing(_dynamicMap(item))).toList();
  }

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async {
    final value = await _call('details', appId, host);
    return _details(_dynamicMap(value));
  }

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

  SourceCategory _category(Map<String, dynamic> item) => SourceCategory(
    id: (item['id'] ?? item['url'] ?? '').toString(),
    name: (item['name'] ?? '').toString(),
    sourceId: id,
    sourceName: name,
    description: (item['description'] ?? '').toString(),
    apps: _dynamicList(item['apps']).map(_listing).toList(),
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
