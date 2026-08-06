import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'source_runtime.dart';

SourceHostApi createPlatformHostApi() => NativeHostApi();

class NativeHostApi implements SourceHostApi {
  static const _installChannel = MethodChannel('com.apkmesh/install');
  final Map<String, HeadlessInAppWebView> _tabs = {};
  final Map<String, InAppWebViewController> _controllers = {};
  final http.Client _client = http.Client();

  bool get _hasHeadlessWebView =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  bool get supportsBrowser => _hasHeadlessWebView;

  @override
  bool get supportsInstall => Platform.isAndroid;

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
    final response = await _getWithRedirects(
      Uri.parse(url),
      policy,
      headers: headers,
    );
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.stream.bytesToString();
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
      final response = await _client.send(request);
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
    final controllerReady = Completer<InAppWebViewController>();
    final pageLoaded = Completer<void>();
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
        if (!controllerReady.isCompleted) controllerReady.complete(controller);
      },
      onLoadStop: (controller, url) {
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
    return tabId;
  }

  InAppWebViewController _controller(String tabId) =>
      _controllers[tabId] ?? (throw StateError('浏览器标签页不存在'));

  @override
  Future<void> browserWaitFor(String tabId, String selector) async {
    final escaped = jsonEncode(selector);
    final controller = _controller(tabId);
    for (var i = 0; i < 100; i++) {
      final exists = await controller.evaluateJavascript(
        source: 'document.querySelector($escaped) != null',
      );
      if (exists == true || exists.toString() == 'true') return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException('等待选择器超时: $selector');
  }

  @override
  Future<Map<String, dynamic>> browserQuery(
    String tabId,
    Map<String, dynamic> selectors,
  ) async {
    final value = await _evaluateQuery(_controller(tabId), null, selectors);
    return value.cast<String, dynamic>();
  }

  @override
  Future<List<Map<String, dynamic>>> browserQueryAll(
    String tabId,
    String rootSelector,
    Map<String, dynamic> selectors,
  ) async {
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
    final tab = _tabs.remove(tabId);
    _controllers.remove(tabId);
    await tab?.dispose();
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
