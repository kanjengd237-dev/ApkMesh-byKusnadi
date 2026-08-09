import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/translation_service.dart';

const _settingsTilePadding = EdgeInsets.symmetric(horizontal: 16);
const _settingsControlWidth = 152.0;

String _themeModeLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => '跟随系统',
  AppThemeMode.light => '浅色',
  AppThemeMode.dark => '深色',
};

String _downloadMethodLabel(DownloadMethod method) => switch (method) {
  DownloadMethod.internal => '应用内部',
  DownloadMethod.browser => '浏览器',
  DownloadMethod.externalDownloader => '外部下载器',
};

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: _settingsTilePadding,
                  child: Text(
                    '设置',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: _settingsTilePadding,
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('主题'),
                  subtitle: Text(_themeModeLabel(state.themeMode)),
                  trailing: SizedBox(
                    width: _settingsControlWidth,
                    child: DropdownButton<AppThemeMode>(
                      isExpanded: true,
                      value: state.themeMode,
                      onChanged: (value) {
                        if (value != null) state.setThemeMode(value);
                      },
                      items: [
                        for (final mode in AppThemeMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(_themeModeLabel(mode)),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                _DownloadMethodSettingsTile(state: state),
                const Divider(),
                _InformationSettingsTile(
                  icon: Icons.folder_outlined,
                  title: '下载目录',
                  subtitle: '应用内部下载使用系统下载目录',
                  paragraphs: const [
                    '选择“应用内部”时，文件会保存到当前平台提供的下载目录；平台未提供该目录时使用应用文档目录。',
                    '选择浏览器或外部下载器时，保存位置由接收下载链接的应用决定。',
                  ],
                ),
                const Divider(),
                _SourceConcurrencySettingsTile(state: state),
                const Divider(),
                TranslationSettingsPanel(state: state),
                const Divider(),
                ListTile(
                  contentPadding: _settingsTilePadding,
                  leading: const Icon(Icons.security_outlined),
                  title: const Text('安装权限'),
                  subtitle: Text(
                    state.host.supportsInstall
                        ? '安装 APK 前需要允许本应用安装未知来源的应用'
                        : '当前平台不支持 APK 安装',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: state.host.supportsInstall
                      ? state.host.requestInstallPermission
                      : () => _showInformationSheet(
                          context,
                          icon: Icons.security_outlined,
                          title: '安装权限',
                          paragraphs: const [
                            'APK 安装仅在 Android 平台可用。安装操作必须由用户主动确认，并受源权限策略约束。',
                          ],
                        ),
                ),
                if (state.host.supportsShizuku) ...[
                  const Divider(),
                  _ShizukuInstallationSettingsPanel(state: state),
                ],
                const Divider(),
                const _InformationSettingsTile(
                  icon: Icons.policy_outlined,
                  title: '法律与安全',
                  subtitle: '使用第三方源和 APK 文件前请确认授权与可信度',
                  paragraphs: [
                    '请只导入你有权访问和使用的站点源，并遵守对应站点的服务条款与当地法律。',
                    'APK Mesh 不验证第三方下载内容。安装前请核验应用来源、包名、版本和签名，并使用可信的安全工具检查文件。',
                    '源声明的网络、浏览器、下载和安装权限会限制其宿主能力，但不能替代对第三方内容的人工判断。',
                  ],
                ),
                const Divider(),
                const _InformationSettingsTile(
                  icon: Icons.info_outline,
                  title: '关于 APK Mesh',
                  subtitle: '开源 APK 源聚合客户端 · 1.0.0',
                  paragraphs: [
                    'APK Mesh 是一个开源 APK 源聚合客户端。应用通过受权限策略约束的独立源脚本搜索应用、解析详情并获取下载地址。',
                    '版本 1.0.0',
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _DownloadMethodSettingsTile extends StatelessWidget {
  const _DownloadMethodSettingsTile({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: _settingsTilePadding,
    leading: const Icon(Icons.download_for_offline_outlined),
    title: const Text('下载方式'),
    subtitle: Text(_downloadMethodLabel(state.downloadMethod)),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DownloadMethodSheet(state: state),
    ),
  );
}

class _DownloadMethodSheet extends StatelessWidget {
  const _DownloadMethodSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
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
                    '下载方式',
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
            const SizedBox(height: 8),
            RadioGroup<DownloadMethod>(
              groupValue: state.downloadMethod,
              onChanged: (method) {
                if (method == null) return;
                state.setDownloadMethod(method);
                Navigator.pop(context);
              },
              child: Column(
                children: [
                  const RadioListTile<DownloadMethod>(
                    contentPadding: EdgeInsets.zero,
                    value: DownloadMethod.internal,
                    secondary: Icon(Icons.download_outlined),
                    title: Text('应用内部'),
                    subtitle: Text('在 APK Mesh 中下载，可查看进度、暂停、继续和安装'),
                  ),
                  const RadioListTile<DownloadMethod>(
                    contentPadding: EdgeInsets.zero,
                    value: DownloadMethod.browser,
                    secondary: Icon(Icons.open_in_browser_outlined),
                    title: Text('浏览器'),
                    subtitle: Text('使用系统默认浏览器打开下载链接'),
                  ),
                  RadioListTile<DownloadMethod>(
                    contentPadding: EdgeInsets.zero,
                    value: DownloadMethod.externalDownloader,
                    enabled: state.supportsExternalDownloader,
                    secondary: const Icon(Icons.move_to_inbox_outlined),
                    title: const Text('外部下载器'),
                    subtitle: Text(
                      state.supportsExternalDownloader
                          ? '选择 ADM、1DM 等支持下载 Intent 的应用'
                          : '当前平台不支持外部下载器',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InformationSettingsTile extends StatelessWidget {
  const _InformationSettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.paragraphs,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: _settingsTilePadding,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _showInformationSheet(
      context,
      icon: icon,
      title: title,
      paragraphs: paragraphs,
    ),
  );
}

void _showInformationSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<String> paragraphs,
}) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
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
              const SizedBox(height: 16),
              for (var index = 0; index < paragraphs.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                SelectableText(
                  paragraphs[index],
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _SourceConcurrencySettingsTile extends StatelessWidget {
  const _SourceConcurrencySettingsTile({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final settings = state.sourceConcurrency;
    return ListTile(
      contentPadding: _settingsTilePadding,
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
    contentPadding: _settingsTilePadding,
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
          contentPadding: _settingsTilePadding,
          leading: const Icon(Icons.translate_outlined),
          title: const Text('翻译'),
          subtitle: Text(
            '${settings.provider.label} · ${translationLanguageLabel(settings.targetLanguage)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showInformationSheet(
            context,
            icon: Icons.translate_outlined,
            title: '翻译',
            paragraphs: const [
              '启用自动翻译后，应用名称和简介会发送到所选翻译服务。翻译失败时界面保留原文。',
              'Google 公共 API Key 仅保存在本机设置中；留空时使用兼容的浏览器接口。',
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: _settingsTilePadding,
          title: const Text('自动翻译应用名称和简介'),
          subtitle: const Text('搜索结果和详情加载后自动请求翻译'),
          value: settings.autoTranslate,
          onChanged: widget.state.setAutoTranslate,
        ),
        ListTile(
          contentPadding: _settingsTilePadding,
          title: const Text('翻译服务'),
          trailing: SizedBox(
            width: _settingsControlWidth,
            child: DropdownButton<TranslationProvider>(
              isExpanded: true,
              value: settings.provider,
              onChanged: (value) {
                if (value != null) widget.state.setTranslationProvider(value);
              },
              items: [
                for (final provider in TranslationProvider.values)
                  DropdownMenuItem(
                    value: provider,
                    child: Text(provider.label),
                  ),
              ],
            ),
          ),
        ),
        ListTile(
          contentPadding: _settingsTilePadding,
          title: const Text('目标语言'),
          trailing: SizedBox(
            width: _settingsControlWidth,
            child: DropdownButton<String>(
              isExpanded: true,
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
        ),
        if (settings.provider == TranslationProvider.google)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
        Padding(
          padding: _settingsTilePadding,
          child: Text(
            '翻译文本会发送到所选服务商或其网关。接口不稳定或请求失败时保留原文。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
