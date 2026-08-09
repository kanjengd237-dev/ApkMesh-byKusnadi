import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/source_runtime.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_result_tile.dart';
import '../widgets/package_lookup_sheet.dart';
import '../widgets/screenshot_gallery.dart';
import 'downloads_page.dart';
import 'home_page.dart';

void showAppDetails(BuildContext context, AppState state, AppListing app) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DetailsSheet(app: app, state: state),
  );
}

class DetailsSheet extends StatefulWidget {
  const DetailsSheet({required this.app, required this.state, super.key});
  final AppListing app;
  final AppState state;

  @override
  State<DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<DetailsSheet> {
  AppDetails? detail;
  List<SourceDownloadProgress> downloads = const [];
  DetailLoadPhase phase = DetailLoadPhase.loadingDetails;
  String? error;
  bool _openingBrowser = false;
  bool _loadingDetails = false;
  bool? _translationOverride;

  bool get _showTranslation =>
      _translationOverride ?? widget.state.translationSettings.autoTranslate;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    if (app is AppDetails) {
      detail = app;
      downloads = app.downloads
          .map(
            (file) => SourceDownloadProgress(
              candidate: SourceDownloadCandidate(
                label: file.label,
                url: file.url,
                size: file.size,
                headers: file.headers,
              ),
              files: [file],
            ),
          )
          .toList(growable: false);
      phase = DetailLoadPhase.complete;
      widget.state.cacheDetails(widget.app, app);
    } else if (widget.state.cachedDetailsFor(app) case final cached?) {
      detail = cached.details;
      downloads = cached.downloads;
      phase = cached.phase;
      error = cached.error;
    } else {
      unawaited(_loadDetails());
    }
  }

