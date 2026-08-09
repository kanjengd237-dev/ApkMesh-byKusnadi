import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.apkmesh/external_download');

bool get supportsExternalDownloader => Platform.isAndroid;

Future<bool> launchExternalDownloader(
  Uri uri, {
  required String fileName,
  Map<String, String> headers = const {},
}) async {
  if (!supportsExternalDownloader) {
    throw UnsupportedError('当前平台不支持外部下载器');
  }
  return await _channel.invokeMethod<bool>('launch', {
        'url': uri.toString(),
        'fileName': fileName,
        'headers': headers,
      }) ??
      false;
}
