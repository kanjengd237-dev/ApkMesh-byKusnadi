bool get supportsExternalDownloader => false;

Future<bool> launchExternalDownloader(
  Uri uri, {
  required String fileName,
  Map<String, String> headers = const {},
}) => throw UnsupportedError(
  'External downloader is not supported on this platform',
);
