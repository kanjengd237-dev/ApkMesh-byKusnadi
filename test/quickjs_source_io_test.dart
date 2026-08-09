import 'dart:io';

import 'package:apk_mesh/core/models.dart';
import 'package:apk_mesh/core/quickjs_source_io.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QuickJS sidecar exposes metadata without creating a runtime', () async {
    final source = QuickJsApkSourceScript(
      'throw new Error("must stay lazy")',
      initialManifest: const {
        'id': 'lazy-source',
        'name': 'Lazy source',
        'version': '2.0.0',
        'homepage': 'https://example.test/',
        'description': 'Lazy metadata',
        'permissions': {
          'network': ['example.test'],
          'browser': true,
        },
        'capabilities': {
          'catalog': true,
          'detailProgress': false,
          'packageLookup': false,
        },
      },
    );

    expect(source.id, 'lazy-source');
    expect(source.name, 'Lazy source');
    expect(source.version, '2.0.0');
    expect(source.supportsCatalog, isTrue);
    expect(source.policy.allowBrowser, isTrue);
    await source.dispose();
  });

  test(
    'QuickJS catalog calls serialize tabs and page results as JSON',
    () async {
      final source = QuickJsApkSourceScript('''
      globalThis.source = {
        manifest: {
          id: 'catalog-result-test',
          name: 'Catalog result test',
          version: '1.0.0',
          homepage: 'https://example.test/',
          permissions: {network: ['example.test']},
        },
        async search(query, page = 1) { return []; },
        async details(url) { return {id: url, name: 'Example App'}; },
        async catalog() {
          return {
            defaultTabId: 'featured',
            tabs: [
              {id: 'featured', name: 'Featured', paged: false},
              {id: 'tools', name: 'Tools', paged: true},
            ],
          };
        },
        async catalogPage(tabId, page = 1) {
          return {
            apps: [{id: 'https://example.test/app', name: 'Catalog App'}],
            hasMore: tabId === 'tools' && page === 1,
          };
        },
      };
    ''');

      await source.initialize();
      final catalog = await source.catalog(DemoHostApi());
      final page = await source.catalogPage('tools', DemoHostApi(), page: 1);

      expect(catalog.defaultTabId, 'featured');
      expect(catalog.tabs.last.id, 'tools');
      expect(page.apps.single.name, 'Catalog App');
      expect(page.hasMore, isTrue);
      await source.dispose();
    },
    skip: !Platform.isAndroid,
  );

  test(
    'QuickJS adapts legacy home and category methods to catalog tabs',
    () async {
      final source = QuickJsApkSourceScript('''
      globalThis.source = {
        manifest: {
          id: 'legacy-catalog-test',
          name: 'Legacy catalog test',
          version: '1.0.0',
          homepage: 'https://example.test/',
          permissions: {network: ['example.test']},
        },
        async search(query, page = 1) { return []; },
        async details(url) { return {id: url, name: 'Example App'}; },
        async home() {
          return {
            recommended: [{id: 'https://example.test/app', name: 'Home App'}],
            categories: [{id: 'tools', name: 'Tools'}],
          };
        },
        async category(categoryId) {
          return {id: categoryId, name: 'Tools', apps: []};
        },
      };
    ''');

      await source.initialize();
      final catalog = await source.catalog(DemoHostApi());
      final categoryPage = await source.catalogPage('tools', DemoHostApi());

      expect(catalog.tabs.map((tab) => tab.name), ['推荐', 'Tools']);
      expect(catalog.tabs.every((tab) => !tab.paged), isTrue);
      expect(categoryPage.apps, isEmpty);
      expect(categoryPage.hasMore, isFalse);
      await source.dispose();
    },
    skip: !Platform.isAndroid,
  );

  test(
    'QuickJS staged details forward download progress events',
    () async {
      final source = QuickJsApkSourceScript('''
      globalThis.source = {
        manifest: {
          id: 'staged-quickjs-test',
          name: 'Staged QuickJS test',
          version: '1.0.0',
          homepage: 'https://example.test/',
          permissions: {network: ['example.test']},
        },
        async search(query, page = 1) { return []; },
        async details(url) {
          return {
            id: url,
            name: 'Example App',
            downloads: [{label: 'app.apk', url: 'https://example.test/app.apk', size: '1 MB'}],
          };
        },
        async detailsMetadata(url) {
          return {
            id: url,
            name: 'Example App',
            downloadCandidates: [{label: 'APK', url: 'https://example.test/prepare', size: '1 MB'}],
          };
        },
        async resolveDownloads(candidates, requestId) {
          await apkmesh.detailProgress(requestId, {
            index: 0,
            download: {label: 'app.apk', url: 'https://example.test/app.apk', size: '1 MB'},
          });
          return [{label: 'app.apk', url: 'https://example.test/app.apk', size: '1 MB'}];
        },
      };
    ''');

      await source.initialize();
      final updates = <AppDetailsProgress>[];
      await SourceRegistry(scripts: [source]).loadDetails(
        const AppListing(
          id: 'https://example.test/details/app',
          sourceId: 'staged-quickjs-test',
          name: 'Listing',
          packageName: '',
          version: '',
          size: '',
          updatedAt: '',
          category: '',
          sourceName: 'Staged QuickJS test',
          iconUrl: '',
        ),
        DemoHostApi(),
        onProgress: updates.add,
      );

      expect(updates.last.details.downloads.single.label, 'app.apk');
      expect(
        updates[1].downloads.single.files?.single.url,
        'https://example.test/app.apk',
      );
      await source.dispose();
    },
    skip: !Platform.isAndroid,
  );

  test(
    'QuickJS package lookup preserves URL and null results',
    () async {
      final source = QuickJsApkSourceScript('''
      globalThis.source = {
        manifest: {
          id: 'package-url-test',
          name: 'Package URL test',
          version: '1.0.0',
          homepage: 'https://example.test/',
          packageLookup: true,
          permissions: {network: ['example.test']},
        },
        packageLookupUrl(packageName) {
          return packageName === 'com.example.app'
            ? 'https://example.test/details/com.example.app'
            : null;
        },
        async search(query, page = 1) { return []; },
        async details(url) {
          return {
            id: url,
            name: 'Example App',
            packageName: 'com.example.app',
          };
        },
      };
    ''');

      await source.initialize();
      expect(
        await source.packageLookupUrl('com.example.app', DemoHostApi()),
        'https://example.test/details/com.example.app',
      );
      expect(
        await source.packageLookupUrl('com.example.missing', DemoHostApi()),
        isNull,
      );
      final results = await SourceRegistry(
        scripts: [source],
      ).lookupByPackageName('com.example.app', DemoHostApi());
      expect(results.single.id, 'https://example.test/details/com.example.app');
      await source.dispose();
    },
    skip: !Platform.isAndroid,
  );
}
