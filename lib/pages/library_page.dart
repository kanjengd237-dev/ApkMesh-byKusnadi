import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/app_result_tile.dart';
import '../widgets/empty_message.dart';
import 'details_sheet.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.bookmark_outline), text: '收藏'),
              Tab(icon: Icon(Icons.history), text: '历史'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _LibraryList(state: state, history: false),
              _LibraryList(state: state, history: true),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LibraryList extends StatefulWidget {
  const _LibraryList({required this.state, required this.history});

  final AppState state;
  final bool history;

  @override
  State<_LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<_LibraryList> {
  final Map<String, AppListing> _selectedApps = {};
  bool _selectionMode = false;

  List<AppListing> get apps =>
      widget.history ? widget.state.history : widget.state.favorites;

  String _appKey(AppListing app) => '${app.sourceId}\u0000${app.id}';

  bool _isSelected(AppListing app) => _selectedApps.containsKey(_appKey(app));

  void _enterSelection(AppListing app) {
    setState(() {
      _selectionMode = true;
      _selectedApps[_appKey(app)] = app;
    });
  }

  void _toggleSelection(AppListing app) {
    final key = _appKey(app);
    setState(() {
      if (_selectedApps.remove(key) == null) _selectedApps[key] = app;
    });
  }

  void _exitSelection() {
    if (!_selectionMode && _selectedApps.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedApps.clear();
    });
  }

  void _favoriteSelected() {
    final added = widget.state.favoriteApps(_selectedApps.values);
    _exitSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added == 0 ? '所选应用已在收藏中' : '已收藏 $added 个应用')),
    );
  }

  void _downloadSelected() {
    final selected = _selectedApps.values.toList(growable: false);
    if (selected.isEmpty) return;
    _exitSelection();
    final messenger = ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('正在后台解析下载链接…')));
    unawaited(_runBatchDownload(selected, messenger));
  }

  Future<void> _runBatchDownload(
    List<AppListing> selected,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      final result = await widget.state.downloadApps(selected);
      if (!mounted || !messenger.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.startedFiles == 0
                  ? '批量下载失败：没有找到可用下载链接'
                  : result.appsWithErrors == 0
                  ? '已开始下载 ${result.startedFiles} 个文件，可在下载页查看进度'
                  : '已开始下载 ${result.startedFiles} 个文件，${result.appsWithErrors} 个应用存在解析或下载问题',
            ),
          ),
        );
    } catch (error) {
      if (!mounted || !messenger.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('批量下载失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = apps;
    final content = items.isEmpty
        ? ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              _buildHeader(context, 0),
              const SizedBox(height: 20),
              EmptyMessage(
                icon: widget.history ? Icons.history : Icons.bookmark_border,
                title: widget.history ? '暂无历史记录' : '暂无收藏应用',
                detail: widget.history
                    ? '打开应用详情后会自动记录在这里。'
                    : '在应用列表或详情页点击书签即可收藏。',
              ),
            ],
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildHeader(context, items.length);
              final app = items[index - 1];
              return AppResultTile(
                key: ValueKey('${app.sourceId}:${app.id}'),
                app: app,
                state: widget.state,
                onOpen: (selected) =>
                    showAppDetails(context, widget.state, selected),
                onEnterSelection: _enterSelection,
                onSelect: _toggleSelection,
                selectionMode: _selectionMode,
                selected: _isSelected(app),
                showDivider: index < items.length,
              );
            },
          );

    return Column(
      children: [
        if (_selectionMode)
          AppSelectionToolbar(
            selectedCount: _selectedApps.length,
            onClose: _exitSelection,
            onDownload: _downloadSelected,
            onFavorite: _favoriteSelected,
          ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int count) => Row(
    children: [
      Expanded(
        child: Text(
          widget.history ? '历史记录' : '我的收藏',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
      Text(
        '$count',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: widget.history ? '清空历史' : '清空收藏',
        onPressed: count == 0 ? null : () => _confirmClear(context),
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ],
  );

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.history ? '清空历史记录？' : '清空收藏？'),
        content: Text(widget.history ? '这会移除所有历史记录。' : '这会移除所有收藏应用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.history) {
      widget.state.clearHistory();
    } else {
      widget.state.clearFavorites();
    }
  }
}
