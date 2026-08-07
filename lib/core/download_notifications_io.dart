import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class DownloadNotifications {
  DownloadNotifications({this.onAction}) {
    _channel.setMethodCallHandler(_handleMethodCall);
    unawaited(_invoke('notificationsReady'));
  }

  static const _channel = MethodChannel('com.apkmesh/download_notifications');

  final void Function(String id, String action)? onAction;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'notificationAction') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final id = arguments['id'];
    final action = arguments['action'];
    if (id is String && action is String) onAction?.call(id, action);
  }

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

  Future<void> showPaused({
    required String id,
    required String title,
    required int received,
    required int? total,
  }) => _invoke('showPaused', {
    'id': id,
    'title': title,
    'received': received,
    'total': total,
  });

  Future<void> cancel(String id) => _invoke('cancel', {'id': id});

  Future<void> showCompleted({required String id, required String title}) =>
      _invoke('showCompleted', {'id': id, 'title': title});

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
