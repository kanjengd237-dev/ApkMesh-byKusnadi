import 'package:apk_mesh/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the three primary destinations', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());

    expect(find.text('发现应用'), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('源管理'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('searches the bundled test source', (tester) async {
    await tester.pumpWidget(const ApkMeshApp());
    await tester.enterText(find.byType(TextField).first, 'minecraft');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Minecraft'), findsOneWidget);
    expect(find.textContaining('APK Award'), findsOneWidget);
  });
}
