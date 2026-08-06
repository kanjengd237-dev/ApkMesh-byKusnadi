import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'source_runtime.dart';

SourceHostApi createPlatformHostApi({DebugLogStore? debug}) =>
    NativeHostApi(debug: debug);

class NativeHostApi implements SourceHostApi {
  NativeHostApi({this._debug});

  static const _installChannel = MethodChannel('com.apkmesh/install');
  final DebugLogStore? _debug;
  final Map<String, HeadlessInAppWebView> _tabs = {};
  final Map<String, InAppWebViewController> _controllers = {};
  final Map<String, BrowserTabDebugInfo> _tabStates = {};
  final List<BrowserTabDebugInfo> _tabHistory = [];
  final http.Client _client = http.Client();

  bool get _hasHeadlessWebView =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  bool get supportsBrowser => _hasHeadlessWebView;

  @override
  bool get supportsInstall => Platform.isAndroid;

  @override
  List<BrowserTabDebugInfo> get browserTabs => [
    ..._tabStates.values,
    ..._tabHistory,
  ];

  void _log(
    String message, {
    DebugLogLevel level = DebugLogLevel.info,
    String category = 'Host',
  }) {
    debugPrint('[APK Mesh] $message');
    _debug?.add(message, level: level, category: category);
  }

  void _setTabState(
    String tabId, {
    String? url,
    required String state,
    bool active = true,
  }) {
    final current = _tabStates[tabId];
    if (current == null) return;
    final snapshot = current.copyWith(url: url, state: state, active: active);
    if (active) {
      _tabStates[tabId] = snapshot;
    } else {
      _tabStates.remove(tabId);
      _tabHistory.insert(0, snapshot);
      if (_tabHistory.length > 20) _tabHistory.removeLast();
    }
    _log('WebView ${active ? state : 'closed'} $tabId ${snapshot.url}');
  }

  void _check(Uri uri, SourcePolicy policy, {required bool capability}) {
    if (!capability) throw UnsupportedError('该源没有请求此能力');
    if (!policy.permits(uri)) {
      throw StateError('源权限拒绝访问 ${uri.host}');
    }
  }

  @override
  Future<String> request(
    String url, {
    Map<String, String> headers = const {},
    required SourcePolicy policy,
  }) async {
    _log('HTTP $url', category: 'HTTP');
    try {
      final response = await _getWithRedirects(
        Uri.parse(url),
        policy,
        headers: headers,
      );
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      _log('HTTP $url -> ${response.statusCode}', category: 'HTTP');
      return response.stream.bytesToString();
    } catch (error) {
      _log(
        'HTTP $url failed: $error',
        level: DebugLogLevel.error,
        category: 'HTTP',
      );
      rethrow;
    }
  }

