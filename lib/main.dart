import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

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
  bool searchOpen = false;
  final searchController = TextEditingController();
  final homeKey = GlobalKey<_HomePageState>();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(key: homeKey, state: widget.state, controller: searchController),
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
            title: searchOpen
                ? SizedBox(
                    width: (constraints.maxWidth - 160).clamp(140.0, 520.0),
                    height: 46,
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submitSearch(),
                      decoration: InputDecoration(
                        hintText: '搜索应用名称或包名',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: IconButton(
                          tooltip: '清空搜索',
                          onPressed: searchController.clear,
                          icon: const Icon(Icons.clear, size: 20),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: const OutlineInputBorder(),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  )
                : const Text('APK Mesh'),
            actions: [
              if (!searchOpen)
                IconButton(
                  tooltip: '搜索',
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                )
              else
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: () => setState(() => searchOpen = false),
                  icon: const Icon(Icons.close),
                ),
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

  void _openSearch() {
    setState(() {
      index = 0;
      searchOpen = true;
    });
  }

  Future<void> _submitSearch() async {
    setState(() {
      index = 0;
      searchOpen = false;
    });
    await homeKey.currentState?.search();
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
  SourceHome home = const SourceHome();
  bool loading = false;
  bool homeLoading = true;
  bool homeLoaded = false;
  String? error;
  String? homeError;
  String? submittedQuery;
  String _selectedTab = 'home';
  String? _loadedHomeSourceId;
  final Map<String, Future<SourceCategory>> _categoryLoads = {};

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _loadHome();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted || submittedQuery != null) return;
    if (_loadedHomeSourceId == widget.state.homeSourceId) return;
    _categoryLoads.clear();
    setState(() {
      homeLoaded = false;
      homeLoading = true;
      _selectedTab = 'home';
    });
    _loadHome();
  }

  Future<void> _loadHome() async {
    if (homeLoaded) return;
    setState(() {
      homeLoading = true;
      homeError = null;
    });
    try {
      final content = await widget.state.home();
      if (!mounted) return;
      setState(() {
        home = content;
        _loadedHomeSourceId = widget.state.homeSourceId;
        homeLoading = false;
        homeLoaded = true;
        if (!home.categories.any(
          (category) =>
              'category:${category.sourceId}:${category.id}' == _selectedTab,
        )) {
          _selectedTab = 'home';
        }
        if (content.recommended.isEmpty &&
            content.categories.isEmpty &&
            widget.state.sourceErrors.isNotEmpty) {
          homeError = widget.state.sourceErrors.entries
              .map((entry) => '${entry.key}：${entry.value}')
              .join('\n');
        }
      });
    } catch (loadError) {
      if (!mounted) return;
      setState(() {
        homeLoading = false;
        homeLoaded = true;
        homeError = loadError.toString();
      });
    }
  }

  Future<void> search() async {
    final query = widget.controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        submittedQuery = null;
        results = const [];
        error = null;
        _selectedTab = 'home';
      });
      await _loadHome();
      return;
    }
    setState(() {
      loading = true;
      error = null;
      results = const [];
      submittedQuery = query;
      _selectedTab = 'all';
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

  List<_ContentTab> get _tabs {
    if (submittedQuery == null) {
      return [
        const _ContentTab(id: 'home', label: '主页'),
        ...home.categories.map(
          (category) => _ContentTab(
            id: 'category:${category.sourceId}:${category.id}',
            label: category.name,
            category: category,
          ),
        ),
      ];
    }
    return [
      const _ContentTab(id: 'all', label: '全部源'),
      ...widget.state.sources
          .where((source) => source.status == SourceStatus.enabled)
          .map(
            (source) => _ContentTab(
              id: 'source:${source.id}',
              label: source.name,
              sourceId: source.id,
            ),
          ),
    ];
  }

  _ContentTab _activeTab(List<_ContentTab> tabs) {
    for (final tab in tabs) {
      if (tab.id == _selectedTab) return tab;
    }
    return tabs.first;
  }

  Widget _buildTabBar(
    BuildContext context,
    List<_ContentTab> tabs,
    _ContentTab activeTab,
  ) {
    final tabKey = tabs.map((tab) => tab.id).join('|');
    final activeIndex = tabs.indexWhere((tab) => tab.id == activeTab.id);
    return DefaultTabController(
      key: ValueKey(tabKey),
      length: tabs.length,
      initialIndex: activeIndex < 0 ? 0 : activeIndex,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        onTap: (index) {
          if (index < tabs.length) {
            setState(() => _selectedTab = tabs[index].id);
          }
        },
        tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
      ),
    );
  }

  Future<SourceCategory> _categoryFuture(SourceCategory category) {
    final key = '${category.sourceId}:${category.id}';
    return _categoryLoads.putIfAbsent(
      key,
      () => category.apps.isNotEmpty
          ? Future<SourceCategory>.value(category)
          : widget.state.category(category),
    );
  }

  List<Widget> _buildHomeContent(BuildContext context, _ContentTab activeTab) {
    if (homeLoading) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (homeError != null &&
        home.recommended.isEmpty &&
        home.categories.isEmpty) {
      return [
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('首页内容加载失败'),
            subtitle: Text(homeError!),
          ),
        ),
      ];
    }
    if (activeTab.category != null) {
      return [
        _CategoryTabContent(
          category: activeTab.category!,
          future: _categoryFuture(activeTab.category!),
          state: widget.state,
        ),
      ];
    }
    final recommended = home.recommended.take(12).toList();
    if (recommended.isEmpty) {
      return const [
        EmptyMessage(
          icon: Icons.home_work_outlined,
          title: '暂无推荐应用',
          detail: '当前主页源没有返回推荐应用。',
        ),
      ];
    }
    return [
      Text('推荐应用', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      ...recommended.asMap().entries.map(
        (entry) => AppResultTile(
          app: entry.value,
          state: widget.state,
          showDivider: entry.key < recommended.length - 1,
        ),
      ),
    ];
  }

  List<Widget> _buildSearchContent(
    BuildContext context,
    _ContentTab activeTab,
  ) {
    final visibleResults = activeTab.sourceId == null
        ? results
        : results.where((app) => app.sourceId == activeTab.sourceId).toList();
    return [
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
      if (!loading && error == null && visibleResults.isEmpty)
        EmptyMessage(
          icon: Icons.manage_search,
          title: '未找到结果',
          detail: activeTab.sourceId == null
              ? '已在所有启用的源中搜索“$submittedQuery”。'
              : '当前源没有返回“$submittedQuery”的结果。',
        ),
      ...visibleResults.asMap().entries.map(
        (entry) => AppResultTile(
          app: entry.value,
          state: widget.state,
          showDivider: entry.key < visibleResults.length - 1,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final showingHome = submittedQuery == null;
    final tabs = _tabs;
    final activeTab = _activeTab(tabs);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Text('发现应用', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          showingHome ? '主页与分类' : '按源筛选搜索结果',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        if (!widget.state.hasEnabledSource)
          const EmptyMessage(
            icon: Icons.hub_outlined,
            title: '没有启用的源',
            detail: '请先在源管理中启用一个源。',
          )
        else ...[
          _buildTabBar(context, tabs, activeTab),
          const SizedBox(height: 16),
          ...(showingHome
              ? _buildHomeContent(context, activeTab)
              : _buildSearchContent(context, activeTab)),
        ],
      ],
    );
  }
}

class _ContentTab {
  const _ContentTab({
    required this.id,
    required this.label,
    this.category,
    this.sourceId,
  });

  final String id;
  final String label;
  final SourceCategory? category;
  final String? sourceId;
}

class _CategoryTabContent extends StatelessWidget {
  const _CategoryTabContent({
    required this.category,
    required this.future,
    required this.state,
  });

  final SourceCategory category;
  final Future<SourceCategory> future;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SourceCategory>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Text('分类加载失败：${snapshot.error}');
        }
        final apps = snapshot.data?.apps ?? const <AppListing>[];
        if (apps.isEmpty) {
          return const EmptyMessage(
            icon: Icons.apps_outage_outlined,
            title: '分类暂无应用',
            detail: '该源没有返回可用应用。',
          );
        }
        return Column(
          children: apps
              .asMap()
              .entries
              .map(
                (entry) => AppResultTile(
                  app: entry.value,
                  state: state,
                  showDivider: entry.key < apps.length - 1,
                ),
              )
              .toList(),
        );
      },
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
        .where(
          (task) =>
              task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.paused,
        )
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
      DownloadStatus.paused => (Icons.pause_circle_outline, scheme.tertiary),
      DownloadStatus.completed => (Icons.check_circle_outline, scheme.primary),
      DownloadStatus.failed => (Icons.error_outline, scheme.error),
      DownloadStatus.canceled => (Icons.cancel_outlined, scheme.outline),
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
              DownloadStatus.downloading => SizedBox(
                width: 104,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '暂停下载',
                      icon: const Icon(Icons.pause),
                      onPressed: () => state.pauseDownload(task),
                    ),
                    IconButton(
                      tooltip: '取消下载',
                      icon: const Icon(Icons.close),
                      onPressed: () => state.cancelDownload(task),
                    ),
                  ],
                ),
              ),
              DownloadStatus.paused => SizedBox(
                width: 104,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '继续下载',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => state.resumeDownload(task),
                    ),
                    IconButton(
                      tooltip: '取消下载',
                      icon: const Icon(Icons.close),
                      onPressed: () => state.cancelDownload(task),
                    ),
                  ],
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
              DownloadStatus.canceled => IconButton(
                tooltip: '重新下载',
                icon: const Icon(Icons.refresh),
                onPressed: () => state.retryDownload(task),
              ),
            },
          ),
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.paused)
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
    case DownloadStatus.paused:
      final progress = task.received > 0
          ? '已下载 ${_formatByteCount(task.received)}'
          : '尚未开始传输';
      return '已暂停 · $progress';
    case DownloadStatus.completed:
      return '下载完成\n${task.filePath ?? task.file.size}';
    case DownloadStatus.failed:
      return '下载失败\n${task.error ?? '未知错误'}';
    case DownloadStatus.canceled:
      return '已取消';
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
        const SizedBox(height: 4),
        const Text('单选一个主页源，由它提供主页推荐应用和分类内容。'),
        const SizedBox(height: 20),
        RadioGroup<String>(
          groupValue: state.homeSourceId,
          onChanged: (value) {
            if (value != null) state.setHomeSource(value);
          },
          child: Column(
            children: state.sources
                .map((source) => SourceTile(source: source, state: state))
                .toList(),
          ),
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
            if (enabled)
              Tooltip(
                message: '设为主页与分类源',
                child: Radio<String>(value: source.id, enabled: enabled),
              ),
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
                        if (widget.app.packageName.trim().isNotEmpty)
                          Text(widget.app.packageName),
                        if (widget.app.version.trim().isNotEmpty ||
                            widget.app.size.trim().isNotEmpty)
                          Text(
                            [widget.app.version, widget.app.size]
                                .where((value) => value.trim().isNotEmpty)
                                .join(' · '),
                          ),
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
              if (snapshot.hasData)
                ..._buildDetailContent(context, snapshot.data!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDetailContent(BuildContext context, AppDetails detail) {
    final content = <Widget>[];
    if (detail.summary.trim().isNotEmpty) {
      content.add(Text(detail.summary));
      content.add(const SizedBox(height: 12));
    }
    if (detail.description.trim().isNotEmpty) {
      content.add(_ExpandableDescription(text: detail.description));
      content.add(const SizedBox(height: 20));
    }
    if (detail.screenshots.isNotEmpty) {
      content.add(Text('截图', style: Theme.of(context).textTheme.titleMedium));
      content.add(const SizedBox(height: 8));
      content.add(_ScreenshotGallery(urls: detail.screenshots));
      content.add(const SizedBox(height: 20));
    }
    if (detail.downloads.isNotEmpty) {
      content.add(Text('下载文件', style: Theme.of(context).textTheme.titleMedium));
      content.add(const SizedBox(height: 8));
      content.addAll(
        detail.downloads.map(
          (file) => _SourceDownloadTile(
            file: file,
            sourceId: widget.app.sourceId,
            state: widget.state,
          ),
        ),
      );
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

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text});
  final String text;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
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

class _ScreenshotGallery extends StatelessWidget {
  const _ScreenshotGallery({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _ScreenshotThumbnail(
          url: urls[index],
          onTap: () => _showScreenshot(context, index),
        ),
      ),
    );
  }

  void _showScreenshot(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (_) => _ScreenshotViewer(urls: urls, initialIndex: index),
    );
  }
}

