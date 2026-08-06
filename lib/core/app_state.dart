import 'package:flutter/foundation.dart';

import 'models.dart';
import 'source_runtime.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _sources = [
      ApkSource(
        id: 'apkaward-demo',
        name: 'APK Award（测试源）',
        homepage: 'apkaward.com',
        version: '0.1.0',
        description: '内置演示源，用于验证搜索、详情和下载接口。',
        status: SourceStatus.enabled,
        builtIn: true,
        lastSync: DateTime.now(),
      ),
    ];
  }

  late List<ApkSource> _sources;
  final SourceRegistry registry = SourceRegistry(
    scripts: [ApkAwardDemoScript()],
  );
  final SourceHostApi host = DemoHostApi();
  List<ApkSource> get sources => List.unmodifiable(_sources);
  bool get hasEnabledSource =>
      _sources.any((source) => source.status == SourceStatus.enabled);

  Future<List<AppListing>> search(String query) => registry.search(
    query,
    host,
    enabledSourceIds: _sources
        .where((source) => source.status == SourceStatus.enabled)
        .map((source) => source.id)
        .toSet(),
  );

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
}
