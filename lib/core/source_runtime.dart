import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'concurrency_limiter.dart';
import 'models.dart';
import 'debug_log.dart';

class BrowserTabViewHandle {
  const BrowserTabViewHandle({
    this.headlessWebView,
    required this.keepAlive,
    required this.policy,
  });

  final HeadlessInAppWebView? headlessWebView;
  final InAppWebViewKeepAlive keepAlive;
  final SourcePolicy policy;

  bool get attachesHeadlessWebView => headlessWebView != null;
}

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

  bool permitsInstall({required bool userInitiated}) =>
      userInitiated || allowInstall;

  bool permits(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    return allowedHosts.any((rule) {
      final normalized = rule.toLowerCase();
      if (normalized == '*') return true;
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
  bool get supportsShizuku;
  bool hasDownloadSession(String downloadId);
  List<BrowserTabDebugInfo> get browserTabs;

  Future<String> request(
    String url, {
    Map<String, String> headers = const {},
    required SourcePolicy policy,
  });

  Future<List<int>> requestBytes(
    String url, {
    Map<String, String> headers = const {},
    required SourcePolicy policy,
  });

  Future<String> browserOpen(String url, {required SourcePolicy policy});
  Future<void> browserWaitFor(String tabId, String selector);
  Future<String> browserWaitForUrlChange(String tabId, String previousUrl);
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
  BrowserTabViewHandle? browserTabView(String tabId);
  void browserAdoptController(String tabId, InAppWebViewController controller);

  Future<String> download(
    String url, {
    Map<String, String> headers = const {},
    String? downloadId,
    String? fileName,
    required SourcePolicy policy,
    void Function(int received, int? total)? onProgress,
  });
  Future<void> pauseDownload(String downloadId);
  Future<void> resumeDownload(String downloadId);
  Future<void> cancelDownload(String downloadId);
  Future<void> removeDownloadFiles(String downloadId, {String? filePath});

  Future<bool> install(
    String filePath, {
    required SourcePolicy policy,
    bool userInitiated = false,
  });
  Future<bool> canInstallPackages();
  Future<void> requestInstallPermission();
  Future<ApkInstallInfo> inspectInstall(String filePath);
  Future<bool> openInstalled(String packageName);
  void setInstallMethod(InstallMethod method);
  Future<ShizukuStatus> shizukuStatus();
  Future<ShizukuStatus> requestShizukuPermission();
  Future<void> dispose();
}

abstract interface class SourceHostConcurrencyApi {
  void setSourceConcurrency(SourceConcurrencySettings settings);
}

class SourceSearchCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

abstract interface class ApkSourceScript {
  String get id;
  String get name;
  SourcePolicy get policy;
  Future<List<AppListing>> search(
    String query,
    SourceHostApi host, {
    int page = 1,
  });
  Future<AppDetails> details(String appId, SourceHostApi host);
  Future<void> dispose();
}

/// Optional source capability for exact Android package-name lookup.
abstract interface class SourcePackageLookupScript {
  bool get supportsPackageLookup;
  Future<String?> packageLookupUrl(String packageName, SourceHostApi host);
}

/// Optional metadata exposed by scripts loaded from a manifest.
abstract interface class SourceDetailProgressScript {
  bool get supportsDetailProgress;
  Future<SourceDetailsMetadata> detailsMetadata(
    String appId,
    SourceHostApi host,
  );
  Future<List<SourceDownload>> resolveDownloads(
    List<SourceDownloadCandidate> candidates,
    SourceHostApi host, {
    required void Function(
      int index,
      List<SourceDownload>? files,
      String? error,
    )
    onProgress,
  });
}

abstract interface class SourceManifestProvider {
  String get version;
  String get homepage;
  String get description;
}

abstract interface class SourceCatalogScript {
  bool get supportsCatalog;
  Future<SourceCatalog> catalog(SourceHostApi host);
  Future<SourceCatalogPage> catalogPage(
    String tabId,
    SourceHostApi host, {
    int page = 1,
  });
}

abstract interface class DebugProjectSource {
  List<SourceDebugProject> get debugProjects;
  Future<DebugProjectResult> runDebugProject(
    SourceDebugProject project,
    String input,
    SourceHostApi host,
  );
}

List<String> _searchKeywords(String query) {
  final unique = <String>{};
  for (final keyword in query.toLowerCase().split(
    RegExp(r'[\s,，、;；|/\\_-]+'),
  )) {
    final normalized = keyword.trim();
    if (normalized.isNotEmpty) unique.add(normalized);
  }
  return unique.toList(growable: false);
}

class SearchResultRanker {
  SearchResultRanker(String query) : _keywords = _searchKeywords(query);

  final List<String> _keywords;

  int score(AppListing app) {
    final title = app.name.toLowerCase();
    var result = 0;
    for (final keyword in _keywords) {
      if (title.contains(keyword)) result += 1;
    }
    return result;
  }
}

List<AppListing> _rankSearchResults(
  String query,
  List<List<AppListing>> batches,
) {
  final ranker = SearchResultRanker(query);
  final ranked = <({AppListing app, int score, int order})>[];
  var order = 0;

  // Each distinct keyword contributes at most one point. The original
  // flattened order is the deterministic tie-breaker for equal scores.
  for (final batch in batches) {
    for (final app in batch) {
      ranked.add((app: app, score: ranker.score(app), order: order));
      order += 1;
    }
  }

  ranked.sort((left, right) {
    final scoreOrder = right.score.compareTo(left.score);
    return scoreOrder == 0 ? left.order.compareTo(right.order) : scoreOrder;
  });
  return ranked.map((item) => item.app).toList(growable: false);
}

class SourceRegistry {
  SourceRegistry({
    List<ApkSourceScript> scripts = const [],
    int maxConcurrentOperations = SourceConcurrencySettings.defaultHttpRequests,
  }) : scripts = [...scripts],
       _scriptsById = {for (final script in scripts) script.id: script},
       _operations = AdjustableSemaphore(maxConcurrentOperations);
  final List<ApkSourceScript> scripts;
  final Map<String, ApkSourceScript> _scriptsById;
  final Map<String, String> lastErrors = {};
  final AdjustableSemaphore _operations;

  int get maxConcurrentOperations => _operations.limit;

  set maxConcurrentOperations(int value) => _operations.limit = value;

  void replace(ApkSourceScript script) {
    final index = scripts.indexWhere((item) => item.id == script.id);
    if (index == -1) {
      scripts.add(script);
    } else {
      final previous = scripts[index];
      scripts[index] = script;
      previous.dispose();
    }
    _scriptsById[script.id] = script;
  }

  Future<void> remove(String id) async {
    final index = scripts.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final script = scripts.removeAt(index);
    _scriptsById.remove(id);
    await script.dispose();
  }

  Future<List<AppListing>> search(
    String query,
    SourceHostApi host, {
    int page = 1,
    Set<String>? enabledSourceIds,
    void Function(ApkSourceScript source, List<AppListing> results)?
    onSourceCompleted,
    SourceSearchCancellation? cancellation,
  }) async {
    final pages = await searchPage(
      query,
      host,
      page: page,
      enabledSourceIds: enabledSourceIds,
      cancellation: cancellation,
      onSourcePageCompleted: (source, result) {
        if (result.succeeded) {
          onSourceCompleted?.call(source, result.results);
        }
      },
    );
    return _rankSearchResults(
      query,
      pages.map((result) => result.results).toList(growable: false),
    );
  }

  Future<List<SourceSearchPage>> searchPage(
    String query,
    SourceHostApi host, {
    int page = 1,
    Set<String>? enabledSourceIds,
    bool clearErrors = true,
    SourceSearchCancellation? cancellation,
    void Function(ApkSourceScript source, SourceSearchPage result)?
    onSourcePageCompleted,
  }) async {
    if (page < 1)
      throw ArgumentError.value(page, 'page', 'must be greater than 0');
    if (clearErrors) lastErrors.clear();
    final selectedScripts = scripts
        .where(
          (script) =>
              enabledSourceIds == null || enabledSourceIds.contains(script.id),
        )
        .toList(growable: false);

    // All selected sources request the same page concurrently. A source that
    // has ended can be removed from enabledSourceIds by the caller before the
    // next request.
    return Future.wait(
      selectedScripts.map(
        (script) => _operations.withPermit(() async {
          if (cancellation?.isCancelled == true) {
            return SourceSearchPage(
              sourceId: script.id,
              sourceName: script.name,
              page: page,
              results: const [],
            );
          }
          try {
            final sourceResults = await script.search(query, host, page: page);
            final result = SourceSearchPage(
              sourceId: script.id,
              sourceName: script.name,
              page: page,
              results: sourceResults,
            );
            if (cancellation?.isCancelled != true) {
              onSourcePageCompleted?.call(script, result);
            }
            return result;
          } catch (error) {
            final message = error.toString();
            lastErrors[script.name] = message;
            final result = SourceSearchPage(
              sourceId: script.id,
              sourceName: script.name,
              page: page,
              results: const [],
              error: message,
            );
            if (cancellation?.isCancelled != true) {
              onSourcePageCompleted?.call(script, result);
            }
            return result;
          }
        }),
      ),
    );
  }

  Future<void> loadDetails(
    AppListing app,
    SourceHostApi host, {
    required void Function(AppDetailsProgress progress) onProgress,
  }) async {
    final script = scriptFor(app.sourceId);
    final SourceDetailProgressScript? detailScript =
        script is SourceDetailProgressScript
        ? script as SourceDetailProgressScript
        : null;
    if (detailScript == null || !detailScript.supportsDetailProgress) {
      final details = await script.details(app.id, host);
      final downloads = details.downloads
          .map(
            (file) => SourceDownloadProgress(
              candidate: SourceDownloadCandidate(
                label: file.label,
                url: file.url,
                size: file.size,
                headers: file.headers,
              ),
              files: [file],
            ),
          )
          .toList(growable: false);
      final result = AppDetailsProgress(
        details: details,
        downloads: downloads,
        phase: DetailLoadPhase.complete,
      );
      onProgress(result);
      return;
    }

    final metadata = await detailScript.detailsMetadata(app.id, host);
    final states = metadata.downloads
        .map((candidate) => SourceDownloadProgress(candidate: candidate))
        .toList();
    void publish(DetailLoadPhase phase, {String? error}) {
      onProgress(
        AppDetailsProgress(
          details: metadata.details,
          downloads: List.unmodifiable(states),
          phase: phase,
          error: error,
        ),
      );
    }

    publish(DetailLoadPhase.resolvingDownloads);
    await detailScript.resolveDownloads(
      metadata.downloads,
      host,
      onProgress: (index, files, error) {
        if (index < 0 || index >= states.length) return;
        states[index] = SourceDownloadProgress(
          candidate: states[index].candidate,
          files: files,
          error: error,
        );
        publish(DetailLoadPhase.resolvingDownloads);
      },
    );
    final finalFiles = states
        .where((item) => item.files != null)
        .expand((item) => item.files!)
        .toList(growable: false);
    final result = AppDetailsProgress(
      details: metadata.details.copyWith(downloads: finalFiles),
      downloads: List.unmodifiable(states),
      phase: DetailLoadPhase.complete,
    );
    onProgress(result);
  }

  Future<AppDetails> details(AppListing app, SourceHostApi host) {
    final script = scriptFor(app.sourceId);
    return script.details(app.id, host);
  }

  Future<List<AppListing>> lookupByPackageName(
    String packageName,
    SourceHostApi host, {
    Set<String>? enabledSourceIds,
  }) async {
    final normalized = packageName.trim();
    if (normalized.isEmpty) return const [];
    lastErrors.clear();
    final selectedScripts = scripts
        .where((script) {
          if (enabledSourceIds != null &&
              !enabledSourceIds.contains(script.id)) {
            return false;
          }
          return script is SourcePackageLookupScript &&
              (script as SourcePackageLookupScript).supportsPackageLookup;
        })
        .toList(growable: false);

    final batches = await Future.wait(
      selectedScripts.map(
        (script) => _operations.withPermit(() async {
          final packageSource = script as SourcePackageLookupScript;
          try {
            final url = (await packageSource.packageLookupUrl(
              normalized,
              host,
            ))?.trim();
            if (url == null || url.isEmpty) return const <AppListing>[];
            final details = await script.details(url, host);
            return details.packageName.trim().toLowerCase() ==
                    normalized.toLowerCase()
                ? <AppListing>[details]
                : const <AppListing>[];
          } catch (error) {
            lastErrors[script.name] = error.toString();
            return const <AppListing>[];
          }
        }),
      ),
    );
    return batches.expand((batch) => batch).toList(growable: false);
  }

  ApkSourceScript scriptFor(String sourceId) =>
      _scriptsById[sourceId] ??
      (throw StateError('Source runtime does not exist: $sourceId'));

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
      throw UnsupportedError('Source does not declare debug projects');
    }
    return (script as DebugProjectSource).runDebugProject(project, input, host);
  }

  Future<SourceCatalog> catalog(
    SourceHostApi host, {
    Set<String>? enabledSourceIds,
  }) async {
    var result = const SourceCatalog();
    lastErrors.clear();
    for (final script in scripts) {
      if (enabledSourceIds != null && !enabledSourceIds.contains(script.id)) {
        continue;
      }
      final SourceCatalogScript? catalog = script is SourceCatalogScript
          ? script as SourceCatalogScript
          : null;
      if (catalog == null || !catalog.supportsCatalog) continue;
      try {
        result = result.merge(await catalog.catalog(host));
      } catch (error) {
        lastErrors[script.name] = error.toString();
      }
    }
    return result;
  }

  Future<SourceCatalogPage> catalogPage(
    SourceCatalogTab tab,
    SourceHostApi host, {
    int page = 1,
  }) {
    if (page < 1)
      throw ArgumentError.value(page, 'page', 'must be greater than 0');
    final script = scriptFor(tab.sourceId);
    if (script is! SourceCatalogScript) {
      throw UnsupportedError('Source does not declare catalog interface');
    }
    final catalog = script as SourceCatalogScript;
    return catalog.catalogPage(tab.id, host, page: page);
  }

  Future<void> dispose() async {
    for (final script in scripts) {
      await script.dispose();
    }
  }
}

