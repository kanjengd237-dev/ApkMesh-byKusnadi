import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/empty_message.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tasks = state.downloads;
    final completedCount = tasks
        .where((task) => task.status == DownloadStatus.completed)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                '下载管理',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            PopupMenuButton<DownloadClearAction>(
              enabled: tasks.isNotEmpty,
              tooltip: '清理下载',
              icon: const Icon(Icons.delete_sweep_outlined),
              onSelected: (action) =>
                  confirmClearDownloads(context, state, action),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: DownloadClearAction.all,
                  child: Text('清除全部'),
                ),
                PopupMenuItem(
                  value: DownloadClearAction.completed,
                  enabled: completedCount > 0,
                  child: const Text('清除已下载'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (tasks.isEmpty)
          const EmptyMessage(
            icon: Icons.download_done_outlined,
            title: '暂无下载任务',
            detail: '从应用详情中选择文件后，任务会显示在这里。',
          )
        else
          ...tasks.asMap().entries.map(
            (entry) => DownloadTaskTile(
              task: entry.value,
              state: state,
              showDivider: entry.key < tasks.length - 1,
            ),
          ),
      ],
    );
  }
}

enum DownloadClearAction { all, completed }

Future<void> confirmClearDownloads(
  BuildContext context,
  AppState state,
  DownloadClearAction action,
) async {
  final completedOnly = action == DownloadClearAction.completed;
  final count = state.downloads
      .where(
        (task) => !completedOnly || task.status == DownloadStatus.completed,
      )
      .length;
  if (count == 0) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(completedOnly ? '清除已下载文件？' : '清除全部下载？'),
      content: Text(
        completedOnly
            ? '将删除 $count 个已下载文件及其记录。'
            : '将删除 $count 个下载文件及其记录，进行中的任务也会取消。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await state.clearDownloads(completedOnly: completedOnly);
  }
}

class DownloadTaskTile extends StatelessWidget {
  const DownloadTaskTile({
    required this.task,
    required this.state,
    this.showDivider = true,
    super.key,
  });

  final DownloadTask task;
  final AppState state;
  final bool showDivider;

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
    final detail = downloadTaskDetail(task);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.file.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
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
  }
}

class DownloadTaskControls extends StatefulWidget {
  const DownloadTaskControls({
    required this.task,
    required this.state,
    super.key,
  });

  final DownloadTask task;
  final AppState state;

  @override
  State<DownloadTaskControls> createState() => _DownloadTaskControlsState();
}

class _DownloadTaskControlsState extends State<DownloadTaskControls> {
  @override
  void initState() {
    super.initState();
    _refreshInstallState();
  }

  @override
  void didUpdateWidget(covariant DownloadTaskControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.status != widget.task.status ||
        oldWidget.task.filePath != widget.task.filePath) {
      _refreshInstallState();
    }
  }

  void _refreshInstallState() {
    final task = widget.task;
    if (task.status == DownloadStatus.completed && task.filePath != null) {
      unawaited(widget.state.refreshInstallState(task));
    }
  }

  Future<void> _openInstalled() async {
    try {
      await widget.state.openInstalledTask(widget.task);
    } catch (error) {
      if (mounted) {
        showActionErrorSnackBar(context, summary: '打开失败', error: error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final state = widget.state;
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
        final paused = task.status == DownloadStatus.paused;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 4,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: paused ? '继续下载' : '暂停下载',
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              onPressed: () => paused
                  ? state.resumeDownload(task)
                  : state.pauseDownload(task),
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            ),
            IconButton(
              tooltip: '取消下载',
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              onPressed: () => state.cancelDownload(task),
              icon: const Icon(Icons.close),
            ),
          ],
        );
      case DownloadStatus.completed:
        final installInfo = state.installInfoFor(task.id);
        if (state.isInstallingDownload(task.id)) {
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 88,
              height: 40,
              child: FilledButton(
                onPressed: null,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }
        if (installInfo?.versionMatches == true) {
          return Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('打开'),
              onPressed: _openInstalled,
            ),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: const Icon(Icons.install_mobile_outlined),
            label: const Text('安装'),
            onPressed: () => installDownloadTask(context, state, task),
          ),
        );
      case DownloadStatus.failed:
        return Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '重试下载',
            onPressed: () => state.retryDownload(task),
            icon: const Icon(Icons.refresh),
          ),
        );
      case DownloadStatus.canceled:
        return const SizedBox.shrink();
    }
  }
}

String? downloadTaskDetail(DownloadTask task) {
  switch (task.status) {
    case DownloadStatus.downloading:
      final total = task.total;
      final progress = total != null && total > 0
          ? '${formatByteCount(task.received)} / ${formatByteCount(total)} · ${((task.progress ?? 0) * 100).toStringAsFixed(0)}%'
          : task.received > 0
          ? '已下载 ${formatByteCount(task.received)}'
          : '正在连接';
      final stats = <String>[];
      final speed = task.speedBytesPerSecond;
      if (speed != null && speed > 0) {
        stats.add('速度 ${formatByteCount(speed)}/s');
      }
      final remaining = task.estimatedRemaining;
      if (remaining != null) {
        stats.add('预计 ${formatDownloadDuration(remaining)}');
      }
      return [progress, ...stats].join(' · ');
    case DownloadStatus.paused:
      final progress = task.received > 0
          ? '已下载 ${formatByteCount(task.received)}'
          : '尚未开始传输';
      return '已暂停 · $progress';
    case DownloadStatus.completed:
      return null;
    case DownloadStatus.failed:
      return '下载失败\n${task.error ?? '未知错误'}';
    case DownloadStatus.canceled:
      return '已取消';
  }
}

String formatByteCount(int bytes) {
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

String formatDownloadDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 1 ? 1 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = totalSeconds % 3600 ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return minutes > 0 ? '$hours 小时 $minutes 分钟' : '$hours 小时';
  }
  if (minutes > 0) {
    return seconds > 0 ? '$minutes 分钟 $seconds 秒' : '$minutes 分钟';
  }
  return '$seconds 秒';
}

Future<void> installDownloadTask(
  BuildContext context,
  AppState state,
  DownloadTask task,
) async {
  try {
    final useShizuku = state.useShizukuInstaller;
    final installed = await state.installTask(task);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          installed
              ? useShizuku
                    ? '已通过 Shizuku 安装'
                    : '已交给系统安装器'
              : '安装未完成，请检查安装权限后重试',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    showActionErrorSnackBar(context, summary: '安装失败', error: error);
  }
}

void showActionErrorSnackBar(
  BuildContext context, {
  required String summary,
  required Object error,
}) {
  final detail = error.toString();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(summary),
        action: SnackBarAction(
          label: '详情',
          onPressed: () {
            if (!context.mounted) return;
            showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text('$summary详情'),
                content: SingleChildScrollView(child: SelectableText(detail)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
}
