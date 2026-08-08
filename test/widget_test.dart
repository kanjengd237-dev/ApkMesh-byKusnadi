import 'package:apk_mesh/core/app_state.dart';
import 'package:apk_mesh/core/models.dart';
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

  testWidgets('opens the download manager', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('暂无下载任务'), findsOneWidget);
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
    expect(find.byType(Chip), findsNWidgets(8));
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
    await tester.ensureVisible(find.text('test.example.app'));
    await tester.tap(find.text('test.example.app'));
    await tester.pumpAndSettle();
    expect(find.text('按包名查找'), findsOneWidget);
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
