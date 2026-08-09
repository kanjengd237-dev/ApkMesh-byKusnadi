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

    state.setSourceConcurrency(httpRequests: 72, webViews: 7);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('source.httpConcurrency'), 72);
    expect(preferences.getInt('source.webViewConcurrency'), 7);
    state.dispose();

    final restoredHost = _InstallHost(ShizukuStatus.unsupported);
    final restored = AppState(host: restoredHost);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(restored.sourceConcurrency.httpRequests, 72);
    expect(restored.sourceConcurrency.webViews, 7);
    expect(restoredHost.concurrency.last.httpRequests, 72);
    expect(restoredHost.concurrency.last.webViews, 7);
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
}

class _InstallHost extends DemoHostApi implements SourceHostConcurrencyApi {
  _InstallHost(this.status);

  final ShizukuStatus status;
  final methods = <InstallMethod>[];
  final concurrency = <SourceConcurrencySettings>[];

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
  void setInstallMethod(InstallMethod method) {
    methods.add(method);
  }
}
