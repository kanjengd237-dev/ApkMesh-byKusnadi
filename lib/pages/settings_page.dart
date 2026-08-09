import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/translation_service.dart';

String _themeModeLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => '跟随系统',
  AppThemeMode.light => '浅色',
  AppThemeMode.dark => '深色',
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
    children: [
      Text('设置', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 20),
      ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('主题'),
        subtitle: Text(_themeModeLabel(state.themeMode)),
        trailing: DropdownButton<AppThemeMode>(
          value: state.themeMode,
          onChanged: (value) {
            if (value != null) state.setThemeMode(value);
          },
          items: [
            for (final mode in AppThemeMode.values)
              DropdownMenuItem(value: mode, child: Text(_themeModeLabel(mode))),
          ],
        ),
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.download_outlined),
        title: Text('下载目录'),
        subtitle: Text('系统默认下载目录'),
      ),
      const Divider(),
      _SourceConcurrencySettingsTile(state: state),
      const Divider(),
      TranslationSettingsPanel(state: state),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.security_outlined),
        title: const Text('安装权限'),
        subtitle: const Text('安装 APK 前需要允许本应用安装未知来源的应用'),
        trailing: state.host.supportsInstall
            ? IconButton(
                tooltip: '打开系统安装权限',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => state.host.requestInstallPermission(),
              )
            : null,
      ),
      if (state.host.supportsShizuku) ...[
        const Divider(),
        _ShizukuInstallationSettingsPanel(state: state),
      ],
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

class _SourceConcurrencySettingsTile extends StatelessWidget {
  const _SourceConcurrencySettingsTile({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final settings = state.sourceConcurrency;
    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: const Text('源并发设置'),
      subtitle: Text(
        'HTTP ${settings.httpRequests} · WebView ${settings.webViews}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _SourceConcurrencySheet(state: state),
      ),
    );
  }
}

class _SourceConcurrencySheet extends StatefulWidget {
  const _SourceConcurrencySheet({required this.state});

  final AppState state;

  @override
  State<_SourceConcurrencySheet> createState() =>
      _SourceConcurrencySheetState();
}

class _SourceConcurrencySheetState extends State<_SourceConcurrencySheet> {
  late int _httpRequests;
  late int _webViews;
  late final TextEditingController _httpController;
  late final TextEditingController _webViewController;

  @override
  void initState() {
    super.initState();
    final settings = widget.state.sourceConcurrency;
    _httpRequests = settings.httpRequests;
    _webViews = settings.webViews;
    _httpController = TextEditingController(text: '$_httpRequests');
    _webViewController = TextEditingController(text: '$_webViews');
  }

  @override
  void dispose() {
    _httpController.dispose();
    _webViewController.dispose();
    super.dispose();
  }

  int? _positiveValue(TextEditingController controller) {
    final value = int.tryParse(controller.text);
    return value == null || value < 1 ? null : value;
  }

  bool get _valid =>
      _positiveValue(_httpController) != null &&
      _positiveValue(_webViewController) != null;

  void _setHttpRequests(int value) {
    setState(() {
      _httpRequests = math.max(1, value);
      _httpController.text = '$_httpRequests';
    });
  }

  void _setWebViews(int value) {
    setState(() {
      _webViews = math.max(1, value);
      _webViewController.text = '$_webViews';
    });
  }

  void _readHttpRequests(String _) {
    final value = _positiveValue(_httpController);
    setState(() {
      if (value != null) _httpRequests = value;
    });
  }

  void _readWebViews(String _) {
    final value = _positiveValue(_webViewController);
    setState(() {
      if (value != null) _webViews = value;
    });
  }

  void _restoreDefaults() {
    _setHttpRequests(SourceConcurrencySettings.defaultHttpRequests);
    _setWebViews(SourceConcurrencySettings.defaultWebViews);
  }

