import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class SourceScriptFile {
  const SourceScriptFile({required this.name, this.text, this.error});

  final String name;
  final String? text;
  final Object? error;
}

List<SourceScriptFile> sourceScriptsFromBytes(
  Uint8List bytes,
  String fileName,
) {
  final extension = fileName.split('.').last.toLowerCase();
  final isZip = extension == 'zip' || _looksLikeZip(bytes);
  if (!isZip && extension != 'js') {
    throw const FormatException('只支持 .js 或 .zip 源文件');
  }
  if (isZip) return _scriptsFromZip(bytes);
  try {
    return [
      SourceScriptFile(name: fileName, text: _decodeScript(bytes), error: null),
    ];
  } catch (error) {
    return [SourceScriptFile(name: fileName, error: error)];
  }
}

List<SourceScriptFile> _scriptsFromZip(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final scripts = archive.files
      .where((file) => file.isFile && file.name.toLowerCase().endsWith('.js'))
      .map((file) {
        try {
          return SourceScriptFile(
            name: file.name,
            text: _decodeScript(file.content),
            error: null,
          );
        } catch (error) {
          return SourceScriptFile(name: file.name, error: error);
        }
      })
      .toList();
  if (scripts.isEmpty) {
    throw const FormatException('ZIP 中没有 JS 源脚本');
  }
  return scripts;
}

String _decodeScript(dynamic content) {
  if (content is! List<int>) {
    throw const FormatException('无法读取 JS 源脚本');
  }
  try {
    return utf8.decode(content);
  } on FormatException {
    throw const FormatException('源脚本必须使用 UTF-8 编码');
  }
}

bool _looksLikeZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4b &&
    (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
    (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
