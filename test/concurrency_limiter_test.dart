import 'dart:async';

import 'package:apk_mesh/core/concurrency_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adjustable semaphore enforces and raises its active limit', () async {
    final semaphore = AdjustableSemaphore(2);
    final firstWave = Completer<void>();
    final release = Completer<void>();
    var active = 0;
    var peak = 0;
    var started = 0;

    Future<void> operation() => semaphore.withPermit(() async {
      active += 1;
      started += 1;
      if (active > peak) peak = active;
      if (started == 2) firstWave.complete();
      await release.future;
      active -= 1;
    });

    final operations = List.generate(4, (_) => operation());
    await firstWave.future;
    expect(started, 2);
    expect(semaphore.waiting, 2);

    semaphore.limit = 3;
    await Future<void>.delayed(Duration.zero);
    expect(started, 3);
    expect(peak, 3);

    release.complete();
    await Future.wait(operations);
    expect(semaphore.active, 0);
    expect(semaphore.waiting, 0);
  });
}