  Future<void> _loadDetails({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loadingDetails = true;
        if (forceRefresh) {
          error = null;
          phase = DetailLoadPhase.loadingDetails;
        }
      });
    }
    try {
      await widget.state.loadDetails(
        widget.app,
        forceRefresh: forceRefresh,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            detail = progress.details;
            downloads = progress.downloads;
            phase = progress.phase;
            error = progress.error;
          });
        },
      );
    } catch (value) {
      if (!mounted) return;
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _refreshDetails() => _loadDetails(forceRefresh: true);

  Future<void> _openInBrowser() async {
    if (_openingBrowser) return;
    final url = (detail?.id ?? widget.app.id).trim();
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showDetailsMessage('当前应用没有可打开的网页地址');
      return;
    }

    late final SourcePolicy policy;
    try {
      policy = widget.state.registry.scriptFor(widget.app.sourceId).policy;
    } catch (value) {
      _showDetailsMessage('无法读取源权限：$value');
      return;
    }
    if (!policy.allowBrowser || !policy.permits(uri)) {
      _showDetailsMessage('该源不允许打开此网页');
      return;
    }

    setState(() => _openingBrowser = true);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('系统没有可用的浏览器');
    } catch (value) {
      if (mounted) _showDetailsMessage('浏览器打开失败：$value');
    } finally {
      if (mounted) setState(() => _openingBrowser = false);
    }
  }

  Future<void> _switchSource() async {
    final query = (detail?.name ?? widget.app.name).trim();
    if (query.isEmpty) {
      _showDetailsMessage('当前应用没有可用于搜索的名称');
      return;
    }

    final selected = await showModalBottomSheet<AppListing>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SourceMatchSheet(
        query: query,
        current: widget.app,
        state: widget.state,
      ),
    );
    if (!mounted || selected == null) return;
    showAppDetails(context, widget.state, selected);
  }

  void _toggleTranslation() {
    final next = !_showTranslation;
    setState(() => _translationOverride = next);
    if (next) {
      final app = detail ?? widget.app;
      widget.state.ensureTranslations([app.name, app.description]);
    }
  }

  void _showDetailsMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final displayApp = detail ?? widget.app;
    if (_showTranslation) {
      widget.state.ensureTranslations([
        displayApp.name,
        displayApp.description,
      ]);
    }
    final displayedName = _showTranslation
        ? widget.state.translatedText(displayApp.name) ?? displayApp.name
        : displayApp.name;
    final displayedDescription = _showTranslation
        ? widget.state.translatedText(displayApp.description) ??
              displayApp.description
        : displayApp.description;
    final metadataChips = buildAppInfoChips(
      displayApp,
      onPackageTap: displayApp.packageName.trim().isEmpty
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => PackageLookupSheet(
                packageName: displayApp.packageName,
                state: widget.state,
                onAppTap: (app) => showAppDetails(context, widget.state, app),
              ),
            ),
    );
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .45,
        maxChildSize: .94,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                AppIcon(url: displayApp.iconUrl),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayedName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (metadataChips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FadingHorizontalChips(children: metadataChips),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (detail == null && error == null)
              const SearchLoadingView(
                icon: Icons.article_outlined,
                label: '正在加载详情',
              ),
            if (error != null)
              Text(detail == null ? '源详情加载失败：$error' : '下载链接解析失败：$error'),
            if (detail != null)
              ..._buildDetailContent(
                context,
                detail!,
                description: displayedDescription,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '刷新详情',
          onPressed: _loadingDetails ? null : _refreshDetails,
          icon: _loadingDetails
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '浏览器打开',
          onPressed: _openingBrowser ? null : _openInBrowser,
          icon: _openingBrowser
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_browser_outlined),
        ),
        IconButton(
          tooltip: _showTranslation ? '显示原文' : '翻译名称和简介',
          onPressed: _toggleTranslation,
          icon: widget.state.isTranslationLoading((detail ?? widget.app).name)
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _showTranslation ? Icons.translate : Icons.translate_outlined,
                ),
        ),
        IconButton(
          tooltip: '切换源',
          onPressed: _switchSource,
          icon: const Icon(Icons.swap_horiz),
        ),
      ],
    );
  }

  List<Widget> _buildDetailContent(
    BuildContext context,
    AppDetails detail, {
    required String description,
  }) {
    final content = <Widget>[_buildDetailActions(context)];
    content.add(const SizedBox(height: 8));
    if (description.trim().isNotEmpty) {
      content.add(ExpandableDescription(text: description));
      content.add(const SizedBox(height: 20));
    }
    if (detail.screenshots.isNotEmpty) {
      content.add(Text('截图', style: Theme.of(context).textTheme.titleMedium));
      content.add(const SizedBox(height: 8));
      content.add(ScreenshotGallery(urls: detail.screenshots));
      content.add(const SizedBox(height: 20));
    }
    if (downloads.isNotEmpty || phase == DetailLoadPhase.resolvingDownloads) {
      content.add(
        Row(
          children: [
            Expanded(
              child: Text(
                '下载文件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (phase == DetailLoadPhase.resolvingDownloads &&
                downloads.isNotEmpty)
              Text(
                '${downloads.where((item) => item.completed).length}/${downloads.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      );
      content.add(const SizedBox(height: 8));
      if (downloads.isEmpty) {
        content.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('正在查找下载项…'),
          ),
        );
      } else {
        final rows = <Widget>[];
        for (final progress in downloads) {
          final files = progress.files;
          if (files != null && files.isNotEmpty) {
            rows.addAll(
              files.map(
                (file) => SourceDownloadTile(
                  file: file,
                  sourceId: widget.app.sourceId,
                  state: widget.state,
                  app: detail,
                  showDivider: true,
                ),
              ),
            );
          } else {
            rows.add(PendingSourceDownloadTile(progress: progress));
          }
        }
        for (var index = 0; index < rows.length; index += 1) {
          if (rows[index] is SourceDownloadTile) {
            final tile = rows[index] as SourceDownloadTile;
            rows[index] = SourceDownloadTile(
              file: tile.file,
              sourceId: tile.sourceId,
              state: tile.state,
              app: tile.app,
              showDivider: index < rows.length - 1,
            );
          }
        }
        content.addAll(rows);
      }
    }
    if (detail.comments.isNotEmpty) {
      if (content.isNotEmpty) content.add(const SizedBox(height: 20));
      content.add(Text('评论', style: Theme.of(context).textTheme.titleMedium));
      content.addAll(
        detail.comments.map(
          (comment) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.comment_outlined),
            title: Text(comment),
          ),
        ),
      );
    }
    return content;
  }
}

class FadingHorizontalChips extends StatefulWidget {
  const FadingHorizontalChips({required this.children, super.key});

  final List<Widget> children;

  @override
  State<FadingHorizontalChips> createState() => _FadingHorizontalChipsState();
}

