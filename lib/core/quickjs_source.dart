import 'quickjs_source_stub.dart'
    if (dart.library.io) 'quickjs_source_io.dart'
    as implementation;

import 'source_runtime.dart';
import 'debug_log.dart';

Future<List<String>> discoverSourceAssets() =>
    implementation.discoverSourceAssets();

void setQuickJsRuntimeConcurrency(int value) =>
    implementation.setQuickJsRuntimeConcurrency(value);

Future<ApkSourceScript?> loadQuickJsSourceText(
  String scriptText, {
  required String sourceUrl,
  DebugLogStore? debug,
}) => implementation.loadQuickJsSourceText(
  scriptText,
  sourceUrl: sourceUrl,
  debug: debug,
);

Future<ApkSourceScript?> loadQuickJsSource(
  String assetPath, {
  DebugLogStore? debug,
}) => implementation.loadQuickJsSource(assetPath, debug: debug);
