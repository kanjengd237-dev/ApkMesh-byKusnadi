import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import 'app_icon.dart';

class AppResultTile extends StatelessWidget {
  const AppResultTile({
    required this.app,
    required this.state,
    this.onOpen,
    this.showDivider = true,
    super.key,
  });

  final AppListing app;
  final AppState state;
  final ValueChanged<AppListing>? onOpen;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.translationSettings.autoTranslate) {
      state.ensureTranslations([app.name, app.description]);
    }
    final displayName = state.translatedText(app.name) ?? app.name;
    final description =
        state.translatedText(app.description) ?? app.description.trim();
    final chips = buildAppInfoChips(app, compact: true);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen == null ? null : () => onOpen!(app),
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
                          displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildCompactInfoRows(chips),
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

Widget _buildCompactInfoRows(List<Widget> items) {
  final split = (items.length + 1) ~/ 2;
  final firstRow = items.sublist(0, split);
  final secondRow = items.sublist(split);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(spacing: 12, runSpacing: 4, children: firstRow),
      if (secondRow.isNotEmpty) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 12, runSpacing: 4, children: secondRow),
      ],
    ],
  );
}

List<Widget> buildAppInfoChips(
  AppListing app, {
  VoidCallback? onPackageTap,
  bool compact = false,
}) {
  final chips = <Widget>[];
  final values = <({IconData icon, String text, Color seedColor})>[];

  void add(IconData icon, String value, Color seedColor) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty &&
        !values.any((item) => item.icon == icon && item.text == trimmed)) {
      values.add((icon: icon, text: trimmed, seedColor: seedColor));
    }
  }

  add(
    Icons.source_outlined,
    app.sourceName.trim().isNotEmpty ? app.sourceName : app.sourceId,
    Colors.blue,
  );
  add(Icons.category_outlined, app.category, Colors.green);
  add(Icons.new_releases_outlined, app.version, Colors.deepPurple);
  add(Icons.storage_outlined, app.size, Colors.deepOrange);
  add(Icons.update_outlined, app.updatedAt, Colors.teal);
  add(Icons.star_outline, app.rating, Colors.amber);
  add(Icons.person_outline, app.author, Colors.indigo);
  add(Icons.code_outlined, app.packageName, Colors.cyan);

  for (final value in values) {
    final onPressed = value.icon == Icons.code_outlined ? onPackageTap : null;
    if (compact) {
      chips.add(
        _AppInfoLabel(icon: value.icon, text: value.text, onPressed: onPressed),
      );
    } else {
      chips.add(
        _AppInfoChip(
          icon: value.icon,
          text: value.text,
          seedColor: value.seedColor,
          onPressed: onPressed,
        ),
      );
    }
  }
  return chips;
}

class _AppInfoLabel extends StatelessWidget {
  const _AppInfoLabel({required this.icon, required this.text, this.onPressed});

  final IconData icon;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor = onPressed == null
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.primary;
    final label = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    return onPressed == null
        ? label
        : Tooltip(
            message: '按包名查找应用',
            child: Semantics(
              button: true,
              onTap: onPressed,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPressed,
                child: label,
              ),
            ),
          );
  }
}

class _AppInfoChip extends StatelessWidget {
  const _AppInfoChip({
    required this.icon,
    required this.text,
    required this.seedColor,
    this.onPressed,
  });

  final IconData icon;
  final String text;
  final Color seedColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: theme.brightness,
    );
    final foregroundColor = scheme.onPrimaryContainer;
    final common = ChipTheme.of(context).copyWith(
      labelPadding: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.primaryContainer,
    );

    final chip = Chip(
      avatar: Icon(icon, size: 16, color: foregroundColor),
      label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: foregroundColor,
        fontWeight: FontWeight.w600,
      ),
      labelPadding: common.labelPadding,
      padding: common.padding,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      backgroundColor: common.backgroundColor,
      side: common.side,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: onPressed == null
          ? chip
          : Tooltip(
              message: '按包名查找应用',
              child: Semantics(
                button: true,
                onTap: onPressed,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPressed,
                  child: chip,
                ),
              ),
            ),
    );
  }
}
