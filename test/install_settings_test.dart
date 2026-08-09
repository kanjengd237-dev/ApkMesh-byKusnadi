import 'package:apk_mesh/core/app_state.dart';
import 'package:apk_mesh/core/models.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('does not enable Shizuku installation without authorization', () async {
    final host = _InstallHost(ShizukuStatus.denied);
    final state = AppState(host: host);

    expect(await state.setUseShizukuInstaller(true), isFalse);
    expect(state.useShizukuInstaller, isFalse);
    expect(host.methods, everyElement(InstallMethod.system));
    state.dispose();
  });

  test('persists and restores the selected installation method', () async {
    final host = _InstallHost(ShizukuStatus.authorized);
    final state = AppState(host: host);

    expect(await state.setUseShizukuInstaller(true), isTrue);
    expect(state.installMethod, InstallMethod.shizuku);
    expect(host.methods.last, InstallMethod.shizuku);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('install.method'), 'shizuku');
    state.dispose();

    final restoredHost = _InstallHost(ShizukuStatus.authorized);
    final restored = AppState(host: restoredHost);
    await restored.setUseShizukuInstaller(false);

    expect(restoredHost.methods, contains(InstallMethod.shizuku));
    expect(restored.installMethod, InstallMethod.system);
    restored.dispose();
  });

  test('persists source concurrency and applies restored limits', () async {
    final host = _InstallHost(ShizukuStatus.unsupported);
    final state = AppState(host: host);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    state.setSourceConcurrency(httpRequests: 500, webViews: 25);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('source.httpConcurrency'), 500);
    expect(preferences.getInt('source.webViewConcurrency'), 25);
    state.dispose();

    final restoredHost = _InstallHost(ShizukuStatus.unsupported);
    final restored = AppState(host: restoredHost);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(restored.sourceConcurrency.httpRequests, 500);
    expect(restored.sourceConcurrency.webViews, 25);
    expect(restoredHost.concurrency.last.httpRequests, 500);
    expect(restoredHost.concurrency.last.webViews, 25);
    restored.dispose();
  });

  test('persists and restores the selected download method', () async {
    final state = AppState(host: DemoHostApi());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    state.setDownloadMethod(DownloadMethod.browser);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('download.method'), 'browser');
    state.dispose();

    final restored = AppState(host: DemoHostApi());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(restored.downloadMethod, DownloadMethod.browser);
    restored.dispose();
  });

  test('persists disabled and home source preferences', () async {
    final state = AppState(host: DemoHostApi());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    state.toggleSource('apkvision-demo', false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    state.dispose();

    final restored = AppState(host: DemoHostApi());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(restored.sources.single.status, SourceStatus.disabled);
    expect(restored.homeSourceId, isNull);
    restored.dispose();
  });

  test('persists and restores fixed search tab sources', () async {
    final state = AppState(host: DemoHostApi());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    state.setSearchTabSourceIds(['source-b', 'source-a', 'source-b']);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('source.searchTabIds'), [
      'source-b',
      'source-a',
    ]);
    state.dispose();

    final restored = AppState(host: DemoHostApi());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(restored.searchTabSourceIds, ['source-b', 'source-a']);
    restored.dispose();
  });

  test(
    'manual installation does not require source install capability',
    () async {
      final host = _InstallHost(ShizukuStatus.unsupported);
      final state = AppState(host: host);
      final task = DownloadTask(
        id: 'manual-install',
        file: const SourceDownload(
          label: 'example.apk',
          url: 'https://example.test/example.apk',
          size: '1 MB',
        ),
        sourceId: 'unavailable-source',
        status: DownloadStatus.completed,
        startedAt: DateTime(2026, 1, 1),
        policy: const DownloadPolicySnapshot(allowedHosts: ['example.test']),
        filePath: '/downloads/example.apk',
      );

      expect(await state.installTask(task), isTrue);
      expect(host.installs, hasLength(1));
      expect(host.installs.single.policy.allowInstall, isFalse);
      expect(host.installs.single.userInitiated, isTrue);
      state.dispose();
    },
  );
}

class _InstallHost extends DemoHostApi implements SourceHostConcurrencyApi {
  _InstallHost(this.status);

  final ShizukuStatus status;
  final methods = <InstallMethod>[];
  final concurrency = <SourceConcurrencySettings>[];
  final installs = <({SourcePolicy policy, bool userInitiated})>[];

  @override
  void setSourceConcurrency(SourceConcurrencySettings settings) {
    concurrency.add(settings);
  }

  @override
  bool get supportsInstall => true;

  @override
  bool get supportsShizuku => true;

  @override
  Future<ShizukuStatus> shizukuStatus() async => status;

  @override
  Future<ShizukuStatus> requestShizukuPermission() async => status;

  @override
  Future<bool> install(
    String filePath, {
    required SourcePolicy policy,
    bool userInitiated = false,
  }) async {
    if (!policy.permitsInstall(userInitiated: userInitiated)) {
      throw StateError('源未声明安装权限');
    }
    installs.add((policy: policy, userInitiated: userInitiated));
    return true;
  }

  @override
  void setInstallMethod(InstallMethod method) {
    methods.add(method);
  }
}
