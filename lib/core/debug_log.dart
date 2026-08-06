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

enum DebugRequestState { pending, completed, failed }

class DebugRequestEntry {
  const DebugRequestEntry({
    required this.id,
    required this.method,
    required this.url,
    required this.startedAt,
    required this.state,
    this.requestHeaders = const {},
    this.responseHeaders = const {},
    this.statusCode,
    this.contentType,
    this.responseBody,
    this.error,
    this.completedAt,
  });

  final String id;
  final String method;
  final String url;
  final DateTime startedAt;
  final DebugRequestState state;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final int? statusCode;
  final String? contentType;
  final String? responseBody;
  final String? error;
  final DateTime? completedAt;

  Duration? get duration => completedAt?.difference(startedAt);

  DebugRequestEntry copyWith({
    DebugRequestState? state,
    Map<String, String>? responseHeaders,
    int? statusCode,
    String? contentType,
    String? responseBody,
    String? error,
    DateTime? completedAt,
  }) => DebugRequestEntry(
    id: id,
    method: method,
    url: url,
    startedAt: startedAt,
    state: state ?? this.state,
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders ?? this.responseHeaders,
    statusCode: statusCode ?? this.statusCode,
    contentType: contentType ?? this.contentType,
    responseBody: responseBody ?? this.responseBody,
    error: error ?? this.error,
    completedAt: completedAt ?? this.completedAt,
  );
}

class DebugLogStore extends ChangeNotifier {
  DebugLogStore({this.maxEntries = 300, this.maxRequests = 100});

  final int maxEntries;
  final int maxRequests;
  final List<DebugLogEntry> _entries = [];
  final List<DebugRequestEntry> _requests = [];
  int _requestSequence = 0;

  List<DebugLogEntry> get entries => List.unmodifiable(_entries);
  List<DebugRequestEntry> get requests => List.unmodifiable(_requests);

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

  String beginRequest(
    String url, {
    String method = 'GET',
    Map<String, String> headers = const {},
  }) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';
    _requests.add(
      DebugRequestEntry(
        id: id,
        method: method,
        url: url,
        startedAt: DateTime.now(),
        state: DebugRequestState.pending,
        requestHeaders: Map.unmodifiable({...headers}),
      ),
    );
    if (_requests.length > maxRequests) {
      _requests.removeRange(0, _requests.length - maxRequests);
    }
    notifyListeners();
    return id;
  }

  void completeRequest(
    String id, {
    required int statusCode,
    required Map<String, String> responseHeaders,
    required String responseBody,
  }) {
    _updateRequest(
      id,
      (request) => request.copyWith(
        state: DebugRequestState.completed,
        statusCode: statusCode,
        responseHeaders: Map.unmodifiable({...responseHeaders}),
        contentType: responseHeaders['content-type'],
        responseBody: _limitBody(responseBody),
        completedAt: DateTime.now(),
      ),
    );
  }

  void failRequest(
    String id,
    Object error, {
    int? statusCode,
    Map<String, String> responseHeaders = const {},
    String? responseBody,
  }) {
    _updateRequest(
      id,
      (request) => request.copyWith(
        state: DebugRequestState.failed,
        statusCode: statusCode,
        responseHeaders: Map.unmodifiable({...responseHeaders}),
        contentType: responseHeaders['content-type'],
        responseBody: responseBody == null ? null : _limitBody(responseBody),
        error: error.toString(),
        completedAt: DateTime.now(),
      ),
    );
  }

  void _updateRequest(
    String id,
    DebugRequestEntry Function(DebugRequestEntry request) update,
  ) {
    final index = _requests.indexWhere((request) => request.id == id);
    if (index == -1) return;
    _requests[index] = update(_requests[index]);
    notifyListeners();
  }

  static String _limitBody(String value) {
    const limit = 120000;
    if (value.length <= limit) return value;
    return '${value.substring(0, limit)}\\n... [响应内容已截断]';
  }

  void clear() {
    if (_entries.isEmpty && _requests.isEmpty) return;
    _entries.clear();
    _requests.clear();
    notifyListeners();
  }
}
