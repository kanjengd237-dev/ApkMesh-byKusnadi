import 'package:apk_mesh/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the four primary destinations', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());

    expect(find.text('发现应用'), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
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

  testWidgets('searches the bundled test source', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.enterText(find.byType(TextField).first, 'minecraft');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Minecraft'), findsOneWidget);
    expect(find.textContaining('APKVision'), findsOneWidget);
  });

  testWidgets('shows a completed empty search state', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.enterText(find.byType(TextField).first, 'missing-package');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('未找到结果'), findsOneWidget);
    expect(find.text('已在所有启用的源中搜索“missing-package”。'), findsOneWidget);
    expect(find.text('输入关键词开始搜索'), findsNothing);
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
