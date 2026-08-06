class DownloadNotifications {
  Future<void> requestPermission() async {}

  Future<void> showProgress({
    required String id,
    required String title,
    required int received,
    required int? total,
  }) async {}

  Future<void> showCompleted({
    required String id,
    required String title,
    required String path,
  }) async {}

  Future<void> showFailed({
    required String id,
    required String title,
    required String error,
  }) async {}
}
