import 'package:apk_mesh/core/app_state.dart';
import 'package:apk_mesh/core/models.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:apk_mesh/pages/downloads_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows installation progress for an active install', (
    tester,
  ) async {
    final state = _ControlState(installing: true);

    await tester.pumpWidget(_controlsApp(state));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('安装'), findsNothing);
    state.dispose();
  });

  testWidgets('shows and invokes open when the APK version matches', (
    tester,
  ) async {
    final state = _ControlState(
      info: const ApkInstallInfo(
        supported: true,
        installed: true,
        versionMatches: true,
        canOpen: true,
        packageName: 'com.example.app',
        archiveVersionName: '1.0.0',
        archiveVersionCode: 1,
        installedVersionName: '1.0.0',
        installedVersionCode: 1,
      ),
    );

    await tester.pumpWidget(_controlsApp(state));
    await tester.tap(find.text('打开'));
    await tester.pump();

    expect(state.opened, isTrue);
    state.dispose();
  });

  testWidgets('offers full installation error details from the snackbar', (
    tester,
  ) async {
    final state = _ControlState(installError: 'INSTALL_FAILED_TEST');

    await tester.pumpWidget(_controlsApp(state));
    await tester.tap(find.text('安装'));
    await tester.pumpAndSettle();

    expect(find.text('安装失败'), findsOneWidget);
    expect(find.text('详情'), findsOneWidget);
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();

    expect(find.text('安装失败详情'), findsOneWidget);
    expect(find.textContaining('INSTALL_FAILED_TEST'), findsOneWidget);
    state.dispose();
  });
}

Widget _controlsApp(_ControlState state) => MaterialApp(
  home: Scaffold(
    body: DownloadTaskControls(task: _completedTask, state: state),
  ),
);

final _completedTask = DownloadTask(
  id: 'download-1',
  file: const SourceDownload(
    label: 'example.apk',
    url: 'https://example.test/example.apk',
    size: '1 MB',
  ),
  sourceId: 'missing-source',
  status: DownloadStatus.completed,
  startedAt: DateTime(2026, 1, 1),
  policy: const DownloadPolicySnapshot(
    allowedHosts: ['example.test'],
    allowInstall: true,
  ),
  filePath: '/tmp/example.apk',
);

class _ControlState extends AppState {
  _ControlState({this.info, this.installing = false, this.installError})
    : super(host: DemoHostApi());

  final ApkInstallInfo? info;
  final bool installing;
  final String? installError;
  bool opened = false;

  @override
  ApkInstallInfo? installInfoFor(String downloadId) => info;

  @override
  bool isInstallingDownload(String downloadId) => installing;

  @override
  Future<void> refreshInstallState(DownloadTask task) async {}

  @override
  Future<void> openInstalledTask(DownloadTask task) async {
    opened = true;
  }

  @override
  Future<bool> installTask(DownloadTask task) async {
    final error = installError;
    if (error != null) throw StateError(error);
    return true;
  }
}