class DemoHostApi implements SourceHostApi {
  @override
  bool hasDownloadSession(String downloadId) => false;

  @override
  List<BrowserTabDebugInfo> get browserTabs => const [];

  @override
  bool get supportsBrowser => false;

  @override
  bool get supportsInstall => false;

  @override
  bool get supportsShizuku => false;

  @override
  Future<String> browserOpen(String url, {required SourcePolicy policy}) =>
      throw UnsupportedError(
        'Headless browser is not supported on this platform',
      );

  @override
  Future<void> browserWaitFor(String tabId, String selector) =>
      throw UnsupportedError(
        'Headless browser is not supported on this platform',
      );

  @override
  Future<String> browserWaitForUrlChange(String tabId, String previousUrl) =>
      throw UnsupportedError(
        'Headless browser is not supported on this platform',
      );

  @override
  Future<Map<String, dynamic>> browserQuery(
    String tabId,
    Map<String, dynamic> selectors,
  ) => throw UnsupportedError(
    'Headless browser is not supported on this platform',
  );

  @override
  Future<List<Map<String, dynamic>>> browserQueryAll(
    String tabId,
    String rootSelector,
    Map<String, dynamic> selectors,
  ) => throw UnsupportedError(
    'Headless browser is not supported on this platform',
  );

