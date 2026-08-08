import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';

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
        const SizedBox(height: 20),
        Column(
          children: state.sources
              .map((source) => SourceTile(source: source, state: state))
              .toList(),
        ),
      ],
    );
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

class SourceTile extends StatelessWidget {
  const SourceTile({required this.source, required this.state, super.key});
  final ApkSource source;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final enabled = source.status == SourceStatus.enabled;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Icon(
                  source.builtIn ? Icons.inventory_2_outlined : Icons.code,
                ),
              ),
              title: Text(source.name),
              subtitle: Text(
                '${source.description}\n${source.homepage} · v${source.version}',
              ),
              isThreeLine: false,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ChoiceChip(
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
                Switch(
                  value: enabled,
                  onChanged: (value) => state.toggleSource(source.id, value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
