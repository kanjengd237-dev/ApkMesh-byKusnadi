import 'package:flutter/material.dart';

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
