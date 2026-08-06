import 'models.dart';

/// Capabilities exposed to a QuickJS source. Implementations are platform-specific.
abstract interface class SourceHostApi {
  Future<String> request(String url, {Map<String, String> headers = const {}});
  Future<String> browse(String url);
  Future<String> download(String url, {String? fileName});
  Future<bool> install(String filePath);
}

abstract interface class ApkSourceScript {
  String get id;
  Future<List<AppListing>> search(String query, SourceHostApi host);
  Future<AppDetails> details(String appId, SourceHostApi host);
}

/// The bridge is intentionally small so a QuickJS engine can be swapped in later.
class SourceRegistry {
  SourceRegistry({List<ApkSourceScript> scripts = const []})
    : scripts = [...scripts];
  final List<ApkSourceScript> scripts;

  Future<List<AppListing>> search(
    String query,
    SourceHostApi host, {
    Set<String>? enabledSourceIds,
  }) async {
    final results = <AppListing>[];
    for (final script in scripts) {
      if (enabledSourceIds != null && !enabledSourceIds.contains(script.id)) {
        continue;
      }
      results.addAll(await script.search(query, host));
    }
    return results;
  }
}

class DemoHostApi implements SourceHostApi {
  @override
  Future<String> browse(String url) async => '<html data-url="$url"></html>';

  @override
  Future<String> download(String url, {String? fileName}) async =>
      '/downloads/${fileName ?? 'package.apk'}';

  @override
  Future<bool> install(String filePath) async => false;

  @override
  Future<String> request(
    String url, {
    Map<String, String> headers = const {},
  }) async => '{}';
}

class ApkAwardDemoScript implements ApkSourceScript {
  @override
  String get id => 'apkaward-demo';

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

  static const _detail = AppDetails(
    id: 'minecraft',
    name: 'Minecraft',
    packageName: 'com.mojang.minecraftpe',
    version: '1.21.92',
    size: '760 MB',
    updatedAt: '2026-07-18',
    category: '游戏',
    sourceName: 'APK Award（测试源）',
    iconUrl:
        'https://upload.wikimedia.org/wikipedia/en/5/51/Minecraft_cover.png',
    summary: '开放世界沙盒游戏',
    description: '这是一个用于验证源接口的测试条目。真实源脚本应从站点详情页读取描述、版本、截图、评论与下载文件。',
    screenshots: [
      'https://images.unsplash.com/photo-1607513746994-51f730a44832?w=900',
      'https://images.unsplash.com/photo-1511512578047-dfb367046420?w=900',
    ],
    comments: ['测试源已接入，页面数据来自内置演示脚本。', '请在安装前自行校验文件来源与签名。'],
    downloads: [
      SourceDownload(
        label: 'APK · arm64-v8a',
        url: 'https://example.com/apkaward/minecraft-arm64.apk',
        size: '760 MB',
      ),
      SourceDownload(
        label: 'XAPK · universal',
        url: 'https://example.com/apkaward/minecraft.xapk',
        size: '812 MB',
      ),
    ],
  );
}