  Future<http.StreamedResponse> _getWithRedirects(
    Uri initialUri,
    SourcePolicy policy, {
    Map<String, String> headers = const {},
  }) async {
    var uri = initialUri;
    for (var redirects = 0; redirects < 6; redirects++) {
      _check(uri, policy, capability: true);
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }
      await response.stream.drain<void>();
      final location = response.headers['location'];
      if (location == null) throw HttpException('重定向缺少 Location', uri: uri);
      uri = uri.resolve(location);
    }
    throw HttpException('重定向次数过多', uri: uri);
  }

  @override
  Future<String> browserOpen(String url, {required SourcePolicy policy}) async {
    final uri = Uri.parse(url);
    _check(uri, policy, capability: policy.allowBrowser);
    if (!_hasHeadlessWebView) {
      throw UnsupportedError('Linux/Windows 当前没有隐藏 WebView 实现');
    }

    final tabId = DateTime.now().microsecondsSinceEpoch.toString();
    _tabStates[tabId] = BrowserTabDebugInfo(
      id: tabId,
      url: url,
      state: 'starting',
      startedAt: DateTime.now(),
    );
    _log('WebView opening $tabId $url');
    final controllerReady = Completer<InAppWebViewController>();
    final pageLoaded = Completer<void>();
    var loaded = false;
    late final HeadlessInAppWebView tab;
    tab = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        incognito: true,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        userAgent: 'APKMesh/0.1 (+https://github.com/apkmesh/apkmesh)',
      ),
      initialUrlRequest: URLRequest(url: WebUri(uri.toString())),
      onWebViewCreated: (controller) {
        _controllers[tabId] = controller;
        _setTabState(tabId, state: 'created');
        if (!controllerReady.isCompleted) controllerReady.complete(controller);
      },
      onLoadStop: (controller, url) {
        loaded = true;
        _setTabState(tabId, url: url?.toString(), state: 'ready');
        if (!pageLoaded.isCompleted) pageLoaded.complete();
      },
      shouldOverrideUrlLoading: (_, action) async {
        final next = action.request.url;
        if (next == null || !policy.permits(next)) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      shouldInterceptRequest: (_, request) async {
        final resource = request.url;
        if ((resource.scheme == 'http' || resource.scheme == 'https') &&
            !policy.permits(resource)) {
          return WebResourceResponse(
            statusCode: 403,
            reasonPhrase: 'Source domain is not allowed',
            contentType: 'text/plain',
            data: Uint8List.fromList(utf8.encode('blocked by source policy')),
          );
        }
        return null;
      },
    );
    _tabs[tabId] = tab;
    await tab.run();
    await controllerReady.future.timeout(const Duration(seconds: 15));
    await pageLoaded.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {},
    );
    if (!loaded) _setTabState(tabId, state: 'load-timeout');
    return tabId;
  }

  InAppWebViewController _controller(String tabId) =>
      _controllers[tabId] ?? (throw StateError('浏览器标签页不存在'));

  @override
  Future<void> browserWaitFor(String tabId, String selector) async {
    _setTabState(tabId, state: 'waiting: $selector');
    final escaped = jsonEncode(selector);
    final controller = _controller(tabId);
    for (var i = 0; i < 100; i++) {
      final exists = await controller.evaluateJavascript(
        source: 'document.querySelector($escaped) != null',
      );
      if (exists == true || exists.toString() == 'true') {
        _setTabState(tabId, state: 'ready');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _setTabState(tabId, state: 'wait-timeout');
    throw TimeoutException('等待选择器超时: $selector');
  }

  @override
  Future<Map<String, dynamic>> browserQuery(
    String tabId,
    Map<String, dynamic> selectors,
  ) async {
    _log('WebView query $tabId', category: 'WebView');
    final value = await _evaluateQuery(_controller(tabId), null, selectors);
    return value.cast<String, dynamic>();
  }

  @override
  Future<List<Map<String, dynamic>>> browserQueryAll(
    String tabId,
    String rootSelector,
    Map<String, dynamic> selectors,
  ) async {
    _log('WebView queryAll $tabId $rootSelector', category: 'WebView');
    final result = await _evaluateQueryAll(
      _controller(tabId),
      rootSelector,
      selectors,
    );
    return result;
  }

  Future<dynamic> _evaluateQuery(
    InAppWebViewController controller,
    String? root,
    Map<String, dynamic> selectors,
  ) async {
    final expression = _queryExpression(
      selectors,
      rootExpression: root ?? 'document',
    );
    final value = await controller.evaluateJavascript(source: expression);
    return value is String ? jsonDecode(value) : (value ?? <String, dynamic>{});
  }

  Future<List<Map<String, dynamic>>> _evaluateQueryAll(
    InAppWebViewController controller,
    String rootSelector,
    Map<String, dynamic> selectors,
  ) async {
    final expression =
        '''(() => Array.from(document.querySelectorAll(${jsonEncode(rootSelector)})).map(root => ${_queryExpression(selectors, rootExpression: 'root')}))()''';
    final value = await controller.evaluateJavascript(source: expression);
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  String _queryExpression(
    Map<String, dynamic> selectors, {
    required String rootExpression,
  }) {
    final entries = selectors.entries
        .map((entry) {
          final selector = entry.value is List
              ? entry.value.first.toString()
              : entry.value.toString();
          final parts = selector.split('@');
          final cssValue = parts.first.trim();
          final element = cssValue.isEmpty
              ? rootExpression
              : '$rootExpression.querySelector(${jsonEncode(cssValue)})';
          final attrValue = parts.length > 1
              ? parts.sublist(1).join('@').trim()
              : null;
          final attr = attrValue == null ? 'null' : jsonEncode(attrValue);
          return '${jsonEncode(entry.key)}: (() => { const el = $element; if (!el) return null; return $attr === null || $attr === "text" ? (el.textContent || "").trim() : (el.getAttribute($attr) || "").trim(); })()';
        })
        .join(',');
    return '''(() => JSON.stringify({$entries}))()''';
  }

  @override
  Future<void> browserClose(String tabId) async {
    _log('WebView closing $tabId', category: 'WebView');
    final tab = _tabs.remove(tabId);
    _controllers.remove(tabId);
    await tab?.dispose();
    _setTabState(tabId, state: 'closed', active: false);
  }

  @override
  Future<String> download(
    String url, {
    String? fileName,
    required SourcePolicy policy,
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    _check(uri, policy, capability: policy.allowDownload);
    final directory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    final requestedName = fileName ?? p.basename(uri.path).split('?').first;
    final safeName = requestedName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File(
      p.join(directory.path, safeName.isEmpty ? 'download.apk' : safeName),
    );
    final response = await _getWithRedirects(uri, policy);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('下载失败 HTTP ${response.statusCode}', uri: uri);
    }
    final sink = destination.openWrite();
    var received = 0;
    await response.stream.listen((chunk) {
      received += chunk.length;
      sink.add(chunk);
      onProgress?.call(received, response.contentLength);
    }).asFuture<void>();
    await sink.close();
    return destination.path;
  }

  @override
  Future<bool> install(String filePath, {required SourcePolicy policy}) async {
    if (!policy.allowInstall) throw StateError('源未声明安装权限');
    if (!supportsInstall) throw UnsupportedError('当前平台不支持 APK 安装');
    if (!await canInstallPackages()) {
      await requestInstallPermission();
      return false;
    }
    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }

  @override
  Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return false;
    return await _installChannel.invokeMethod<bool>('canInstallPackages') ??
        false;
  }

  @override
  Future<void> requestInstallPermission() async {
    if (!Platform.isAndroid) return;
    await _installChannel.invokeMethod<void>('requestInstallPermission');
  }

  @override
  Future<void> dispose() async {
    for (final id in _tabs.keys.toList()) {
      await browserClose(id);
    }
    _client.close();
  }
}
