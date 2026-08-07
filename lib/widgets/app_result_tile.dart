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
    final description = app.description.trim();
    final chips = buildAppInfoChips(app);

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
                          app.name,
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
                          Wrap(spacing: 6, runSpacing: 2, children: chips),
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

List<Widget> buildAppInfoChips(AppListing app, {VoidCallback? onPackageTap}) {
  final chips = <Widget>[];
  final values = <({IconData icon, String text})>[];

  void add(IconData icon, String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty &&
        !values.any((item) => item.icon == icon && item.text == trimmed)) {
      values.add((icon: icon, text: trimmed));
    }
  }

  add(
    Icons.source_outlined,
    app.sourceName.trim().isNotEmpty ? app.sourceName : app.sourceId,
  );
  add(Icons.category_outlined, app.category);
  add(Icons.new_releases_outlined, app.version);
  add(Icons.storage_outlined, app.size);
  add(Icons.update_outlined, app.updatedAt);
  add(Icons.star_outline, app.rating);
  add(Icons.person_outline, app.author);
  add(Icons.code_outlined, app.packageName);

  for (final value in values) {
    chips.add(
      _AppInfoChip(
        icon: value.icon,
        text: value.text,
        onPressed: value.icon == Icons.code_outlined ? onPackageTap : null,
      ),
    );
  }
  return chips;
}

class _AppInfoChip extends StatelessWidget {
  const _AppInfoChip({required this.icon, required this.text, this.onPressed});

  final IconData icon;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    final avatar = Icon(icon, size: 16, color: scheme.onSurfaceVariant);
    final common = ChipTheme.of(context).copyWith(
      labelPadding: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: .72),
    );

    final chip = Chip(
      avatar: avatar,
      label: label,
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
