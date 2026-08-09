import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import 'source_debug_test_sheet.dart';
import 'source_test_sheet.dart';

enum _SourceBulkAction { selectAll, invert, range, enable, disable }

class SourcesPage extends StatefulWidget {
  const SourcesPage({required this.state, super.key});

  final AppState state;

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  int? _selectionAnchor;
  int? _rangeEnd;

  AppState get state => widget.state;

  Set<String> get _selectedSourceIds {
    final sourceIds = state.sources.map((source) => source.id).toSet();
    return _selectedIds.intersection(sourceIds);
  }

  Set<String> get _testableSelectedIds => state.sources
      .where(
        (source) =>
            source.status == SourceStatus.enabled &&
            _selectedSourceIds.contains(source.id),
      )
      .map((source) => source.id)
      .toSet();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        _buildHeader(context),
        const SizedBox(height: 20),
        Column(
          children: state.sources.asMap().entries.map((entry) {
            final source = entry.value;
            return SourceTile(
              key: ValueKey(source.id),
              source: source,
              state: state,
              selectionMode: _selectionMode,
              selected: _selectedSourceIds.contains(source.id),
              onLongPress: () => _enterSelection(entry.key),
              onSelectionToggle: () => _toggleSelection(entry.key),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final showAllSelectionActions = constraints.maxWidth >= 760;
        final selectionActions = _buildSelectionActions();
        final batchTest = OutlinedButton.icon(
          onPressed: _selectionMode && _testableSelectedIds.isEmpty
              ? null
              : _openBatchTest,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('批量测试'),
        );
        final importButton = FilledButton.icon(
          onPressed: () => _showAddSource(context),
          icon: const Icon(Icons.add),
          label: const Text('导入源'),
        );
        final title = Text(
          _selectionMode ? '已选择 ${_selectedSourceIds.length} 个源' : '源管理',
          style: Theme.of(context).textTheme.headlineMedium,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_selectionMode)
                    IconButton(
                      tooltip: '退出多选',
                      onPressed: _exitSelection,
                      icon: const Icon(Icons.close),
                    ),
                  Expanded(child: title),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_selectionMode) _buildOverflowMenu(),
                    batchTest,
                    importButton,
                  ],
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            if (_selectionMode)
              IconButton(
                tooltip: '退出多选',
                onPressed: _exitSelection,
                icon: const Icon(Icons.close),
              ),
            Expanded(child: title),
            if (_selectionMode)
              if (showAllSelectionActions)
                ...selectionActions
              else
                _buildOverflowMenu(),
            batchTest,
            const SizedBox(width: 8),
            importButton,
          ],
        );
      },
    );
  }

  List<Widget> _buildSelectionActions() => [
    IconButton(
      tooltip: '全选',
      onPressed: _selectAll,
      icon: const Icon(Icons.select_all),
    ),
    IconButton(
      tooltip: '反选',
      onPressed: _invertSelection,
      icon: const Icon(Icons.swap_vert),
    ),
    IconButton(
      tooltip: '区间选择',
      onPressed: _selectRange,
      icon: const Icon(Icons.unfold_more),
    ),
    IconButton(
      tooltip: '开启选中源',
      onPressed: _selectedSourceIds.isEmpty
          ? null
          : () => _setSelectedEnabled(true),
      icon: const Icon(Icons.toggle_on_outlined),
    ),
    IconButton(
      tooltip: '关闭选中源',
      onPressed: _selectedSourceIds.isEmpty
          ? null
          : () => _setSelectedEnabled(false),
      icon: const Icon(Icons.toggle_off_outlined),
    ),
  ];

  Widget _buildOverflowMenu() => PopupMenuButton<_SourceBulkAction>(
    tooltip: '批量管理',
    icon: const Icon(Icons.more_vert),
    onSelected: _handleBulkAction,
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: _SourceBulkAction.selectAll,
        child: _BulkActionMenuLabel(icon: Icons.select_all, label: '全选'),
      ),
      const PopupMenuItem(
        value: _SourceBulkAction.invert,
        child: _BulkActionMenuLabel(icon: Icons.swap_vert, label: '反选'),
      ),
      const PopupMenuItem(
        value: _SourceBulkAction.range,
        child: _BulkActionMenuLabel(icon: Icons.unfold_more, label: '区间选择'),
      ),
      PopupMenuItem(
        value: _SourceBulkAction.enable,
        enabled: _selectedSourceIds.isNotEmpty,
        child: const _BulkActionMenuLabel(
          icon: Icons.toggle_on_outlined,
          label: '开启',
        ),
      ),
      PopupMenuItem(
        value: _SourceBulkAction.disable,
        enabled: _selectedSourceIds.isNotEmpty,
        child: const _BulkActionMenuLabel(
          icon: Icons.toggle_off_outlined,
          label: '关闭',
        ),
      ),
    ],
  );

  void _handleBulkAction(_SourceBulkAction action) {
    switch (action) {
      case _SourceBulkAction.selectAll:
        _selectAll();
      case _SourceBulkAction.invert:
        _invertSelection();
      case _SourceBulkAction.range:
        _selectRange();
      case _SourceBulkAction.enable:
        _setSelectedEnabled(true);
      case _SourceBulkAction.disable:
        _setSelectedEnabled(false);
    }
  }

  void _enterSelection(int index) {
    if (index < 0 || index >= state.sources.length) return;
    setState(() {
      _selectionMode = true;
      _selectedIds.add(state.sources[index].id);
      _selectionAnchor = index;
      _rangeEnd = index;
    });
  }

  void _toggleSelection(int index) {
    if (index < 0 || index >= state.sources.length) return;
    if (!_selectionMode) {
      _enterSelection(index);
      return;
    }
    final id = state.sources[index].id;
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
      _rangeEnd = index;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
      _selectionAnchor = null;
      _rangeEnd = null;
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(state.sources.map((source) => source.id));
      _selectionMode = true;
    });
  }

  void _invertSelection() {
    final allIds = state.sources.map((source) => source.id).toSet();
    final inverted = allIds.difference(_selectedSourceIds);
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(inverted);
      _selectionMode = true;
    });
  }

  void _selectRange() {
    if (state.sources.isEmpty) return;
    final anchor =
        _selectionAnchor ??
        state.sources.indexWhere(
          (source) => _selectedSourceIds.contains(source.id),
        );
    final end = _rangeEnd ?? anchor;
    if (anchor < 0 || end < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择区间起点和终点')));
      return;
    }
    final start = anchor < end ? anchor : end;
    final finish = anchor < end ? end : anchor;
    setState(() {
      _selectedIds.addAll(
        state.sources.sublist(start, finish + 1).map((source) => source.id),
      );
      _selectionMode = true;
    });
  }

  void _setSelectedEnabled(bool enabled) {
    final selected = _selectedSourceIds;
    if (selected.isEmpty) return;
    state.setSourcesEnabled(selected, enabled);
  }

  void _openBatchTest() {
    if (_selectionMode) {
      final selected = _testableSelectedIds;
      if (selected.isEmpty) return;
      showSourceBatchTestSheet(context, state, sourceIds: selected);
      return;
    }
    showSourceBatchTestSheet(context, state);
  }

  void _showAddSource(BuildContext context) {
    final url = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var busy = false;
        String? error;

        return StatefulBuilder(
          builder: (dialogBuildContext, setDialogState) {
            Future<void> runImport(
              Future<SourceImportResult> Function() action,
            ) async {
              setDialogState(() {
                busy = true;
                error = null;
              });
              try {
                final result = await action();
                if (!dialogContext.mounted) return;
                if (result.imported.isEmpty) {
                  setDialogState(() {
                    error = result.failures.entries
                        .map((entry) => '${entry.key}: ${entry.value}')
                        .join('\n');
                  });
                  return;
                }
                Navigator.pop(dialogContext);
                final message = result.failures.isEmpty
                    ? '已导入 ${result.imported.length} 个源'
                    : '已导入 ${result.imported.length} 个源，失败 ${result.failures.length} 个';
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                }
              } catch (importError) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  error = importError.toString();
                });
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    busy = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('导入源'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: url,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: '源 URL',
                        hintText: 'https://example.com/source.js',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => runImport(() async {
                              final result = await FilePicker.platform
                                  .pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['js', 'zip'],
                                    allowMultiple: false,
                                    withData: true,
                                  );
                              if (result == null) {
                                return const SourceImportResult(
                                  imported: [],
                                  failures: {},
                                );
                              }
                              final file = result.files.single;
                              final bytes =
                                  file.bytes ?? await file.xFile.readAsBytes();
                              return state.importSourceBytes(bytes, file.name);
                            }),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('从系统文件选择 JS 或 ZIP'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(dialogBuildContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          if (url.text.trim().isEmpty) {
                            setDialogState(() {
                              error = '请输入源 URL';
                            });
                            return;
                          }
                          runImport(() => state.importSourceUrl(url.text));
                        },
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('从 URL 导入'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(url.dispose);
  }
}

class _BulkActionMenuLabel extends StatelessWidget {
  const _BulkActionMenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]);
}

