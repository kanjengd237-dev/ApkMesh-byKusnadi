import 'package:path/path.dart' as p;

const _maxDownloadFileNameLength = 180;
const _maxDownloadSessionIdLength = 48;

String buildDownloadDestinationName({
  required String requestedName,
  required String sessionId,
}) {
  var name = p
      .basename(requestedName.trim())
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  var safeSessionId = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safeSessionId.isEmpty) safeSessionId = 'download';
  if (safeSessionId.length > _maxDownloadSessionIdLength) {
    safeSessionId = safeSessionId.substring(0, _maxDownloadSessionIdLength);
  }

  if (name.isEmpty || name == '.' || name == '..' || name.length > 96) {
    name = 'download.apk';
  }

  final extension = p.extension(name);
  final stem = extension.isEmpty ? name : p.withoutExtension(name);
  final suffix = '.$safeSessionId$extension';
  final maxStemLength = _maxDownloadFileNameLength - suffix.length;
  final boundedStem = stem.length > maxStemLength
      ? stem.substring(0, maxStemLength)
      : stem;
  return '$boundedStem$suffix';
}
