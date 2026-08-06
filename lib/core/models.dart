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
    this.lastSync,
  });

  final String id;
  final String name;
  final String homepage;
  final String version;
  final String description;
  final SourceStatus status;
  final bool builtIn;
  final DateTime? lastSync;

  ApkSource copyWith({SourceStatus? status, DateTime? lastSync}) => ApkSource(
    id: id,
    name: name,
    homepage: homepage,
    version: version,
    description: description,
    status: status ?? this.status,
    builtIn: builtIn,
    lastSync: lastSync ?? this.lastSync,
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

class SourceDownload {
  const SourceDownload({
    required this.label,
    required this.url,
    required this.size,
  });
  final String label;
  final String url;
  final String size;
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
