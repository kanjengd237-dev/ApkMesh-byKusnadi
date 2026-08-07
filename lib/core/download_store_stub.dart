import 'models.dart';

class DownloadStore {
  const DownloadStore();

  Future<List<DownloadTask>> load() async => const [];

  Future<void> save(List<DownloadTask> tasks) async {}
}

DownloadStore createDownloadStore() => const DownloadStore();
