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
