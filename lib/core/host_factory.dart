import 'source_runtime.dart';
import 'debug_log.dart';

import 'host_factory_stub.dart'
    if (dart.library.io) 'host_factory_io.dart'
    as implementation;

SourceHostApi createPlatformHostApi({DebugLogStore? debug}) =>
    implementation.createPlatformHostApi(debug: debug);
