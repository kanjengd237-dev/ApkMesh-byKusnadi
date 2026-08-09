import 'source_runtime.dart';
import 'debug_log.dart';

Future<List<String>> discoverSourceAssets() async => const [];

void setQuickJsRuntimeConcurrency(int value) {}

Future<ApkSourceScript?> loadQuickJsSourceText(
  String scriptText, {
  required String sourceUrl,
  DebugLogStore? debug,
}) async => null;

Future<ApkSourceScript?> loadQuickJsSource(
  String assetPath, {
  DebugLogStore? debug,
}) async => null;
