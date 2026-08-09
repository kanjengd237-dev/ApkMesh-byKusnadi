import 'package:apk_mesh/core/app_state.dart';
import 'package:apk_mesh/core/models.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:apk_mesh/main.dart';
import 'package:apk_mesh/widgets/app_result_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the four primary destinations', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());

    expect(find.text('发现应用'), findsNothing);
    expect(find.text('主页'), findsWidgets);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('源管理'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('changes the app theme from settings', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await tester.pumpAndSettle();

    expect(find.text('主题'), findsOneWidget);
    expect(find.text('跟随系统'), findsWidgets);

    await tester.tap(find.byType(DropdownButton<AppThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.text('主题'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('opens the download manager', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('暂无下载任务'), findsOneWidget);
  });

  testWidgets('shows the English translation action when search opens', (
    tester,
  ) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('翻译为英文'), findsOneWidget);
  });

  testWidgets('shows a completed empty search state', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'missing-package');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('未找到结果'), findsOneWidget);
    expect(find.text('已在所有启用的源中搜索“missing-package”。'), findsOneWidget);
    expect(find.text('输入关键词开始搜索'), findsNothing);
  });

  testWidgets('returns to the home page from search results', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'missing-package');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byTooltip('返回主页'), findsOneWidget);
    await tester.tap(find.byTooltip('返回主页'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('返回主页'), findsNothing);
    expect(find.text('未找到结果'), findsNothing);
  });
  testWidgets('renders listing description and metadata chips', (tester) async {
    final state = AppState();
    const app = AppDetails(
      id: 'https://example.test/apps/example',
      sourceId: 'example-source',
      name: 'Example App',
      packageName: 'test.example.app',
      version: '1.0.0',
      size: '1 MB',
      updatedAt: '2026-01-01',
      category: 'Tools',
      sourceName: 'Example source',
      iconUrl: '',
      summary: 'Legacy summary',
      description: 'Example description',
      rating: '4.8',
      author: 'Example Team',
      screenshots: [],
      comments: [],
      downloads: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppResultTile(app: app, state: state),
        ),
      ),
    );

    expect(find.text('Example description'), findsOneWidget);
    expect(find.text('Legacy summary'), findsNothing);
    expect(find.text('Example source'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('Example Team'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(find.byIcon(Icons.source_outlined), findsOneWidget);
    expect(find.byIcon(Icons.code_outlined), findsOneWidget);
    state.dispose();
  });

  testWidgets('details hides summary and shows metadata chips', (tester) async {
    final state = AppState();
    await state.initialize();
    const app = AppDetails(
      id: 'https://example.test/apps/example',
      sourceId: 'example-source',
      name: 'Example App',
      packageName: 'test.example.app',
      version: '1.0.0',
      size: '1 MB',
      updatedAt: '2026-01-01',
      category: 'Tools',
      sourceName: 'Example source',
      iconUrl: '',
      summary: 'Legacy summary',
      description: 'Example description',
      rating: '4.8',
      author: 'Example Team',
      screenshots: [],
      comments: [],
      downloads: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailsSheet(app: app, state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Legacy summary'), findsNothing);
    expect(find.text('Example description'), findsOneWidget);
    expect(find.text('Example source'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(8));
    final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
    expect(
      chips.map((chip) => chip.backgroundColor).toSet(),
      hasLength(chips.length),
    );
    expect(
      chips.map((chip) => chip.labelStyle?.color).toSet(),
      hasLength(chips.length),
    );
    await tester.ensureVisible(find.text('test.example.app'));
    await tester.tap(find.text('test.example.app'));
    await tester.pumpAndSettle();
    expect(find.text('按包名查找'), findsOneWidget);
    state.dispose();
  });

  testWidgets('opens the source batch test sheet', (tester) async {
    final state = AppState(host: DemoHostApi());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourcesPage(state: state)),
      ),
    );

    await tester.tap(find.text('批量测试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('批量测试源'), findsOneWidget);
    expect(find.text('搜索“hello” · 1 个源'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    state.dispose();
  });

  testWidgets('supports source selection and source test chip', (tester) async {
    final state = AppState(host: DemoHostApi());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourcesPage(state: state)),
      ),
    );

    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.text('主页'), findsOneWidget);
    await tester.longPress(find.text('APKVision'));
    await tester.pump();
    expect(find.byTooltip('退出多选'), findsOneWidget);

    final overflow = find.byTooltip('批量管理');
    if (overflow.evaluate().isNotEmpty) {
      await tester.tap(overflow);
      await tester.pumpAndSettle();
      expect(find.text('全选'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pump();
    } else {
      expect(find.byTooltip('全选'), findsOneWidget);
    }
    expect(find.text('已选择 1 个源'), findsOneWidget);

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pump();
    await tester.tap(find.byTooltip('查看测试项目'));
    await tester.pumpAndSettle();
    expect(find.text('暂无可测试项目'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    state.dispose();
  });

  testWidgets('opens the selected source test sheet and updates its status', (
    tester,
  ) async {
    final state = AppState(host: DemoHostApi());
    state.registry.replace(_TestDebugSource());
    state.addSource(
      const ApkSource(
        id: _TestDebugSource.sourceId,
        name: '测试源',
        homepage: 'example.test',
        version: '1.0.0',
        description: '用于测试源调试项目。',
        status: SourceStatus.enabled,
        builtIn: false,
      ),
    );
    await state.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourcesPage(state: state)),
      ),
    );

    await tester.tap(find.byTooltip('查看测试项目').last);
    await tester.pumpAndSettle();
    expect(find.text('执行搜索'), findsOneWidget);

    await tester.tap(find.text('执行搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('正在测试'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('测试成功'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pump();
    expect(find.text('测试结果'), findsOneWidget);
    expect(find.text('返回 1 条结果'), findsNWidgets(2));
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();

    state.dispose();
  });

  testWidgets('opens the source debug bottom sheet', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.tap(find.byTooltip('调试'));
    await tester.pumpAndSettle();

    expect(find.text('调试信息'), findsOneWidget);
    expect(find.text('WebView 状态'), findsOneWidget);
    expect(find.text('运行日志'), findsOneWidget);
  });
}

class _TestDebugSource implements ApkSourceScript, DebugProjectSource {
  static const sourceId = 'test-debug-source';
  static const project = SourceDebugProject(
    sourceId: sourceId,
    sourceName: '测试源',
    id: 'search',
    name: '执行搜索',
    description: '执行一个可控的异步测试。',
    inputLabel: '关键词',
    placeholder: '输入关键词',
    defaultInput: 'hello',
  );

  @override
  List<SourceDebugProject> get debugProjects => const [project];

  @override
  String get id => sourceId;

  @override
  String get name => '测试源';

  @override
  SourcePolicy get policy => const SourcePolicy(allowedHosts: {});

  @override
  Future<void> dispose() async {}

  @override
  Future<AppDetails> details(String appId, SourceHostApi host) async {
    throw UnimplementedError();
  }

  @override
  Future<DebugProjectResult> runDebugProject(
    SourceDebugProject project,
    String input,
    SourceHostApi host,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return DebugProjectResult(
      projectId: project.id,
      sourceId: sourceId,
      title: '搜索完成',
      summary: '返回 1 条结果',
      data: {'input': input},
    );
  }

  @override
  Future<List<AppListing>> search(
    String query,
    SourceHostApi host, {
    int page = 1,
  }) async => const [];
}
