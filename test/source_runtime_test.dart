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
    final registry = SourceRegistry(scripts: [ApkAwardDemoScript()]);
    final host = DemoHostApi();

    expect(
      await registry.search('minecraft', host, enabledSourceIds: const {}),
      isEmpty,
    );
    expect(
      (await registry.search(
        'minecraft',
        host,
        enabledSourceIds: {'apkaward-demo'},
      )).single.name,
      'Minecraft',
    );
  });
}
