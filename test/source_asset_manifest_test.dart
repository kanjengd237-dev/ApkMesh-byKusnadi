import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every built-in JavaScript source has a valid lazy manifest', () async {
    final directory = Directory('assets/sources');
    final scripts =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.js'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final ids = <String>{};

    expect(scripts, isNotEmpty);
    for (final script in scripts) {
      final sidecar = File('${script.path}.manifest.json');
      expect(sidecar.existsSync(), isTrue, reason: script.path);
      final manifest = jsonDecode(await sidecar.readAsString());
      expect(manifest, isA<Map<String, dynamic>>());
      final data = manifest as Map<String, dynamic>;
      expect(data['id'], isA<String>());
      expect(ids.add(data['id'] as String), isTrue, reason: script.path);
      expect(data['name'], isA<String>());
      expect(data['permissions'], isA<Map<String, dynamic>>());
      expect(data['capabilities'], isA<Map<String, dynamic>>());
    }
  });
}
