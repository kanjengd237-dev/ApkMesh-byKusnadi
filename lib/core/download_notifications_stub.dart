class DownloadNotifications {
  const DownloadNotifications({this.onAction});

  final void Function(String id, String action)? onAction;

  Future<void> requestPermission() async {}

  Future<void> showProgress({
    required String id,
    required String title,
    required int received,
    required int? total,
  }) async {}

  Future<void> showPaused({
    required String id,
    required String title,
    required int received,
    required int? total,
  }) async {}

  Future<void> cancel(String id) async {}

  Future<void> showCompleted({
    required String id,
    required String title,
  }) async {}

  Future<void> showFailed({
    required String id,
    required String title,
    required String error,
  }) async {}
}
