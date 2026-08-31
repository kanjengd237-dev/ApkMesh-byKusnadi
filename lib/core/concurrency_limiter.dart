import 'dart:async';
import 'dart:collection';

class AdjustableSemaphore {
  AdjustableSemaphore(int limit) : _limit = _validate(limit);

  int _limit;
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  int get limit => _limit;
  int get active => _active;
  int get waiting => _waiting.length;

  set limit(int value) {
    _limit = _validate(value);
    _drain();
  }

  Future<void> acquire() {
    if (_active < _limit) {
      _active += 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiting.addLast(completer);
    return completer.future;
  }

  void release() {
    if (_active == 0) throw StateError('No permits to release');
    _active -= 1;
    _drain();
  }

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }

  void _drain() {
    while (_active < _limit && _waiting.isNotEmpty) {
      _active += 1;
      _waiting.removeFirst().complete();
    }
  }

  static int _validate(int value) {
    if (value < 1)
      throw ArgumentError.value(value, 'limit', 'must be greater than 0');
    return value;
  }
}
