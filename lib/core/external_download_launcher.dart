import 'external_download_launcher_stub.dart'
    if (dart.library.io) 'external_download_launcher_io.dart'
    as implementation;

bool get supportsExternalDownloader =>
    implementation.supportsExternalDownloader;

Future<bool> launchExternalDownloader(
  Uri uri, {
  required String fileName,
  Map<String, String> headers = const {},
}) => implementation.launchExternalDownloader(
  uri,
  fileName: fileName,
  headers: headers,
);
