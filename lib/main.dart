import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'core/app_state.dart';
import 'core/debug_log.dart';
import 'core/models.dart';

void main() => runApp(const ApkMeshApp());

class ApkMeshApp extends StatefulWidget {
  const ApkMeshApp({super.key});

  @override
  State<ApkMeshApp> createState() => _ApkMeshAppState();
}

class _ApkMeshAppState extends State<ApkMeshApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.initialize();
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff315f8c),
      brightness: Brightness.light,
    );
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp(
        title: 'APK Mesh',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: Shell(state: state),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({required this.state, super.key});
  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(state: widget.state, controller: searchController),
      DownloadsPage(state: widget.state),
      SourcesPage(state: widget.state),
      SettingsPage(state: widget.state),
    ];
    final destinations = const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '主页',
      ),
      NavigationDestination(
        icon: Icon(Icons.download_outlined),
        selectedIcon: Icon(Icons.download),
        label: '下载',
      ),
      NavigationDestination(
        icon: Icon(Icons.hub_outlined),
        selectedIcon: Icon(Icons.hub),
        label: '源管理',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Scaffold(
          appBar: AppBar(
            title: const Text('APK Mesh'),
            actions: [
              IconButton(
                tooltip: '调试',
                onPressed: () => _showDebugSheet(context),
                icon: const Icon(Icons.bug_report_outlined),
              ),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (value) =>
                      setState(() => index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('主页'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download),
                      label: Text('下载'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.hub_outlined),
                      selectedIcon: Icon(Icons.hub),
                      label: Text('源管理'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(index: index, children: pages),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (value) =>
                      setState(() => index = value),
                  destinations: destinations,
                ),
        );
      },
    );
  }

  void _showDebugSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DebugSheet(state: widget.state),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({required this.state, required this.controller, super.key});
  final AppState state;
  final TextEditingController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<AppListing> results = const [];
  bool loading = false;
  String? error;
  String? submittedQuery;

  Future<void> search() async {
    final query = widget.controller.text.trim();
    setState(() {
      loading = true;
      error = null;
      submittedQuery = query;
    });
    try {
      final found = await widget.state.search(query);
      if (mounted) {
        setState(() {
          results = found;
          loading = false;
          if (found.isEmpty && widget.state.sourceErrors.isNotEmpty) {
            error = widget.state.sourceErrors.entries
                .map((entry) => '${entry.key}：${entry.value}')
                .join('\n');
          }
        });
      }
    } catch (searchError) {
      if (mounted) {
        setState(() {
          loading = false;
          error = searchError.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Text('发现应用', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('从已启用的源聚合搜索结果', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        TextField(
          controller: widget.controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => search(),
          decoration: InputDecoration(
            hintText: '搜索应用名称或包名',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: '开始搜索',
              onPressed: loading ? null : search,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (!widget.state.hasEnabledSource)
          const EmptyMessage(
            icon: Icons.hub_outlined,
            title: '没有启用的源',
            detail: '请先在源管理中启用一个源。',
          ),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
        if (!loading && error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              title: const Text('源执行失败'),
              subtitle: Text(error!),
            ),
          ),
        if (!loading &&
            error == null &&
            results.isEmpty &&
            widget.state.hasEnabledSource)
          EmptyMessage(
            icon: Icons.manage_search,
            title: submittedQuery == null ? '输入关键词开始搜索' : '未找到结果',
            detail: submittedQuery == null
                ? '结果会合并所有已启用源的数据。'
                : submittedQuery!.isEmpty
                ? '请输入应用名称或包名。'
                : '已在所有启用的源中搜索“$submittedQuery”。',
          ),
        ...results.asMap().entries.map(
          (entry) => AppResultTile(
            app: entry.value,
            state: widget.state,
            showDivider: entry.key < results.length - 1,
          ),
        ),
      ],
    );
  }
}

class AppResultTile extends StatelessWidget {
  const AppResultTile({
    required this.app,
    required this.state,
    this.showDivider = true,
    super.key,
  });
  final AppListing app;
  final AppState state;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    void openDetails() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DetailsSheet(app: app, state: state),
      );
    }

    final theme = Theme.of(context);
    final summary = app.summary.trim();
    final contextLine = _appContextLine(app, summary);
    final badges = _appBadges(app);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: openDetails,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(url: app.iconUrl, size: 72, borderRadius: 16),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (contextLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            contextLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (summary.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (badges.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: badges),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 88,
            color: theme.colorScheme.outlineVariant.withValues(alpha: .65),
          ),
      ],
    );
  }
}

String _appContextLine(AppListing app, String summary) {
  final values = <String>[];
  final summaryLower = summary.toLowerCase();
  bool isInSummary(String value) {
    final normalized = value.toLowerCase();
    final sourceBase = normalized.split(RegExp(r'[（(]')).first.trim();
    return summaryLower.contains(normalized) ||
        (sourceBase.isNotEmpty && summaryLower.contains(sourceBase));
  }

  for (final value in [app.sourceName, app.category]) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty &&
        !isInSummary(trimmed) &&
        !values.contains(trimmed)) {
      values.add(trimmed);
    }
  }
  return values.join(' · ');
}

