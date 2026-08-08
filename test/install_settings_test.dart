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
}

class _InstallHost extends DemoHostApi {
  _InstallHost(this.status);

  final ShizukuStatus status;
  final methods = <InstallMethod>[];

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