  @override
  Future<void> browserClose(String tabId) async {}

  @override
  BrowserTabViewHandle? browserTabView(String tabId) => null;

  @override
  void browserAdoptController(
    String tabId,
    InAppWebViewController controller,
  ) {}

  @override
  Future<String> download(
    String url, {
    Map<String, String> headers = const {},
    String? downloadId,
    String? fileName,
    required SourcePolicy policy,
    void Function(int received, int? total)? onProgress,
  }) =>
      throw UnsupportedError('File download is not supported on this platform');

  @override
  Future<void> pauseDownload(String downloadId) => throw UnsupportedError(
    'Download pause is not supported on this platform',
  );

  @override
  Future<void> resumeDownload(String downloadId) => throw UnsupportedError(
    'Download resume is not supported on this platform',
  );

  @override
  Future<void> cancelDownload(String downloadId) => throw UnsupportedError(
    'Download cancel is not supported on this platform',
  );

  @override
  Future<void> removeDownloadFiles(
    String downloadId, {
    String? filePath,
  }) async {}

  @override
  Future<bool> install(
    String filePath, {
    required SourcePolicy policy,
    bool userInitiated = false,
  }) async => false;

  @override
  Future<bool> canInstallPackages() async => false;

  @override
  Future<void> requestInstallPermission() async {}

