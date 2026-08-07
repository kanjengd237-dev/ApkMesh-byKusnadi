import 'dart:typed_data';

import 'package:apk_mesh/core/source_import.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a single JavaScript source', () {
    final result = sourceScriptsFromBytes(
      Uint8List.fromList('globalThis.source = {};'.codeUnits),
      'example.js',
    );

    expect(result, hasLength(1));
    expect(result.single.name, 'example.js');
    expect(result.single.text, 'globalThis.source = {};');
  });

  test('reads every JavaScript source in a ZIP', () {
    final archive = Archive()
      ..addFile(ArchiveFile.string('first.js', 'globalThis.source = {};'))
      ..addFile(
        ArchiveFile.string('nested/second.js', 'globalThis.source = {};'),
      );
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));

    final result = sourceScriptsFromBytes(zip, 'sources.zip');

    expect(result.map((item) => item.name), ['first.js', 'nested/second.js']);
  });

  test('rejects unsupported source files', () {
    expect(
      () => sourceScriptsFromBytes(
        Uint8List.fromList(<int>[1, 2, 3]),
        'source.txt',
      ),
      throwsFormatException,
    );
  });
}
