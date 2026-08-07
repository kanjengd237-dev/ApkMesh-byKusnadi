import 'dart:io';

import 'package:apk_mesh/core/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores request metadata and response content', () {
    final store = DebugLogStore();
    final id = store.beginRequest(
      'https://example.com/search',
      headers: const {'accept': 'text/html'},
    );

    expect(store.requests.single.state, DebugRequestState.pending);
    store.completeRequest(
      id,
      statusCode: 200,
      responseHeaders: const {'content-type': 'text/html'},
      responseBody: '<html>result</html>',
    );

    final request = store.requests.single;
    expect(request.statusCode, 200);
    expect(request.requestHeaders['accept'], 'text/html');
    expect(request.responseHeaders['content-type'], 'text/html');
    expect(request.responseBody, '<html>result</html>');
    expect(request.duration, isNotNull);
  });

  test('source JavaScript declares its own debug projects', () async {
    final source = await File('assets/sources/apkvision.js').readAsString();

    expect(source, contains('debugProjects: ['));
    expect(source, contains("id: 'search-keyword'"));
    expect(source, contains("id: 'app-details'"));
    expect(source, contains('async search(query, page = 1)'));
    expect(source, contains('async home()'));
    expect(source, contains('async category(categoryId)'));
    expect(source, contains('async debug(projectId, input)'));
  });
}