List<Widget> _appBadges(AppListing app) {
  final badges = <Widget>[];
  final values = <({IconData icon, String text})>[];

  void add(IconData icon, String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !values.any((item) => item.text == trimmed)) {
      values.add((icon: icon, text: trimmed));
    }
  }

  add(Icons.new_releases_outlined, app.version);
  add(Icons.storage_outlined, app.size);
  add(Icons.update_outlined, app.updatedAt);
  add(Icons.code_outlined, app.packageName);

  for (final value in values) {
    badges.add(_AppInfoBadge(icon: value.icon, text: value.text));
  }
  return badges;
}

class _AppInfoBadge extends StatelessWidget {
  const _AppInfoBadge({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tasks = state.downloads;
    final active = tasks
        .where((task) => task.status == DownloadStatus.downloading)
        .length;
    final completed = tasks
        .where((task) => task.status == DownloadStatus.completed)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Text('下载管理', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('$active 个进行中 · $completed 个已完成'),
        const SizedBox(height: 20),
        if (tasks.isEmpty)
          const EmptyMessage(
            icon: Icons.download_done_outlined,
            title: '暂无下载任务',
            detail: '从应用详情中选择文件后，任务会显示在这里。',
          )
        else
          ...tasks.map((task) => _DownloadTaskTile(task: task, state: state)),
      ],
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({required this.task, required this.state});
  final DownloadTask task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (task.status) {
      DownloadStatus.downloading => (Icons.downloading, scheme.primary),
      DownloadStatus.completed => (Icons.check_circle_outline, scheme.primary),
      DownloadStatus.failed => (Icons.error_outline, scheme.error),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: Icon(icon, color: color),
            title: Text(task.file.label),
            subtitle: Text(_downloadTaskDetail(task)),
            trailing: switch (task.status) {
              DownloadStatus.downloading => const SizedBox(
                width: 48,
                height: 48,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              DownloadStatus.completed => IconButton(
                tooltip: '安装',
                icon: const Icon(Icons.install_mobile_outlined),
                onPressed: () => _installDownloadTask(context, state, task),
              ),
              DownloadStatus.failed => IconButton(
                tooltip: '重试下载',
                icon: const Icon(Icons.refresh),
                onPressed: () => state.retryDownload(task),
              ),
            },
          ),
          if (task.status == DownloadStatus.downloading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: LinearProgressIndicator(value: task.progress),
            ),
        ],
      ),
    );
  }
}

String _downloadTaskDetail(DownloadTask task) {
  switch (task.status) {
    case DownloadStatus.downloading:
      final total = task.total;
      if (total != null && total > 0) {
        final percent = ((task.progress ?? 0) * 100).toStringAsFixed(0);
        return '${_formatByteCount(task.received)} / ${_formatByteCount(total)} · $percent%';
      }
      return task.received > 0
          ? '已下载 ${_formatByteCount(task.received)}'
          : '正在连接';
    case DownloadStatus.completed:
      return '下载完成\n${task.filePath ?? task.file.size}';
    case DownloadStatus.failed:
      return '下载失败\n${task.error ?? '未知错误'}';
  }
}

