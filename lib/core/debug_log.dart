import 'package:flutter/foundation.dart';

enum DebugLogLevel { info, warning, error }

class DebugLogEntry {
  const DebugLogEntry({
    required this.time,
    required this.message,
    this.level = DebugLogLevel.info,
    this.category = 'app',
  });

  final DateTime time;
  final String message;
  final DebugLogLevel level;
  final String category;
}

class BrowserTabDebugInfo {
  const BrowserTabDebugInfo({
    required this.id,
    required this.url,
    required this.state,
    required this.startedAt,
    this.active = true,
  });

  final String id;
  final String url;
  final String state;
  final DateTime startedAt;
  final bool active;

  BrowserTabDebugInfo copyWith({
    String? url,
    String? state,
    DateTime? startedAt,
    bool? active,
  }) => BrowserTabDebugInfo(
    id: id,
    url: url ?? this.url,
    state: state ?? this.state,
    startedAt: startedAt ?? this.startedAt,
    active: active ?? this.active,
  );
}

class DebugLogStore extends ChangeNotifier {
  DebugLogStore({this.maxEntries = 300});

  final int maxEntries;
  final List<DebugLogEntry> _entries = [];

  List<DebugLogEntry> get entries => List.unmodifiable(_entries);

  void add(
    String message, {
    DebugLogLevel level = DebugLogLevel.info,
    String category = 'app',
  }) {
    _entries.add(
      DebugLogEntry(
        time: DateTime.now(),
        message: message,
        level: level,
        category: category,
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}
