import 'models.dart';
import 'debug_log.dart';

class SourcePolicy {
  const SourcePolicy({
    required this.allowedHosts,
    this.allowBrowser = false,
    this.allowDownload = false,
    this.allowInstall = false,
  });

  final Set<String> allowedHosts;
  final bool allowBrowser;
  final bool allowDownload;
  final bool allowInstall;

  bool permits(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    return allowedHosts.any((rule) {
      final normalized = rule.toLowerCase();
      if (normalized.startsWith('*.')) {
        final suffix = normalized.substring(1);
        return host.endsWith(suffix) && host.length > suffix.length;
      }
      return host == normalized;
    });
  }
}

abstract interface class SourceHostApi {
  bool get supportsBrowser;
  bool get supportsInstall;
  List<BrowserTabDebugInfo> get browserTabs;

  Future<String> request(
    String url, {
    Map<String, String> headers = const {},
    required SourcePolicy policy,
  });

  Future<String> browserOpen(String url, {required SourcePolicy policy});
  Future<void> browserWaitFor(String tabId, String selector);
  Future<Map<String, dynamic>> browserQuery(
    String tabId,
    Map<String, dynamic> selectors,
  );
  Future<List<Map<String, dynamic>>> browserQueryAll(
    String tabId,
    String rootSelector,
    Map<String, dynamic> selectors,
  );
  Future<void> browserClose(String tabId);

  Future<String> download(
    String url, {
    String? fileName,
    required SourcePolicy policy,
    void Function(int received, int? total)? onProgress,
  });

  Future<bool> install(String filePath, {required SourcePolicy policy});
  Future<bool> canInstallPackages();
  Future<void> requestInstallPermission();
  Future<void> dispose();
}

abstract interface class ApkSourceScript {
  String get id;
  String get name;
  SourcePolicy get policy;
  Future<List<AppListing>> search(String query, SourceHostApi host);
  Future<AppDetails> details(String appId, SourceHostApi host);
  Future<void> dispose();
}

abstract interface class DebugProjectSource {
  List<SourceDebugProject> get debugProjects;
  Future<DebugProjectResult> runDebugProject(
    SourceDebugProject project,
    String input,
    SourceHostApi host,
  );
}

class SourceRegistry {
  SourceRegistry({List<ApkSourceScript> scripts = const []})
    : scripts = [...scripts];
  final List<ApkSourceScript> scripts;
  final Map<String, String> lastErrors = {};

  void replace(ApkSourceScript script) {
    final index = scripts.indexWhere((item) => item.id == script.id);
    if (index == -1) {
      scripts.add(script);
    } else {
      final previous = scripts[index];
      scripts[index] = script;
      previous.dispose();
    }
  }

  Future<List<AppListing>> search(
    String query,
    SourceHostApi host, {
    Set<String>? enabledSourceIds,
  }) async {
    final results = <AppListing>[];
    lastErrors.clear();
    for (final script in scripts) {
      if (enabledSourceIds != null && !enabledSourceIds.contains(script.id)) {
        continue;
      }
      try {
        results.addAll(await script.search(query, host));
      } catch (error) {
        // A broken source must not suppress successful results from other sources.
        lastErrors[script.name] = error.toString();
      }
    }
    return results;
  }

  Future<AppDetails> details(AppListing app, SourceHostApi host) {
    final script = scripts.firstWhere((item) => item.id == app.sourceId);
    return script.details(app.id, host);
  }

  ApkSourceScript scriptFor(String sourceId) =>
      scripts.firstWhere((item) => item.id == sourceId);

  List<SourceDebugProject> get debugProjects => scripts
      .whereType<DebugProjectSource>()
      .expand((script) => script.debugProjects)
      .toList(growable: false);

