import 'package:apk_mesh/core/app_state.dart';
import 'package:apk_mesh/core/models.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:apk_mesh/pages/home_page.dart';
import 'package:apk_mesh/pages/sources_page.dart';
import 'package:apk_mesh/widgets/app_result_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'translation.auto': false});
  });

  testWidgets('source management lazily builds hundreds of sources', (
    tester,
  ) async {
    final state = AppState(host: DemoHostApi());
    for (var index = 0; index < 300; index++) {
      state.addSource(_source(index));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourcesPage(state: state)),
      ),
    );
    await tester.pump();

    expect(state.sources, hasLength(301));
    expect(find.byType(SourceTile).evaluate().length, lessThan(20));
    expect(find.text('Scale source 299'), findsNothing);
    state.dispose();
  });

  testWidgets('search lazily builds a large aggregated result set', (
    tester,
  ) async {
    final state = AppState(host: DemoHostApi());
    await state.initialize();
    final controller = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(state: state, controller: controller),
        ),
      ),
    );
    await tester.pump();
    final home = tester.state<HomePageState>(find.byType(HomePage));
    home
      ..submittedQuery = 'scale'
      ..loading = false
      ..results = List.generate(1000, _listing);
    await tester.pump();

    expect(find.byType(AppResultTile).evaluate().length, lessThan(30));
    expect(find.text('Scale app 999'), findsNothing);

    controller.dispose();
    state.dispose();
  });
}

ApkSource _source(int index) => ApkSource(
  id: 'scale-source-$index',
  name: 'Scale source $index',
  homepage: 'source-$index.example',
  version: '1.0.0',
  description: 'Synthetic scale source',
  status: SourceStatus.enabled,
  builtIn: false,
);

AppListing _listing(int index) => AppListing(
  id: 'scale-app-$index',
  sourceId: 'apkvision-demo',
  name: 'Scale app $index',
  packageName: 'example.scale.$index',
  version: '1.0.0',
  size: '1 MB',
  updatedAt: '',
  category: '',
  sourceName: 'Scale source',
  iconUrl: '',
);
