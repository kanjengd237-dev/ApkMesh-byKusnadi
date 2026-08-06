import 'package:flutter/material.dart';

import 'core/app_state.dart';
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
      const SettingsPage(),
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
                tooltip: '搜索',
                onPressed: () => setState(() => index = 0),
                icon: const Icon(Icons.search),
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

  Future<void> search() async {
    setState(() => loading = true);
    final found = await widget.state.search(widget.controller.text);
    if (mounted) {
      setState(() {
        results = found;
        loading = false;
      });
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
        if (!loading && results.isEmpty && widget.state.hasEnabledSource)
          const EmptyMessage(
            icon: Icons.manage_search,
            title: '输入关键词开始搜索',
            detail: '结果会合并所有已启用源的数据。',
          ),
        ...results.map((app) => AppResultTile(app: app)),
      ],
    );
  }
}

class AppResultTile extends StatelessWidget {
  const AppResultTile({required this.app, super.key});
  final AppListing app;

  @override
  Widget build(BuildContext context) {
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
        trailing: IconButton(
          tooltip: '查看详情',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => DetailsSheet(app: app),
          ),
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
  const SettingsPage({super.key});

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
      const ListTile(
        leading: Icon(Icons.security_outlined),
        title: Text('安装权限'),
        subtitle: Text('安装 APK 前由系统请求“允许安装未知应用”权限'),
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

class DetailsSheet extends StatelessWidget {
  const DetailsSheet({required this.app, super.key});
  final AppListing app;

  @override
  Widget build(BuildContext context) {
    final details = app is AppDetails ? app as AppDetails : null;
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
                AppIcon(url: app.iconUrl),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(app.packageName),
                      Text('${app.version} · ${app.size}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(details?.description ?? app.summary),
            if (details != null) ...[
              const SizedBox(height: 24),
              Text('下载文件', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...details.downloads.map(
                (file) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(file.label),
                  subtitle: Text(file.size),
                  trailing: FilledButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('下载能力将在接入宿主 API 后启用')),
                    ),
                    child: const Text('下载'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('评论', style: Theme.of(context).textTheme.titleMedium),
              ...details.comments.map(
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
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({required this.url, super.key});
  final String url;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.network(
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