class SourceTile extends StatelessWidget {
  const SourceTile({
    required this.source,
    required this.state,
    required this.selectionMode,
    required this.selected,
    required this.onLongPress,
    required this.onSelectionToggle,
    super.key,
  });

  final ApkSource source;
  final AppState state;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onSelectionToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = source.status == SourceStatus.enabled;
    final projects = state.debugProjects
        .where((project) => project.sourceId == source.id)
        .toList(growable: false);
    final leading = CircleAvatar(
      child: Icon(source.builtIn ? Icons.inventory_2_outlined : Icons.code),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: selected
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selectionMode ? onSelectionToggle : null,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: selectionMode
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: selected,
                            onChanged: (_) => onSelectionToggle(),
                          ),
                          leading,
                        ],
                      )
                    : leading,
                title: Text(source.name),
                subtitle: Text(
                  '${source.description}\n${source.homepage} · v${source.version}',
                ),
                isThreeLine: false,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PopupMenuButton<SourceDebugProject>(
                    tooltip: '查看测试项目',
                    onSelected: (project) =>
                        showSourceDebugTestSheet(context, state, project),
                    itemBuilder: (context) => projects.isEmpty
                        ? const [
                            PopupMenuItem<SourceDebugProject>(
                              enabled: false,
                              child: Text('暂无可测试项目'),
                            ),
                          ]
                        : projects
                              .map(
                                (project) => PopupMenuItem<SourceDebugProject>(
                                  value: project,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.play_circle_outline),
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(project.name),
                                            if (project.description.isNotEmpty)
                                              Text(
                                                project.description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                    child: const Chip(
                      avatar: Icon(Icons.fact_check_outlined, size: 18),
                      label: Text('测试'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    avatar: source.homeSource
                        ? null
                        : const Icon(Icons.home_outlined, size: 18),
                    showCheckmark: true,
                    label: const Text('主页'),
                    selected: source.homeSource,
                    onSelected: enabled
                        ? (selected) {
                            if (selected) state.setHomeSource(source.id);
                          }
                        : null,
                  ),
                  if (!source.builtIn)
                    IconButton(
                      tooltip: '删除源',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => state.removeSource(source.id),
                    ),
                  const SizedBox(width: 12),
                  Switch(
                    value: enabled,
                    onChanged: (value) => state.toggleSource(source.id, value),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
