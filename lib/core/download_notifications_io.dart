import 'dart:io';

import 'package:flutter/services.dart';

class DownloadNotifications {
  static const _channel = MethodChannel('com.apkmesh/download_notifications');

  Future<void> requestPermission() => _invoke('requestPermission');

  Future<void> showProgress({
    required String id,
    required String title,
    required int received,
    required int? total,
  }) => _invoke('showProgress', {
    'id': id,
    'title': title,
    'received': received,
    'total': total,
  });

  Future<void> showCompleted({
    required String id,
    required String title,
    required String path,
  }) => _invoke('showCompleted', {'id': id, 'title': title, 'path': path});

  Future<void> showFailed({
    required String id,
    required String title,
    required String error,
  }) => _invoke('showFailed', {'id': id, 'title': title, 'error': error});

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Notifications are optional on platforms without a native implementation.
    } on PlatformException {
      // A denied notification permission must not interrupt the download itself.
    }
  }
}
