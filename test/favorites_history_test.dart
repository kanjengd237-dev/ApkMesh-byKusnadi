import 'package:apk_mesh/core/app_state.dart';
import 'package:apk_mesh/core/models.dart';
import 'package:apk_mesh/core/source_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists favorites and recent history', () async {
    final first = _listing('source-a', 'app-a', 'App A');
    final second = _listing('source-b', 'app-b', 'App B');
    final state = AppState(host: DemoHostApi());
    await _settleSettings();

    state.toggleFavorite(first);
    state.recordHistory(first);
    state.recordHistory(second);
    state.recordHistory(first);
    await _settleSettings();

    expect(state.favorites, [first]);
    expect(state.history, [first, second]);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('library.favorites'), hasLength(1));
    expect(preferences.getStringList('library.history'), hasLength(2));
    state.dispose();

    final restored = AppState(host: DemoHostApi());
    await _settleSettings();
    expect(restored.favorites, hasLength(1));
    expect(restored.favorites.single.name, 'App A');
    expect(restored.history.map((app) => app.name), ['App A', 'App B']);

    restored.toggleFavorite(first);
    restored.clearHistory();
    await _settleSettings();
    expect(restored.favorites, isEmpty);
    expect(restored.history, isEmpty);
    restored.dispose();
  });

  test('batch favorites only adds missing applications', () async {
    final state = AppState(host: DemoHostApi());
    await _settleSettings();
    final first = _listing('source-a', 'app-a', 'App A');
    final second = _listing('source-b', 'app-b', 'App B');

    expect(state.favoriteApps([first, first, second]), 2);
    expect(state.favoriteApps([first, second]), 0);
    expect(state.favorites.map((app) => app.name), ['App B', 'App A']);
    state.dispose();
  });

  test('keeps different sources separate and limits history', () async {
    final state = AppState(host: DemoHostApi());
    await _settleSettings();
    final sameIdFromFirstSource = _listing('source-a', 'same-id', 'A');
    final sameIdFromSecondSource = _listing('source-b', 'same-id', 'B');

    state.toggleFavorite(sameIdFromFirstSource);
    state.toggleFavorite(sameIdFromSecondSource);
    for (var index = 0; index < 105; index++) {
      state.recordHistory(_listing('source-a', 'history-$index', 'App $index'));
    }

    expect(state.favorites, hasLength(2));
    expect(state.history, hasLength(100));
    expect(state.history.first.name, 'App 104');
    expect(state.history.last.name, 'App 5');
    state.dispose();
  });
}

Future<void> _settleSettings() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

AppListing _listing(String sourceId, String id, String name) => AppListing(
  id: 'https://$sourceId.example/$id',
  sourceId: sourceId,
  name: name,
  packageName: 'com.example.$id',
  version: '1.0.0',
  size: '1 MB',
  updatedAt: '2026-01-01',
  category: 'Tools',
  sourceName: sourceId,
  iconUrl: 'https://$sourceId.example/$id.png',
  description: '$name description',
);
