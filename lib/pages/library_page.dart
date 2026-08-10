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

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.state, required this.history});

  final AppState state;
  final bool history;

  List<AppListing> get apps => history ? state.history : state.favorites;

  @override
  Widget build(BuildContext context) {
    final items = apps;
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        children: [
          _buildHeader(context, 0),
          const SizedBox(height: 20),
          EmptyMessage(
            icon: history ? Icons.history : Icons.bookmark_border,
            title: history ? '暂无历史记录' : '暂无收藏应用',
            detail: history ? '打开应用详情后会自动记录在这里。' : '在应用列表或详情页点击书签即可收藏。',
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(context, items.length);
        final app = items[index - 1];
        return AppResultTile(
          key: ValueKey('${app.sourceId}:${app.id}'),
          app: app,
          state: state,
          onOpen: (selected) => showAppDetails(context, state, selected),
          showDivider: index < items.length,
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int count) => Row(
    children: [
      Expanded(
        child: Text(
          history ? '历史记录' : '我的收藏',
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
        tooltip: history ? '清空历史' : '清空收藏',
        onPressed: count == 0 ? null : () => _confirmClear(context),
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ],
  );

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(history ? '清空历史记录？' : '清空收藏？'),
        content: Text(history ? '这会移除所有历史记录。' : '这会移除所有收藏应用。'),
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
    if (history) {
      state.clearHistory();
    } else {
      state.clearFavorites();
    }
  }
}
