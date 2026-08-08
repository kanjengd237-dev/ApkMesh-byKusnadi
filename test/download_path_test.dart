import 'package:apk_mesh/core/download_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a bounded APK name for an encoded URL path', () {
    final encodedPath = '${'a' * 400}_';

    final name = buildDownloadDestinationName(
      requestedName: encodedPath,
      sessionId: 'task-1',
    );

    expect(name, 'download.task-1.apk');
    expect(name.length, lessThanOrEqualTo(180));
  });

  test('keeps a normal filename and adds the session suffix', () {
    final name = buildDownloadDestinationName(
      requestedName: 'example.apk',
      sessionId: 'task-1',
    );

    expect(name, 'example.task-1.apk');
  });

  test('bounds an explicitly supplied long filename', () {
    final name = buildDownloadDestinationName(
      requestedName: '${'a' * 120}.apk',
      sessionId: 'task-1',
    );

    expect(name.length, lessThanOrEqualTo(180));
    expect(name, 'download.task-1.apk');
  });
}
