import 'package:apk_mesh/core/source_runtime.dart';
import 'package:apk_mesh/core/models.dart';
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
    final registry = SourceRegistry(scripts: [ApkVisionDemoScript()]);
    final host = DemoHostApi();

    expect(
      await registry.search('minecraft', host, enabledSourceIds: const {}),
      isEmpty,
    );
    expect(
      (await registry.search(
        'minecraft',
        host,
        enabledSourceIds: {'apkvision-demo'},
      )).single.name,
      'Minecraft',
    );
    expect(
      ApkVisionDemoScript().policy.permits(
        Uri.parse('https://dl.apkvision.org/minecraft/test.apk'),
      ),
      isTrue,
    );
  });

  test('registry exposes source failures for the UI', () async {
    final registry = SourceRegistry(scripts: [FailingSource()]);
    await registry.search(
      'minecraft',
      DemoHostApi(),
      enabledSourceIds: {'failing'},
    );

    expect(registry.lastErrors['故障源'], contains('解析失败'));
  });
}

class FailingSource implements ApkSourceScript {
  @override
  String get id => 'failing';

  @override
  String get name => '故障源';

  @override
  SourcePolicy get policy => const SourcePolicy(allowedHosts: {});

  @override
  Future<List<AppListing>> search(String query, SourceHostApi host) {
    throw StateError('解析失败');
  }

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) {
    throw StateError('解析失败');
  }

  @override
  Future<void> dispose() async {}
}