  void _apply() {
    final httpRequests = _positiveValue(_httpController);
    final webViews = _positiveValue(_webViewController);
    if (httpRequests == null || webViews == null) return;
    widget.state.setSourceConcurrency(
      httpRequests: httpRequests,
      webViews: webViews,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '源并发设置',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _ConcurrencyControl(
                  icon: Icons.language_outlined,
                  title: 'HTTP 请求',
                  subtitle: '同时执行的源网络请求数',
                  value: _httpRequests,
                  baselineMax: 100,
                  controller: _httpController,
                  onSliderChanged: (value) => _setHttpRequests(value.round()),
                  onTextChanged: _readHttpRequests,
                ),
                const Divider(height: 40),
                _ConcurrencyControl(
                  icon: Icons.web_asset_outlined,
                  title: '隐藏 WebView',
                  subtitle: '同时保持活动的浏览器标签页数',
                  value: _webViews,
                  baselineMax: 10,
                  controller: _webViewController,
                  onSliderChanged: (value) => _setWebViews(value.round()),
                  onTextChanged: _readWebViews,
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _restoreDefaults,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('恢复默认值'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _valid ? _apply : null,
                      icon: const Icon(Icons.check),
                      label: const Text('应用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConcurrencyControl extends StatelessWidget {
  const _ConcurrencyControl({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.baselineMax,
    required this.controller,
    required this.onSliderChanged,
    required this.onTextChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final double baselineMax;
  final TextEditingController controller;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<String> onTextChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valid = (int.tryParse(controller.text) ?? 0) >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 112,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.end,
                onChanged: onTextChanged,
                decoration: InputDecoration(
                  labelText: '并发数',
                  errorText: valid ? null : '至少为 1',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            year2023: false,
            trackHeight: 24,
            trackGap: 8,
            activeTrackColor: scheme.primary,
            inactiveTrackColor: scheme.primaryContainer,
            thumbColor: scheme.primary,
            overlayColor: scheme.primary.withValues(alpha: .12),
          ),
          child: Slider(
            value: math.min(value.toDouble(), baselineMax),
            min: 1,
            max: baselineMax,
            label: '$value',
            onChanged: onSliderChanged,
          ),
        ),
      ],
    );
  }
}

String _shizukuStatusLabel(ShizukuStatus status, bool enabled) =>
    switch (status) {
      ShizukuStatus.authorized =>
        enabled ? '已授权；点击安装后将通过 Shizuku 安装 APK' : '已授权，打开后通过 Shizuku 安装 APK',
      ShizukuStatus.unavailable =>
        enabled ? 'Shizuku 未运行，安装前请先启动服务' : '请先启动 Shizuku，再打开此选项',
      ShizukuStatus.denied => 'Shizuku 未授予 APK Mesh 权限',
      ShizukuStatus.unsupported => '当前平台不支持 Shizuku 安装',
    };

class _ShizukuInstallationSettingsPanel extends StatefulWidget {
  const _ShizukuInstallationSettingsPanel({required this.state});

  final AppState state;

  @override
  State<_ShizukuInstallationSettingsPanel> createState() =>
      _ShizukuInstallationSettingsPanelState();
}

class _ShizukuInstallationSettingsPanelState
    extends State<_ShizukuInstallationSettingsPanel> {
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.state.refreshShizukuStatus());
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _changing = true);
    try {
      final changed = await widget.state.setUseShizukuInstaller(enabled);
      if (!changed && mounted) {
        final message = _shizukuStatusLabel(widget.state.shizukuStatus, false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Shizuku 授权失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    secondary: const Icon(Icons.admin_panel_settings_outlined),
    title: const Text('使用 Shizuku 安装'),
    subtitle: Text(
      _shizukuStatusLabel(
        widget.state.shizukuStatus,
        widget.state.useShizukuInstaller,
      ),
    ),
    value: widget.state.useShizukuInstaller,
    onChanged: _changing ? null : _setEnabled,
  );
}

class TranslationSettingsPanel extends StatefulWidget {
  const TranslationSettingsPanel({required this.state, super.key});

  final AppState state;

  @override
  State<TranslationSettingsPanel> createState() =>
      _TranslationSettingsPanelState();
}

class _TranslationSettingsPanelState extends State<TranslationSettingsPanel> {
  late final TextEditingController _googleKeyController;

  @override
  void initState() {
    super.initState();
    _googleKeyController = TextEditingController(
      text: widget.state.translationSettings.googlePublicKey,
    );
  }

  @override
  void didUpdateWidget(covariant TranslationSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = widget.state.translationSettings.googlePublicKey;
    if (_googleKeyController.text != key) {
      _googleKeyController.text = key;
    }
  }

  @override
  void dispose() {
    _googleKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.state.translationSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.translate_outlined),
          title: const Text('翻译'),
          subtitle: Text(
            '${settings.provider.label} · ${translationLanguageLabel(settings.targetLanguage)}',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动翻译应用名称和简介'),
          subtitle: const Text('搜索结果和详情加载后自动请求翻译'),
          value: settings.autoTranslate,
          onChanged: widget.state.setAutoTranslate,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('翻译服务'),
          trailing: DropdownButton<TranslationProvider>(
            value: settings.provider,
            onChanged: (value) {
              if (value != null) widget.state.setTranslationProvider(value);
            },
            items: [
              for (final provider in TranslationProvider.values)
                DropdownMenuItem(value: provider, child: Text(provider.label)),
            ],
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('目标语言'),
          trailing: DropdownButton<String>(
            value: settings.targetLanguage,
            onChanged: (value) {
              if (value != null) widget.state.setTranslationLanguage(value);
            },
            items: [
              for (final language in const [
                'system',
                'zh-CN',
                'zh-TW',
                'en',
                'ja',
                'ko',
                'es',
                'fr',
                'de',
                'pt',
              ])
                DropdownMenuItem(
                  value: language,
                  child: Text(translationLanguageLabel(language)),
                ),
            ],
          ),
        ),
        if (settings.provider == TranslationProvider.google)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _googleKeyController,
              obscureText: true,
              onEditingComplete: () =>
                  widget.state.setGooglePublicKey(_googleKeyController.text),
              onSubmitted: widget.state.setGooglePublicKey,
              decoration: const InputDecoration(
                labelText: 'Google 公共 API Key（可选）',
                helperText: '留空时使用 Google Translate 浏览器旧接口。',
              ),
            ),
          ),
        Text(
          '翻译文本会发送到所选服务商或其网关。接口不稳定或请求失败时保留原文。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