  @override
  Future<ApkInstallInfo> inspectInstall(String filePath) async =>
      const ApkInstallInfo.unsupported();

  @override
  Future<bool> openInstalled(String packageName) async => false;

  @override
  void setInstallMethod(InstallMethod method) {}

  @override
  Future<ShizukuStatus> shizukuStatus() async => ShizukuStatus.unsupported;

  @override
  Future<ShizukuStatus> requestShizukuPermission() async =>
      ShizukuStatus.unsupported;

  @override
  Future<String> request(
    String url, {
    Map<String, String> headers = const {},
    required SourcePolicy policy,
  }) => throw UnsupportedError(
    'Source network request is not supported on this platform',
  );

  @override
  Future<List<int>> requestBytes(
    String url, {
    Map<String, String> headers = const {},
    required SourcePolicy policy,
  }) => throw UnsupportedError(
    'Source network request is not supported on this platform',
  );

  @override
  Future<void> dispose() async {}
}

class ApkVisionDemoScript
    implements ApkSourceScript, SourceCatalogScript, SourcePackageLookupScript {
  @override
  bool get supportsCatalog => true;
  @override
  bool get supportsPackageLookup => false;
  @override
  String get id => 'apkvision-demo';

  @override
  String get name => 'APKVision';

  @override
  SourcePolicy get policy => const SourcePolicy(
    allowedHosts: {'apkvision.org', '*.apkvision.org'},
    allowBrowser: true,
    allowDownload: true,
  );

  @override
  Future<SourceCatalog> catalog(SourceHostApi host) async => SourceCatalog(
    defaultTabId: 'recommended',
    tabs: const [
      SourceCatalogTab(
        id: 'recommended',
        name: 'Recommended',
        sourceId: 'apkvision-demo',
        sourceName: 'APKVision',
        paged: false,
      ),
      SourceCatalogTab(
        id: 'arcade',
        name: 'Arcade',
        sourceId: 'apkvision-demo',
        sourceName: 'APKVision',
        paged: true,
        description: 'Action and arcade apps',
      ),
    ],
  );

  @override
  Future<SourceCatalogPage> catalogPage(
    String tabId,
    SourceHostApi host, {
    int page = 1,
  }) async => SourceCatalogPage(
    tabId: tabId,
    sourceId: id,
    sourceName: name,
    page: page,
    apps: page == 1 ? [_detail] : const [],
    hasMore: tabId == 'arcade' && page == 1,
  );

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async => _detail;

  @override
  Future<List<AppListing>> search(
    String query,
    SourceHostApi host, {
    int page = 1,
  }) async {
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
  Future<String?> packageLookupUrl(
    String packageName,
    SourceHostApi host,
  ) async => null;

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
    sourceName: 'APKVision',
    iconUrl:
        'https://apkvision.org/wp-content/uploads/2020/01/minecraft-play-with-friends.png',
    summary: 'Minecraft APK free download from APKVision.',
    description:
        'A test entry for verifying APKVision search, details, and download interfaces.',
    screenshots: [
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-1.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-2.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-3.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-4.webp',
      'https://img.apkvision.org/minecraft-play-with-friends/minecraft-play-with-friends-5.webp',
    ],
    comments: ['Verify file source and signature before installing.'],
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