  Future<DebugProjectResult> runDebugProject(
    SourceDebugProject project,
    String input,
    SourceHostApi host,
  ) {
    final script = scriptFor(project.sourceId);
    if (script is! DebugProjectSource) {
      throw UnsupportedError('源未声明调试项目');
    }
    return (script as DebugProjectSource).runDebugProject(project, input, host);
  }

  Future<void> dispose() async {
    for (final script in scripts) {
      await script.dispose();
    }
  }
}

class DemoHostApi implements SourceHostApi {
  @override
  List<BrowserTabDebugInfo> get browserTabs => const [];

  @override
  bool get supportsBrowser => false;

  @override
  bool get supportsInstall => false;

  @override
  Future<String> browserOpen(String url, {required SourcePolicy policy}) =>
      throw UnsupportedError('当前平台不支持隐藏浏览器');

  @override
  Future<void> browserWaitFor(String tabId, String selector) =>
      throw UnsupportedError('当前平台不支持隐藏浏览器');

  @override
  Future<Map<String, dynamic>> browserQuery(
    String tabId,
    Map<String, dynamic> selectors,
  ) => throw UnsupportedError('当前平台不支持隐藏浏览器');

  @override
  Future<List<Map<String, dynamic>>> browserQueryAll(
    String tabId,
    String rootSelector,
    Map<String, dynamic> selectors,
  ) => throw UnsupportedError('当前平台不支持隐藏浏览器');

  @override
  Future<void> browserClose(String tabId) async {}

  @override
  Future<String> download(
    String url, {
    String? fileName,
    required SourcePolicy policy,
    void Function(int received, int? total)? onProgress,
  }) => throw UnsupportedError('当前平台不支持文件下载');

  @override
  Future<bool> install(String filePath, {required SourcePolicy policy}) async =>
      false;

  @override
  Future<bool> canInstallPackages() async => false;

  @override
  Future<void> requestInstallPermission() async {}

  @override
  Future<String> request(
    String url, {
    Map<String, String> headers = const {},
    required SourcePolicy policy,
  }) => throw UnsupportedError('当前平台不支持源网络请求');

  @override
  Future<void> dispose() async {}
}

class ApkVisionDemoScript implements ApkSourceScript {
  @override
  String get id => 'apkvision-demo';

  @override
  String get name => 'APKVision（测试源）';

  @override
  SourcePolicy get policy => const SourcePolicy(
    allowedHosts: {'apkvision.org', '*.apkvision.org'},
    allowBrowser: true,
    allowDownload: true,
  );

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async => _detail;

  @override
  Future<List<AppListing>> search(String query, SourceHostApi host) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return [_detail]
        .where(
          (app) =>
              app.name.toLowerCase().contains(normalized) ||
              app.packageName.contains(normalized),
        )
        .toList();
  }

  @override
  Future<void> dispose() async {}

  static const _detail = AppDetails(
    id: 'https://apkvision.org/games/arcade/minecraft-pe-apk-55409/',
    sourceId: 'apkvision-demo',
    name: 'Minecraft',
    packageName: 'com.mojang.minecraftpe',
    version: '1.26.50.24 Beta',
    size: '1000.1 MB',
    updatedAt: 'August 5, 2026',
    category: 'Arcade',
    sourceName: 'APKVision（测试源）',
    iconUrl:
        'https://apkvision.org/wp-content/uploads/2020/01/minecraft-play-with-friends.png',
    summary: 'Minecraft APK free download from APKVision.',
    description: '这是一个用于验证 APKVision 搜索、详情和下载接口的测试条目。',
    screenshots: [
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-1.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-2.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-3.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-4.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-5.webp',
    ],
    comments: ['请在安装前自行校验文件来源与签名。'],
    downloads: [
      SourceDownload(
        label: 'Minecraft APK v1.26.50.24 Beta',
        url:
            'https://apkvision.org/games/arcade/minecraft-pe-apk-55409/download/v1.26.50.24-beta-apk/',
        size: '1000.1 MB',
      ),
    ],
  );
}
