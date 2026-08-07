import 'dart:io';

import 'package:apk_mesh/core/quickjs_source_io.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'QuickJS catalog calls serialize object results as JSON',
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
        async home() {
          return {
            recommended: [{id: 'https://example.test/app', name: 'Home App'}],
            categories: [{id: 'tools', name: 'Tools', apps: []}],
          };
        },
        async category(categoryId) {
          return {id: categoryId, name: 'Tools', apps: []};
        },
      };
    ''');

      await source.initialize();
      final home = await source.home(DemoHostApi());

      expect(home.recommended.single.name, 'Home App');
      expect(home.categories.single.id, 'tools');
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
