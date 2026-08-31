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
    throw UnsupportedError(
      'External downloader is not supported on this platform',
    );
  }
  return await _channel.invokeMethod<bool>('launch', {
        'url': uri.toString(),
        'fileName': fileName,
        'headers': headers,
      }) ??
      false;
}
