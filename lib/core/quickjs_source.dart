import 'quickjs_source_stub.dart'
    if (dart.library.io) 'quickjs_source_io.dart'
    as implementation;

import 'source_runtime.dart';
import 'debug_log.dart';

Future<ApkSourceScript?> loadQuickJsSource(
  String assetPath, {
  DebugLogStore? debug,
}) => implementation.loadQuickJsSource(assetPath, debug: debug);
