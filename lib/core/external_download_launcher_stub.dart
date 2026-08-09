bool get supportsExternalDownloader => false;

Future<bool> launchExternalDownloader(
  Uri uri, {
  required String fileName,
  Map<String, String> headers = const {},
}) => throw UnsupportedError('当前平台不支持外部下载器');