String _formatByteCount(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

Future<void> _installDownloadTask(
  BuildContext context,
  AppState state,
  DownloadTask task,
) async {
  try {
    final installed = await state.installTask(task);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(installed ? '已交给系统安装器' : '请完成系统安装权限设置后重试')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('安装失败：$error')));
  }
}

class SourcesPage extends StatelessWidget {
  const SourcesPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('源管理', style: Theme.of(context).textTheme.headlineMedium),
            FilledButton.icon(
              onPressed: () => _showAddSource(context),
              icon: const Icon(Icons.add),
              label: const Text('导入源'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('源脚本在隔离的 QuickJS 环境中运行，仅通过受控能力访问网络和文件。'),
        const SizedBox(height: 20),
        ...state.sources.map(
          (source) => SourceTile(source: source, state: state),
        ),
      ],
    );
  }

  void _showAddSource(BuildContext context) {
    final name = TextEditingController();
    final url = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '源名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: '脚本 URL 或本地路径'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                state.addSource(
                  ApkSource(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.text.trim(),
                    homepage: url.text.trim(),
                    version: '0.1.0',
                    description: '用户导入的 QuickJS 源',
                    status: SourceStatus.enabled,
                    builtIn: false,
                  ),
                );
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }
}

class SourceTile extends StatelessWidget {
  const SourceTile({required this.source, required this.state, super.key});
  final ApkSource source;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final enabled = source.status == SourceStatus.enabled;
    final debugProjectCount = state.debugProjects
        .where((project) => project.sourceId == source.id)
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          child: Icon(source.builtIn ? Icons.inventory_2_outlined : Icons.code),
        ),
        title: Text(source.name),
        subtitle: Text(
          '${source.description}\n${source.homepage} · v${source.version} · 调试项目 $debugProjectCount 个',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: enabled,
              onChanged: (value) => state.toggleSource(source.id, value),
            ),
            if (!source.builtIn)
              IconButton(
                tooltip: '删除源',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => state.removeSource(source.id),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
    children: [
      Text('设置', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 20),
      const ListTile(
        leading: Icon(Icons.download_outlined),
        title: Text('下载目录'),
        subtitle: Text('系统默认下载目录'),
      ),
      const Divider(),
      ListTile(
        leading: Icon(Icons.security_outlined),
        title: Text('安装权限'),
        subtitle: const Text('安装 APK 前需要允许本应用安装未知来源的应用'),
        trailing: state.host.supportsInstall
            ? IconButton(
                tooltip: '打开系统安装权限',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => state.host.requestInstallPermission(),
              )
            : null,
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.policy_outlined),
        title: Text('法律与安全'),
        subtitle: Text('请只导入你有权访问的站点源，并在安装前核验签名。'),
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('关于 APK Mesh'),
        subtitle: Text('开源源聚合客户端 · 0.1.0'),
      ),
    ],
  );
}

enum _DebugSection { overview, requests, webviews, projects, logs }

class DebugSheet extends StatefulWidget {
  const DebugSheet({required this.state, super.key});
  final AppState state;

  @override
  State<DebugSheet> createState() => _DebugSheetState();
}

class _DebugSheetState extends State<DebugSheet> {
  _DebugSection section = _DebugSection.overview;
  final Map<String, TextEditingController> _projectInputs = {};
  final Map<String, DebugProjectResult> _projectResults = {};
  final Set<String> _runningProjects = {};

  AppState get state => widget.state;

