import 'package:flutter/material.dart';

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
        ...results.map((app) => AppResultTile(app: app, state: widget.state)),
      ],
    );
  }
}

class AppResultTile extends StatelessWidget {
  const AppResultTile({required this.app, required this.state, super.key});
  final AppListing app;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    void openDetails() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => DetailsSheet(app: app, state: state),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: AppIcon(url: app.iconUrl),
        title: Text(app.name),
        subtitle: Text(
          '${app.summary}\n${app.version} · ${app.size} · ${app.sourceName}',
        ),
        isThreeLine: true,
        onTap: openDetails,
        trailing: IconButton(
          tooltip: '查看详情',
          icon: const Icon(Icons.chevron_right),
          onPressed: openDetails,
        ),
      ),
    );
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          child: Icon(source.builtIn ? Icons.inventory_2_outlined : Icons.code),
        ),
        title: Text(source.name),
        subtitle: Text(
          '${source.description}\n${source.homepage} · v${source.version}',
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

class DebugSheet extends StatelessWidget {
  const DebugSheet({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      minChildSize: .45,
      maxChildSize: .96,
      builder: (_, controller) => AnimatedBuilder(
        animation: state.debug,
        builder: (context, _) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '调试信息',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '清空日志',
                    onPressed: state.debug.entries.isEmpty
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
              const Divider(),
              Text('运行时', style: Theme.of(context).textTheme.titleMedium),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  state.sourceRuntimeReady
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                ),
                title: Text(
                  state.sourceRuntimeReady ? 'QuickJS 源已加载' : '使用演示源',
                ),
                subtitle: Text(
                  state.runtimeError ??
                      '已启用源：${state.sources.where((source) => source.status == SourceStatus.enabled).map((source) => source.name).join('、')}',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.web_outlined),
                title: Text(
                  'WebView：${state.host.supportsBrowser ? '可用' : '不可用'}',
                ),
                subtitle: Text(
                  '安装能力：${state.host.supportsInstall ? '可用' : '不可用'}',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'WebView 状态',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              if (state.host.browserTabs.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.web_asset_off_outlined),
                  title: Text('暂无 WebView 标签'),
                  subtitle: Text('源未打开详情页，或最近一次标签已清理。'),
                )
              else
                ...state.host.browserTabs.map((tab) => _DebugTabTile(tab: tab)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Text('${state.debug.entries.length} 条'),
                ],
              ),
              const SizedBox(height: 4),
              if (state.debug.entries.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.article_outlined),
                  title: Text('暂无日志'),
                )
              else
                ...state.debug.entries.reversed.map(
                  (entry) => _DebugLogTile(entry: entry),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugTabTile extends StatelessWidget {
  const _DebugTabTile({required this.tab});
  final BrowserTabDebugInfo tab;

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
                  (file) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text(file.label),
                    subtitle: Text(file.size),
                    trailing: FilledButton(
                      onPressed: () async {
                        try {
                          final path = await widget.state.download(
                            file,
                            widget.app.sourceId,
                          );
                          if (context.mounted) {
                            final shouldInstall = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('下载完成'),
                                content: Text(
                                  '文件已保存到：$path\n是否交给系统安装器？请先确认来源和签名。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('稍后安装'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('安装'),
                                  ),
                                ],
                              ),
                            );
                            if (shouldInstall == true) {
                              try {
                                final installed = await widget.state.install(
                                  path,
                                  widget.app.sourceId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        installed ? '已交给系统安装器' : '系统未接受此安装请求',
                                      ),
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('安装失败：$error')),
                                  );
                                }
                              }
                            }
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('下载失败：$error')),
                            );
                          }
                        }
                      },
                      child: const Text('下载'),
                    ),
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

class AppIcon extends StatelessWidget {
  const AppIcon({required this.url, super.key});
  final String url;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: url.isEmpty
        ? Container(
            width: 56,
            height: 56,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.android),
          )
        : Image.network(
            url,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 56,
              height: 56,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.android),
            ),
          ),
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
