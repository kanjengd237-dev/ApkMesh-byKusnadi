import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class DownloadStore {
  DownloadStore();

  static const _fileName = 'downloads.json';
  File? _file;

  bool get _isFlutterTest => Platform.environment['FLUTTER_TEST'] == 'true';

  Future<File> _storageFile() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return _file ??= File(p.join(directory.path, _fileName));
  }

  Future<List<DownloadTask>> load() async {
    if (_isFlutterTest) return const [];
    final file = await _storageFile();
    if (!await file.exists()) return const [];

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map || decoded['tasks'] is! List) {
      throw const FormatException('下载任务存储格式无效');
    }

    final tasks = <DownloadTask>[];
    for (final value in decoded['tasks'] as List) {
      if (value is! Map) continue;
      try {
        tasks.add(DownloadTask.fromJson(Map<String, dynamic>.from(value)));
      } on Object {
        // Ignore one damaged task while retaining the rest of the queue.
      }
    }
    return tasks;
  }

  Future<void> save(List<DownloadTask> tasks) async {
    if (_isFlutterTest) return;
    final file = await _storageFile();
    final temporary = File('${file.path}.tmp');
    final payload = jsonEncode({
      'version': 1,
      'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
    });
    await temporary.writeAsString(payload, flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}

DownloadStore createDownloadStore() => DownloadStore();
