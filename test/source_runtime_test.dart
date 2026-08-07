import 'dart:async';

import 'package:apk_mesh/core/models.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source policy only permits declared hosts', () {
    const policy = SourcePolicy(
      allowedHosts: {'example.com', '*.cdn.example.com'},
      allowBrowser: true,
    );

    expect(policy.permits(Uri.parse('https://example.com/app')), isTrue);
    expect(
      policy.permits(Uri.parse('https://img.cdn.example.com/icon.png')),
      isTrue,
    );
    expect(
      policy.permits(Uri.parse('https://cdn.example.com/icon.png')),
      isFalse,
    );
    expect(policy.permits(Uri.parse('file:///tmp/app.apk')), isFalse);
  });

  test('source policy allows an explicit any-host permission', () {
    const policy = SourcePolicy(allowedHosts: {'*'});

    expect(
      policy.permits(Uri.parse('https://temporary.example/file.apk')),
      isTrue,
    );
    expect(policy.permits(Uri.parse('http://redirect.example/file')), isTrue);
    expect(policy.permits(Uri.parse('file:///tmp/app.apk')), isFalse);
  });
  test('registry skips disabled source ids', () async {
    final registry = SourceRegistry(scripts: [ExampleCatalogSource()]);
    final host = DemoHostApi();

    expect(
      await registry.search('example', host, enabledSourceIds: const {}),
      isEmpty,
    );
    expect(
      (await registry.search(
        'example',
        host,
        enabledSourceIds: {'example-source'},
      )).single.name,
      'Example App',
    );
  });

  test(
    'registry starts all enabled searches before awaiting results',
    () async {
      final gate = _SearchGate();
      final registry = SourceRegistry(
        scripts: [
          _ConcurrentSource('first', gate),
          _ConcurrentSource('second', gate),
        ],
      );
      final completed = <String>[];
      final search = registry.search(
        'example',
        DemoHostApi(),
        onSourceCompleted: (source, _) => completed.add(source.id),
      );

      await gate.bothStarted.future;
      expect(gate.started, 2);
      expect(completed, isEmpty);

      gate.release.complete();
      final results = await search;
      expect(completed, hasLength(2));
      expect(results, hasLength(2));
    },
  );

  test(
    'registry ranks distinct title keywords and preserves source order on ties',
    () async {
      final registry = SourceRegistry(
        scripts: [
          _StaticSearchSource('first', [
            _listing('first', 'alpha beta normal'),
            _listing('first', 'alpha alpha beta repeated'),
            _listing('first', 'alpha only'),
          ]),
          _StaticSearchSource('second', [
            _listing('second', 'beta alpha second-source'),
            _listing('second', 'beta only'),
          ]),
        ],
      );

      final results = await registry.search('alpha beta', DemoHostApi());

      expect(results.map((app) => app.name), [
        'alpha beta normal',
        'alpha alpha beta repeated',
        'beta alpha second-source',
        'alpha only',
        'beta only',
      ]);
    },
  );

  test('registry aggregates optional home and category APIs', () async {
    final registry = SourceRegistry(scripts: [ExampleCatalogSource()]);
    final home = await registry.home(
      DemoHostApi(),
      enabledSourceIds: {'example-source'},
    );

    expect(home.recommended.single.name, 'Example App');
    expect(home.categories.single.name, 'Tools');

    final category = await registry.category(
      home.categories.single,
      DemoHostApi(),
    );
    expect(category.apps.single.name, 'Example App');
  });

  test('registry exposes source failures for the UI', () async {
    final registry = SourceRegistry(scripts: [FailingSource()]);
    await registry.search(
      'example',
      DemoHostApi(),
      enabledSourceIds: {'failing'},
    );

    expect(registry.lastErrors['Failing source'], contains('parse failed'));
  });
}

class ExampleCatalogSource implements ApkSourceScript, SourceCatalogScript {
  @override
  String get id => 'example-source';

  @override
  String get name => 'Example source';

  @override
  SourcePolicy get policy =>
      const SourcePolicy(allowedHosts: {'example.test', '*.cdn.example.test'});

  @override
  bool get supportsCatalog => true;

  @override
  Future<SourceHome> home(SourceHostApi host) async => SourceHome(
    recommended: const [_app],
    categories: [
      SourceCategory(
        id: 'tools',
        name: 'Tools',
        sourceId: id,
        sourceName: name,
      ),
    ],
  );

  @override
  Future<SourceCategory> category(
    String categoryId,
    SourceHostApi host,
  ) async => SourceCategory(
    id: categoryId,
    name: 'Tools',
    sourceId: id,
    sourceName: name,
    apps: const [_app],
  );

  @override
  Future<List<AppListing>> search(String query, SourceHostApi host) async {
    if (!query.toLowerCase().contains('example')) return const [];
    return const [_app];
  }

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async => _app;

  @override
  Future<void> dispose() async {}

  static const _app = AppDetails(
    id: 'https://example.test/apps/example',
    sourceId: 'example-source',
    name: 'Example App',
    packageName: 'test.example.app',
    version: '1.0.0',
    size: '1 MB',
    updatedAt: '2026-01-01',
    category: 'Tools',
    sourceName: 'Example source',
    iconUrl: 'https://cdn.example.test/example.png',
    summary: 'Example listing',
    description: 'Example details',
    screenshots: [],
    comments: [],
    downloads: [],
  );
}

class _StaticSearchSource implements ApkSourceScript {
  _StaticSearchSource(this.id, this.results);

  @override
  final String id;
  final List<AppListing> results;

  @override
  String get name => 'Static $id';

  @override
  SourcePolicy get policy => const SourcePolicy(allowedHosts: {});

  @override
  Future<List<AppListing>> search(String query, SourceHostApi host) async =>
      results;

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}
}

AppListing _listing(String sourceId, String name) => AppListing(
  id: '$sourceId/$name',
  sourceId: sourceId,
  name: name,
  packageName: '',
  version: '',
  size: '',
  updatedAt: '',
  category: '',
  sourceName: sourceId,
  iconUrl: '',
);

class _SearchGate {
  int started = 0;
  final bothStarted = Completer<void>();
  final release = Completer<void>();
}

class _ConcurrentSource implements ApkSourceScript {
  _ConcurrentSource(this.id, this.gate);

  @override
  final String id;
  final _SearchGate gate;

  @override
  String get name => 'Concurrent $id';

  @override
  SourcePolicy get policy => const SourcePolicy(allowedHosts: {});

  @override
  Future<List<AppListing>> search(String query, SourceHostApi host) async {
    gate.started += 1;
    if (gate.started == 2) gate.bothStarted.complete();
    await gate.release.future;
    return const [ExampleCatalogSource._app];
  }

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async =>
      ExampleCatalogSource._app;

  @override
  Future<void> dispose() async {}
}

class FailingSource implements ApkSourceScript {
  @override
  String get id => 'failing';

  @override
  String get name => 'Failing source';

  @override
  SourcePolicy get policy => const SourcePolicy(allowedHosts: {});

  @override
  Future<List<AppListing>> search(String query, SourceHostApi host) {
    throw StateError('parse failed');
  }

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) {
    throw StateError('parse failed');
  }

  @override
  Future<void> dispose() async {}
}
