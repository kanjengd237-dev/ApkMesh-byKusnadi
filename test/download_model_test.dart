import 'package:apk_mesh/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download tasks round-trip through persisted JSON', () {
    final task = DownloadTask(
      id: 'task-1',
      file: const SourceDownload(
        label: 'example.apk',
        url: 'https://example.test/example.apk',
        size: '10 MB',
        headers: {
          'Referer': 'https://example.test/',
          'Cookie': 'session=secret',
        },
      ),
      sourceId: 'example-source',
      status: DownloadStatus.completed,
      startedAt: DateTime.utc(2026, 1, 1, 12),
      policy: const DownloadPolicySnapshot(
        allowedHosts: ['example.test', '*.example.test'],
        allowInstall: true,
      ),
      received: 1024,
      total: 1024,
      filePath: '/downloads/example.apk',
      completedAt: DateTime.utc(2026, 1, 1, 12, 1),
      app: const AppListing(
        id: 'https://example.test/apps/example',
        sourceId: 'example-source',
        name: 'Example App',
        packageName: 'com.example.app',
        version: '1.0.0',
        size: '10 MB',
        updatedAt: '2026-01-01',
        category: 'Tools',
        sourceName: 'Example source',
        iconUrl: 'https://example.test/icon.png',
        description: 'Example description',
        rating: '4.8',
        author: 'Example Team',
      ),
    );

    final encoded = task.toJson();
    final restored = DownloadTask.fromJson(encoded);

    expect(restored.id, task.id);
    expect(restored.file.url, task.file.url);
    expect(restored.status, DownloadStatus.completed);
    expect(restored.policy?.allowedHosts, ['example.test', '*.example.test']);
    expect(restored.policy?.allowInstall, isTrue);
    expect(restored.received, 1024);
    expect(restored.filePath, task.filePath);
    expect(restored.app?.name, 'Example App');
    expect(restored.app?.iconUrl, 'https://example.test/icon.png');
    expect(restored.file.headers, {'Referer': 'https://example.test/'});
    expect(encoded.toString(), isNot(contains('session=secret')));

    final legacyEncoded = Map<String, dynamic>.from(encoded)..remove('app');
    expect(DownloadTask.fromJson(legacyEncoded).app, isNull);
  });
}