class _FadingHorizontalChipsState extends State<FadingHorizontalChips> {
  late final ScrollController _controller;
  bool _fadeLeft = false;
  bool _fadeRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateFadeEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFadeEdges());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateFadeEdges)
      ..dispose();
    super.dispose();
  }

  void _updateFadeEdges() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final fadeLeft = position.pixels > 0.5;
    final fadeRight = position.pixels < position.maxScrollExtent - 0.5;
    if (!mounted || (fadeLeft == _fadeLeft && fadeRight == _fadeRight)) {
      return;
    }
    setState(() {
      _fadeLeft = fadeLeft;
      _fadeRight = fadeRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chips = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (var index = 0; index < widget.children.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            widget.children[index],
          ],
        ],
      ),
    );
    if (!_fadeLeft && !_fadeRight) {
      return SizedBox(height: 40, child: chips);
    }

    final colors = _fadeLeft && _fadeRight
        ? <Color>[
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ]
        : _fadeLeft
        ? <Color>[Colors.transparent, Colors.black, Colors.black]
        : <Color>[Colors.black, Colors.black, Colors.transparent];
    final stops = _fadeLeft && _fadeRight
        ? const [0.0, 0.08, 0.92, 1.0]
        : _fadeLeft
        ? const [0.0, 0.08, 1.0]
        : const [0.0, 0.92, 1.0];
    return SizedBox(
      height: 40,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) =>
            LinearGradient(colors: colors, stops: stops).createShader(bounds),
        child: chips,
      ),
    );
  }
}

class SourceMatchSheet extends StatefulWidget {
  const SourceMatchSheet({
    required this.query,
    required this.current,
    required this.state,
    super.key,
  });

  final String query;
  final AppListing current;
  final AppState state;

  @override
  State<SourceMatchSheet> createState() => _SourceMatchSheetState();
}

class _SourceMatchSheetState extends State<SourceMatchSheet> {
  final _listKey = GlobalKey<AnimatedListState>();
  final _seen = <String>{};
  final _sourceErrors = <String, String>{};
  final _matches = <AppListing>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    try {
      await widget.state.searchPage(
        widget.query,
        page: 1,
        onSourcePage: _handleSourcePage,
      );
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (value) {
      if (!mounted) return;
      setState(() => _loading = false);
      _sourceErrors['search'] = value.toString();
    }
  }