class _ScreenshotThumbnail extends StatefulWidget {
  const _ScreenshotThumbnail({required this.url, required this.onTap});
  final String url;
  final VoidCallback onTap;

  @override
  State<_ScreenshotThumbnail> createState() => _ScreenshotThumbnailState();
}

class _ScreenshotThumbnailState extends State<_ScreenshotThumbnail> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double _aspectRatio = 1;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _ScreenshotThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _removeImageListener();
      _aspectRatio = 1;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final stream = NetworkImage(widget.url).resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      final image = info.image;
      if (!mounted || image.height == 0) return;
      final ratio = image.width / image.height;
      if ((ratio - _aspectRatio).abs() > .01) {
        setState(() => _aspectRatio = ratio);
      }
    });
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (190 * _aspectRatio).clamp(112.0, 360.0);
    return SizedBox(
      width: width,
      height: 190,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}

class _ScreenshotViewer extends StatefulWidget {
  const _ScreenshotViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_ScreenshotViewer> createState() => _ScreenshotViewerState();
}

class _ScreenshotViewerState extends State<_ScreenshotViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_currentIndex + 1} / ${widget.urls.length}'),
          actions: [
            IconButton(
              tooltip: '保存图片',
              onPressed: _saving ? null : _saveCurrent,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: PhotoViewGallery.builder(
          pageController: _pageController,
          itemCount: widget.urls.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          loadingBuilder: (context, event) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          builder: (context, index) => PhotoViewGalleryPageOptions(
            imageProvider: NetworkImage(widget.urls[index]),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained * .8,
            maxScale: PhotoViewComputedScale.covered * 3,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCurrent() async {
    setState(() => _saving = true);
    try {
      final response = await http.get(Uri.parse(widget.urls[_currentIndex]));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('图片请求失败：HTTP ${response.statusCode}');
      }
      await Gal.putImageBytes(
        response.bodyBytes,
        album: 'APK Mesh',
        name: _imageName(widget.urls[_currentIndex], _currentIndex),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已保存到系统相册')));
    } on GalException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存图片失败：${error.toString()}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存图片失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _imageName(String url, int index) {
    final path = Uri.tryParse(url)?.path ?? '';
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    final last = parts.isEmpty ? null : parts.last;
    final base = (last ?? '')
        .replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return base.isEmpty ? 'apkmesh_screenshot_${index + 1}' : 'apkmesh_$base';
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
        final detail = [
          if (file.size.trim().isNotEmpty) file.size,
          if (task != null) _downloadTaskDetail(task),
        ].join('\n');
        return Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (task?.status) {
                DownloadStatus.completed => Icons.check_circle_outline,
                DownloadStatus.paused => Icons.pause_circle_outline,
                DownloadStatus.canceled => Icons.cancel_outlined,
                DownloadStatus.failed => Icons.error_outline,
                _ => Icons.file_download_outlined,
              }),
              title: Text(file.label),
              subtitle: detail.isEmpty ? null : Text(detail),
              trailing: SizedBox(
                width: 112,
                child: _downloadButton(context, task),
              ),
            ),
            if (task?.status == DownloadStatus.downloading ||
                task?.status == DownloadStatus.paused)
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
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: '暂停下载',
            onPressed: () => state.pauseDownload(task!),
            icon: const Icon(Icons.pause),
          ),
          IconButton(
            tooltip: '取消下载',
            onPressed: () => state.cancelDownload(task!),
            icon: const Icon(Icons.close),
          ),
        ],
      );
    }
    if (task?.status == DownloadStatus.paused) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: '继续下载',
            onPressed: () => state.resumeDownload(task!),
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: '取消下载',
            onPressed: () => state.cancelDownload(task!),
            icon: const Icon(Icons.close),
          ),
        ],
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
    final retry =
        task?.status == DownloadStatus.failed ||
        task?.status == DownloadStatus.canceled;
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