  @override
  void dispose() {
    for (final controller in _projectInputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _inputFor(SourceDebugProject project) =>
      _projectInputs.putIfAbsent(
        project.key,
        () => TextEditingController(text: project.defaultInput),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      minChildSize: .5,
      maxChildSize: .98,
      builder: (_, controller) => AnimatedBuilder(
        animation: state.debug,
        builder: (context, _) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '调试信息',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            '${state.debug.requests.length} 个请求 · ${state.debug.entries.length} 条日志',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '清空调试记录',
                      onPressed:
                          state.debug.entries.isEmpty &&
                              state.debug.requests.isEmpty
                          ? null
                          : state.debug.clear,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SegmentedButton<_DebugSection>(
                  segments: const [
                    ButtonSegment(
                      value: _DebugSection.overview,
                      label: Text('概览'),
                      icon: Icon(Icons.dashboard_outlined),
                    ),
                    ButtonSegment(
                      value: _DebugSection.requests,
                      label: Text('请求'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                    ButtonSegment(
                      value: _DebugSection.webviews,
                      label: Text('WebView'),
                      icon: Icon(Icons.web_outlined),
                    ),
                    ButtonSegment(
                      value: _DebugSection.projects,
                      label: Text('项目'),
                      icon: Icon(Icons.play_circle_outline),
                    ),
                    ButtonSegment(
                      value: _DebugSection.logs,
                      label: Text('日志'),
                      icon: Icon(Icons.notes_outlined),
                    ),
                  ],
                  selected: {section},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => section = value.first),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: _buildSection(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSection(BuildContext context) => switch (section) {
    _DebugSection.overview => _buildOverview(context),
    _DebugSection.requests => _buildRequests(context),
    _DebugSection.webviews => _buildWebviews(context),
    _DebugSection.projects => _buildProjects(context),
    _DebugSection.logs => _buildLogs(context),
  };

  List<Widget> _buildOverview(BuildContext context) {
    final requests = state.debug.requests.reversed.take(4).toList();
    final tabs = state.host.browserTabs;
    final logs = state.debug.entries.reversed.take(5).toList();
    return [
      Text('运行时', style: Theme.of(context).textTheme.titleMedium),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          state.sourceRuntimeReady
              ? Icons.check_circle_outline
              : Icons.warning_amber_outlined,
        ),
        title: Text(state.sourceRuntimeReady ? 'QuickJS 源已加载' : '使用演示源'),
        subtitle: Text(
          state.runtimeError ??
              '已启用源：${state.sources.where((source) => source.status == SourceStatus.enabled).map((source) => source.name).join('、')}',
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.web_outlined),
        title: Text('WebView：${state.host.supportsBrowser ? '可用' : '不可用'}'),
        subtitle: Text(
          '活动标签 ${tabs.where((tab) => tab.active).length} 个 · 安装能力：${state.host.supportsInstall ? '可用' : '不可用'}',
        ),
      ),
      const SizedBox(height: 8),
      Text('WebView 状态', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      if (tabs.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.web_asset_off_outlined),
          title: Text('暂无 WebView 标签'),
          subtitle: Text('调试项目运行后可点击标签查看页面。'),
        )
      else
        ...tabs
            .take(3)
            .map(
              (tab) => _DebugTabTile(
                tab: tab,
                onTap: () => _showWebView(context, tab),
              ),
            ),
      const SizedBox(height: 8),
      Row(
        children: [
          Text('最近请求', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${state.debug.requests.length} 个'),
        ],
      ),
      if (requests.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.swap_horiz_outlined),
          title: Text('暂无请求'),
        )
      else
        ...requests.map(
          (request) => _DebugRequestTile(
            request: request,
            onTap: () => _showRequest(context, request),
          ),
        ),
      const SizedBox(height: 8),
      Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
      if (logs.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.article_outlined),
          title: Text('暂无日志'),
        )
      else
        ...logs.map((entry) => _DebugLogTile(entry: entry)),
    ];
  }

  List<Widget> _buildRequests(BuildContext context) {
    final requests = state.debug.requests.reversed.toList();
    return [
      Row(
        children: [
          Text('请求记录', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${requests.length} 个 · 点击查看内容'),
        ],
      ),
      const SizedBox(height: 8),
      if (requests.isEmpty)
        const EmptyMessage(
          icon: Icons.swap_horiz_outlined,
          title: '暂无请求记录',
          detail: '运行搜索项目或应用搜索后，请求会出现在这里。',
        )
      else
        ...requests.map(
          (request) => _DebugRequestTile(
            request: request,
            onTap: () => _showRequest(context, request),
          ),
        ),
    ];
  }

  List<Widget> _buildWebviews(BuildContext context) {
    final tabs = state.host.browserTabs;
    return [
      Row(
        children: [
          Text('WebView 状态', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${tabs.length} 个'),
        ],
      ),
      const SizedBox(height: 8),
      if (tabs.isEmpty)
        const EmptyMessage(
          icon: Icons.web_asset_off_outlined,
          title: '暂无 WebView 标签',
          detail: '运行“获取应用详情”项目后，可以点开对应标签进行可视化查看。',
        )
      else
        ...tabs.map(
          (tab) =>
              _DebugTabTile(tab: tab, onTap: () => _showWebView(context, tab)),
        ),
    ];
  }

  List<Widget> _buildProjects(BuildContext context) {
    final projects = state.debugProjects;
    return [
      Row(
        children: [
          Text('调试项目', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${projects.length} 个'),
        ],
      ),
      const SizedBox(height: 8),
      if (projects.isEmpty)
        const EmptyMessage(
          icon: Icons.play_disabled_outlined,
          title: '源未声明调试项目',
          detail: '源可以在 manifest.debugProjects 中声明可触发的调试流程。',
        )
      else
        ...projects.map((project) => _DebugProjectTile(project: project)),
    ];
  }

  List<Widget> _buildLogs(BuildContext context) {
    final logs = state.debug.entries.reversed.toList();
    return [
      Row(
        children: [
          Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${logs.length} 条'),
        ],
      ),
      const SizedBox(height: 8),
      if (logs.isEmpty)
        const EmptyMessage(
          icon: Icons.article_outlined,
          title: '暂无日志',
          detail: '执行搜索、详情或调试项目后，运行事件会显示在这里。',
        )
      else
        ...logs.map((entry) => _DebugLogTile(entry: entry)),
    ];
  }

  Future<void> _runProject(SourceDebugProject project) async {
    final controller = _inputFor(project);
    final input = controller.text.trim().isEmpty
        ? project.defaultInput.trim()
        : controller.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入${project.inputLabel}')));
      return;
    }
    setState(() => _runningProjects.add(project.key));
    try {
      final result = await state.runDebugProject(project, input);
      if (mounted) {
        setState(() {
          _projectResults[project.key] = result;
          _runningProjects.remove(project.key);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _runningProjects.remove(project.key));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('调试项目失败：$error')));
      }
    }
  }

  void _showRequest(BuildContext context, DebugRequestEntry request) {
    showDialog<void>(
      context: context,
      builder: (_) => _DebugRequestDialog(request: request),
    );
  }

  void _showWebView(BuildContext context, BrowserTabDebugInfo tab) {
    showDialog<void>(
      context: context,
      builder: (_) => _DebugWebViewDialog(state: state, tab: tab),
    );
  }
}

class _DebugProjectTile extends StatelessWidget {
  const _DebugProjectTile({required this.project});
  final SourceDebugProject project;

  @override
  Widget build(BuildContext context) {
    final sheet = context.findAncestorStateOfType<_DebugSheetState>()!;
    final input = sheet._inputFor(project);
    final running = sheet._runningProjects.contains(project.key);
    final result = sheet._projectResults[project.key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline),
            title: Text(project.name),
            subtitle: Text('${project.sourceName}\n${project.description}'),
            isThreeLine: true,
          ),
          TextField(
            controller: input,
            enabled: !running,
            decoration: InputDecoration(
              labelText: project.inputLabel,
              hintText: project.placeholder,
              suffixIcon: IconButton(
                tooltip: '运行调试项目',
                onPressed: running ? null : () => sheet._runProject(project),
                icon: running
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
              ),
            ),
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(result.title),
                subtitle: SelectableText(
                  '${result.summary}\n${_prettyDebugValue(result.data)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DebugRequestTile extends StatelessWidget {
  const _DebugRequestTile({required this.request, required this.onTap});
  final DebugRequestEntry request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (request.state) {
      DebugRequestState.pending => scheme.tertiary,
      DebugRequestState.completed => scheme.primary,
      DebugRequestState.failed => scheme.error,
    };
    final status =
        request.statusCode?.toString() ??
        switch (request.state) {
          DebugRequestState.pending => '进行中',
          DebugRequestState.completed => '完成',
          DebugRequestState.failed => '失败',
        };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        request.state == DebugRequestState.failed
            ? Icons.error_outline
            : Icons.swap_horiz_outlined,
        color: color,
      ),
      title: Text('${request.method} $status'),
      subtitle: Text(
        '${request.url}\n${request.duration?.inMilliseconds ?? 0} ms · ${request.responseBody?.length ?? 0} 字符',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _DebugRequestDialog extends StatelessWidget {
  const _DebugRequestDialog({required this.request});
  final DebugRequestEntry request;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      child: SizedBox(
        width: size.width > 760 ? 700 : size.width * .92,
        height: size.height * .82,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${request.method} ${request.statusCode ?? '请求'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(request.url),
                ),
              ),
              const SizedBox(height: 8),
              const TabBar(
                tabs: [
                  Tab(text: '响应内容'),
                  Tab(text: '请求详情'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _DebugBodyView(
                      body: request.responseBody ?? request.error ?? '暂无响应内容',
                    ),
                    _DebugMetadataView(request: request),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugBodyView extends StatelessWidget {
  const _DebugBodyView({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: SelectableText(
      _formatDebugBody(body),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );
}

class _DebugMetadataView extends StatelessWidget {
  const _DebugMetadataView({required this.request});
  final DebugRequestEntry request;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('请求头', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SelectableText(_formatHeaders(request.requestHeaders)),
      const SizedBox(height: 16),
      Text('响应头', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SelectableText(_formatHeaders(request.responseHeaders)),
      const SizedBox(height: 16),
      Text('状态', style: Theme.of(context).textTheme.titleSmall),
      SelectableText(
        '${request.state.name} · ${request.duration?.inMilliseconds ?? 0} ms${request.error == null ? '' : '\n${request.error}'}',
      ),
    ],
  );
}

class _DebugWebViewDialog extends StatefulWidget {
  const _DebugWebViewDialog({required this.state, required this.tab});
  final AppState state;
  final BrowserTabDebugInfo tab;

  @override
  State<_DebugWebViewDialog> createState() => _DebugWebViewDialogState();
}

class _DebugWebViewDialogState extends State<_DebugWebViewDialog> {
  String status = '正在加载';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final canView =
        widget.state.host.supportsBrowser &&
        (widget.tab.url.startsWith('http://') ||
            widget.tab.url.startsWith('https://'));
    return Dialog(
      child: SizedBox(
        width: size.width > 900 ? 840 : size.width * .94,
        height: size.height * .84,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.web_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WebView 可视化查看',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${widget.tab.active ? '活动' : '历史'} · $status',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(widget.tab.url, maxLines: 2),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: canView
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(widget.tab.url),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        incognito: true,
                      ),
                      onLoadStart: (_, _) => setState(() => status = '加载中'),
                      onLoadStop: (_, _) => setState(() => status = '已加载'),
                      onReceivedError: (_, _, _) =>
                          setState(() => status = '加载失败'),
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('当前平台不支持可视化 WebView，仅保留标签和操作记录。'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugTabTile extends StatelessWidget {
  const _DebugTabTile({required this.tab, required this.onTap});
  final BrowserTabDebugInfo tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = tab.active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        tab.active ? Icons.web : Icons.web_asset_off_outlined,
        color: color,
      ),
      title: Text('${tab.active ? '活动' : '已关闭'} · ${tab.state}'),
      subtitle: Text(
        '${tab.url}\n${tab.id} · ${_formatDebugTime(tab.startedAt)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: const Icon(Icons.open_in_new),
    );
  }
}

class _DebugLogTile extends StatelessWidget {
  const _DebugLogTile({required this.entry});
  final DebugLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      DebugLogLevel.error => Theme.of(context).colorScheme.error,
      DebugLogLevel.warning => Theme.of(context).colorScheme.tertiary,
      DebugLogLevel.info => Theme.of(context).colorScheme.primary,
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.level == DebugLogLevel.error
            ? Icons.error_outline
            : Icons.notes_outlined,
        color: color,
      ),
      title: Text(entry.message),
      subtitle: Text('${entry.category} · ${_formatDebugTime(entry.time)}'),
    );
  }
}

String _formatHeaders(Map<String, String> headers) {
  if (headers.isEmpty) return '无';
  return headers.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join('\\n');
}

String _formatDebugBody(String body) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
  } catch (_) {
    return body;
  }
}

String _prettyDebugValue(dynamic value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String _formatDebugTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class DetailsSheet extends StatefulWidget {
  const DetailsSheet({required this.app, required this.state, super.key});
  final AppListing app;
  final AppState state;

  @override
  State<DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<DetailsSheet> {
  late final Future<AppDetails> details = widget.app is AppDetails
      ? Future<AppDetails>.value(widget.app as AppDetails)
      : widget.state.details(widget.app);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .45,
        maxChildSize: .94,
        builder: (_, controller) => FutureBuilder<AppDetails>(
          future: details,
          builder: (context, snapshot) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  AppIcon(url: widget.app.iconUrl),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.app.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(widget.app.packageName),
                        Text('${widget.app.version} · ${widget.app.size}'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (snapshot.hasError) Text('源详情加载失败：${snapshot.error}'),
              if (snapshot.hasData) ...[
                Text(snapshot.data!.description),
                const SizedBox(height: 24),
                Text('下载文件', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...snapshot.data!.downloads.map(
                  (file) => _SourceDownloadTile(
                    file: file,
                    sourceId: widget.app.sourceId,
                    state: widget.state,
                  ),
                ),
                const SizedBox(height: 24),
                Text('评论', style: Theme.of(context).textTheme.titleMedium),
                ...snapshot.data!.comments.map(
                  (comment) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.comment_outlined),
                    title: Text(comment),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceDownloadTile extends StatelessWidget {
  const _SourceDownloadTile({
    required this.file,
    required this.sourceId,
    required this.state,
  });

  final SourceDownload file;
  final String sourceId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final task = state.downloadFor(file.url);
        final detail = task == null
            ? file.size
            : '${file.size}\n${_downloadTaskDetail(task)}';
        return Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                task?.status == DownloadStatus.completed
                    ? Icons.check_circle_outline
                    : Icons.file_download_outlined,
              ),
              title: Text(file.label),
              subtitle: Text(detail),
              trailing: SizedBox(
                width: 112,
                child: _downloadButton(context, task),
              ),
            ),
            if (task?.status == DownloadStatus.downloading)
              Padding(
                padding: const EdgeInsets.only(left: 56, bottom: 8),
                child: LinearProgressIndicator(value: task?.progress),
              ),
          ],
        );
      },
    );
  }

  Widget _downloadButton(BuildContext context, DownloadTask? task) {
    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    if (task?.status == DownloadStatus.downloading) {
      return FilledButton.icon(
        style: style,
        onPressed: null,
        icon: const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('下载中'),
      );
    }
    if (task?.status == DownloadStatus.completed) {
      return FilledButton.icon(
        style: style,
        onPressed: () => _installDownloadTask(context, state, task!),
        icon: const Icon(Icons.install_mobile_outlined),
        label: const Text('安装'),
      );
    }
    final retry = task?.status == DownloadStatus.failed;
    return FilledButton.icon(
      style: style,
      onPressed: () {
        if (retry) {
          state.retryDownload(task!);
        } else {
          state.startDownload(file, sourceId);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(retry ? '正在重新下载' : '已开始下载，可在下载页查看进度')),
        );
      },
      icon: Icon(retry ? Icons.refresh : Icons.download),
      label: Text(retry ? '重试' : '下载'),
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({
    required this.url,
    this.size = 56,
    this.borderRadius = 12,
    super.key,
  });
  final String url;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: url.isEmpty
        ? _placeholder(context)
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _placeholder(context),
          ),
  );

  Widget _placeholder(BuildContext context) => Container(
    width: size,
    height: size,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Icon(Icons.android),
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({
    required this.icon,
    required this.title,
    required this.detail,
    super.key,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  );
}