  void _handleSourcePage(SourceSearchPage page) {
    if (!page.succeeded) {
      _sourceErrors[page.sourceName] = page.error ?? '源搜索失败';
      return;
    }
    for (final app in page.results) {
      final key = '${app.sourceId}:${app.id}';
      final isCurrent =
          app.sourceId == widget.current.sourceId &&
          app.id == widget.current.id;
      if (isCurrent ||
          app.name.trim() != widget.query ||
          !_seen.add(key) ||
          !mounted) {
        continue;
      }
      final index = _matches.length;
      setState(() => _matches.add(app));
      _listKey.currentState?.insertItem(
        index,
        duration: const Duration(milliseconds: 260),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .68,
        minChildSize: .38,
        maxChildSize: .94,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '切换源',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  widget.query,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 3,
              child: _loading
                  ? const LinearProgressIndicator(minHeight: 3)
                  : const SizedBox.shrink(),
            ),
            Expanded(child: _buildResults(controller)),
            if (!_loading && _sourceErrors.isNotEmpty && _matches.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  '部分源搜索失败：${_sourceErrors.keys.join('、')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ScrollController controller) {
    if (_matches.isEmpty) {
      if (_loading) {
        return const SearchLoadingView(
          icon: Icons.manage_search,
          label: '正在搜索',
        );
      }
      final failed = _sourceErrors.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(failed ? Icons.error_outline : Icons.search_off, size: 48),
              const SizedBox(height: 12),
              Text(
                failed ? '同名应用搜索失败' : '没有找到完全同名的应用',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                failed ? _sourceErrors.values.join('\n') : '仅展示所有启用源的第一页结果。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedList(
      key: _listKey,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      initialItemCount: _matches.length,
      itemBuilder: (context, index, animation) {
        final app = _matches[index];
        return SizeTransition(
          sizeFactor: animation,
          child: AppResultTile(
            app: app,
            state: widget.state,
            onOpen: (selected) => Navigator.of(context).pop(selected),
            showDivider: index < _matches.length - 1,
          ),
        );
      },
    );
  }
}

class PendingSourceDownloadTile extends StatelessWidget {
  const PendingSourceDownloadTile({required this.progress, super.key});

  final SourceDownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = progress.error != null;
    final empty = progress.files != null && progress.files!.isEmpty;
    final detail =
        progress.error ?? (empty ? '未找到可用下载链接' : progress.candidate.size);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 40,
            child: Align(
              alignment: Alignment.topLeft,
              child: failed
                  ? SizedBox.square(
                      dimension: 22,
                      child: Icon(Icons.error_outline, color: scheme.error),
                    )
                  : progress.resolving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : SizedBox.square(
                      dimension: 22,
                      child: Icon(
                        Icons.link_off_outlined,
                        color: scheme.outline,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress.candidate.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExpandableDescription extends StatefulWidget {
  const ExpandableDescription({required this.text, super.key});
  final String text;

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = DefaultTextStyle.of(context).style;
        final scheme = Theme.of(context).colorScheme;
        final suffixStyle = textStyle.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        );
        final direction = Directionality.of(context);
        final fullPainter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          maxLines: 3,
          textDirection: direction,
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = fullPainter.didExceedMaxLines;
        final span = expanded || !canExpand
            ? TextSpan(text: widget.text, style: textStyle)
            : _collapsedSpan(
                textStyle: textStyle,
                suffixStyle: suffixStyle,
                direction: direction,
                maxWidth: constraints.maxWidth > 16
                    ? constraints.maxWidth - 16
                    : constraints.maxWidth,
              );
        final text = AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Text.rich(
            span,
            maxLines: expanded || !canExpand ? null : 3,
            overflow: TextOverflow.clip,
          ),
        );
        if (!canExpand) return text;
        return Material(
          color: scheme.surfaceContainerLow.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(padding: const EdgeInsets.all(8), child: text),
          ),
        );
      },
    );
  }

  TextSpan _collapsedSpan({
    required TextStyle textStyle,
    required TextStyle suffixStyle,
    required TextDirection direction,
    required double maxWidth,
  }) {
    const suffix = '... 点击展开';
    final codePoints = widget.text.runes.toList();

    bool fits(int count) {
      final prefix = String.fromCharCodes(codePoints.take(count));
      final painter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: prefix, style: textStyle),
            TextSpan(text: suffix, style: suffixStyle),
          ],
        ),
        maxLines: 3,
        textDirection: direction,
      )..layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines;
    }

    var low = 0;
    var high = codePoints.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (fits(middle)) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return TextSpan(
      children: [
        TextSpan(
          text: String.fromCharCodes(codePoints.take(low)).trimRight(),
          style: textStyle,
        ),
        TextSpan(text: suffix, style: suffixStyle),
      ],
    );
  }
}

class SourceDownloadTile extends StatelessWidget {
  const SourceDownloadTile({
    required this.file,
    required this.sourceId,
    required this.state,
    this.app,
    this.showDivider = true,
    super.key,
  });

  final SourceDownload file;
  final String sourceId;
  final AppState state;
  final AppListing? app;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final task = state.downloadFor(file.url);
        final taskDetail = task == null ? null : downloadTaskDetail(task);
        final detail = task == null ? file.size.trim() : (taskDetail ?? '');
        final (icon, color) = switch (task?.status) {
          DownloadStatus.completed => (
            Icons.check_circle_outline,
            scheme.primary,
          ),
          DownloadStatus.paused => (
            Icons.pause_circle_outline,
            scheme.tertiary,
          ),
          DownloadStatus.canceled => (Icons.cancel_outlined, scheme.outline),
          DownloadStatus.failed => (Icons.error_outline, scheme.error),
          _ => (Icons.file_download_outlined, scheme.primary),
        };

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Icon(icon, color: color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: task == null
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _downloadTitle(context, file.label),
                                    if (detail.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      _downloadDetail(context, detail, scheme),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              _downloadButton(context),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _downloadTitle(context, file.label),
                              if (detail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _downloadDetail(context, detail, scheme),
                              ],
                              const SizedBox(height: 8),
                              DownloadTaskControls(task: task, state: state),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                indent: 52,
                color: scheme.outlineVariant.withValues(alpha: .65),
              ),
          ],
        );
      },
    );
  }

  Widget _downloadTitle(BuildContext context, String label) {
    return Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _downloadDetail(
    BuildContext context,
    String detail,
    ColorScheme scheme,
  ) {
    return Text(
      detail,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    );
  }

  Widget _downloadButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: () {
          state.startDownload(file, sourceId, app: app);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已开始下载，可在下载页查看进度')));
        },
        icon: const Icon(Icons.download),
        label: const Text('下载'),
      ),
    );
  }
}
