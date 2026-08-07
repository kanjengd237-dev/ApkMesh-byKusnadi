enum SourceStatus { enabled, disabled, error }

class ApkSource {
  const ApkSource({
    required this.id,
    required this.name,
    required this.homepage,
    required this.version,
    required this.description,
    required this.status,
    required this.builtIn,
    this.homeSource = false,
    this.lastSync,
  });

  final String id;
  final String name;
  final String homepage;
  final String version;
  final String description;
  final SourceStatus status;
  final bool builtIn;
  final bool homeSource;
  final DateTime? lastSync;

  ApkSource copyWith({
    SourceStatus? status,
    bool? homeSource,
    DateTime? lastSync,
  }) => ApkSource(
    id: id,
    name: name,
    homepage: homepage,
    version: version,
    description: description,
    status: status ?? this.status,
    builtIn: builtIn,
    homeSource: homeSource ?? this.homeSource,
    lastSync: lastSync ?? this.lastSync,
  );
}

class SourceCategory {
  const SourceCategory({
    required this.id,
    required this.name,
    required this.sourceId,
    required this.sourceName,
    this.description = '',
    this.apps = const [],
  });

  final String id;
  final String name;
  final String sourceId;
  final String sourceName;
  final String description;
  final List<AppListing> apps;

  SourceCategory copyWith({List<AppListing>? apps}) => SourceCategory(
    id: id,
    name: name,
    sourceId: sourceId,
    sourceName: sourceName,
    description: description,
    apps: apps ?? this.apps,
  );
}

class SourceHome {
  const SourceHome({this.recommended = const [], this.categories = const []});

  final List<AppListing> recommended;
  final List<SourceCategory> categories;

  SourceHome merge(SourceHome other) => SourceHome(
    recommended: [...recommended, ...other.recommended],
    categories: [...categories, ...other.categories],
  );
}

class AppListing {
  const AppListing({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.packageName,
    required this.version,
    required this.size,
    required this.updatedAt,
    required this.category,
    required this.sourceName,
    required this.iconUrl,
    required this.summary,
  });

  final String id;
  final String sourceId;
  final String name;
  final String packageName;
  final String version;
  final String size;
  final String updatedAt;
  final String category;
  final String sourceName;
  final String iconUrl;
  final String summary;
}

class SourceDebugProject {
  const SourceDebugProject({
    required this.sourceId,
    required this.sourceName,
    required this.id,
    required this.name,
    required this.description,
    required this.inputLabel,
    required this.placeholder,
    this.defaultInput = '',
  });

  final String sourceId;
  final String sourceName;
  final String id;
  final String name;
  final String description;
  final String inputLabel;
  final String placeholder;
  final String defaultInput;

  String get key => '$sourceId:$id';
}

class DebugProjectResult {
  const DebugProjectResult({
    required this.projectId,
    required this.sourceId,
    required this.title,
    required this.summary,
    required this.data,
  });

  final String projectId;
  final String sourceId;
  final String title;
  final String summary;
  final dynamic data;
}

class SourceDownload {
  const SourceDownload({
    required this.label,
    required this.url,
    required this.size,
    this.headers = const {},
  });
  final String label;
  final String url;
  final String size;
  final Map<String, String> headers;
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => '下载已取消';
}

enum DownloadStatus { downloading, paused, completed, failed, canceled }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.file,
    required this.sourceId,
    required this.status,
    required this.startedAt,
    this.received = 0,
    this.total,
    this.filePath,
    this.error,
    this.completedAt,
  });

  static const _notProvided = Object();

  final String id;
  final SourceDownload file;
  final String sourceId;
  final DownloadStatus status;
  final DateTime startedAt;
  final int received;
  final int? total;
  final String? filePath;
  final String? error;
  final DateTime? completedAt;

  double? get progress =>
      total != null && total! > 0 ? (received / total!).clamp(0.0, 1.0) : null;

  DownloadTask copyWith({
    DownloadStatus? status,
    DateTime? startedAt,
    int? received,
    Object? total = _notProvided,
    Object? filePath = _notProvided,
    Object? error = _notProvided,
    Object? completedAt = _notProvided,
  }) => DownloadTask(
    id: id,
    file: file,
    sourceId: sourceId,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    received: received ?? this.received,
    total: identical(total, _notProvided) ? this.total : total as int?,
    filePath: identical(filePath, _notProvided)
        ? this.filePath
        : filePath as String?,
    error: identical(error, _notProvided) ? this.error : error as String?,
    completedAt: identical(completedAt, _notProvided)
        ? this.completedAt
        : completedAt as DateTime?,
  );
}

class AppDetails extends AppListing {
  const AppDetails({
    required super.id,
    required super.sourceId,
    required super.name,
    required super.packageName,
    required super.version,
    required super.size,
    required super.updatedAt,
    required super.category,
    required super.sourceName,
    required super.iconUrl,
    required super.summary,
    required this.description,
    required this.screenshots,
    required this.comments,
    required this.downloads,
  });

  final String description;
  final List<String> screenshots;
  final List<String> comments;
  final List<SourceDownload> downloads;
}
