# APK Mesh

APK Mesh 是一个使用 Flutter 构建的开源 APK 源聚合客户端。源脚本使用 QuickJS 编写，宿主向脚本提供受控的浏览器自动化、网络抓取、下载和安装能力。当前版本包含主页、下载、源管理和设置四个页面；Android 端会自动发现并加载 `assets/sources/` 下的内置源脚本，当前包括 APKVision、APKMirror 和 APKTodo。

## 法律与安全边界

本软件不托管或分发 APK。内置源脚本仅用于展示和开发验证，不代表对相关站点内容的认可。请只启用你有权访问和使用的源，并自行确认应用版权、分发许可、文件签名和安全性。源管理支持从 HTTPS URL 导入 `.js` 源，也支持通过系统文件提供器导入单个 `.js` 或包含多个源脚本的 `.zip`。

源作者不得编写或分发用于解析明显侵权、绕过访问控制、窃取账号或传播恶意软件的网站源。使用者对导入源、搜索结果、下载文件和安装行为承担全部责任；软件作者不对第三方源及其内容承担责任。任何站点的使用都必须遵守当地法律、站点条款和版权方授权。

## 开发

```bash
flutter pub get
flutter run
flutter test
```

QuickJS 宿主桥接位于 `lib/core/source_runtime.dart`，Android 实现位于 `lib/core/quickjs_source_io.dart` 和 `lib/core/host_factory_io.dart`：

- `flutter_js` 在 Android 中运行 QuickJS，并通过异步消息注册 `apkmesh.request`、`apkmesh.browser`、`apkmesh.download` 和 `apkmesh.install`。
- `flutter_inappwebview` 提供隔离的 Headless WebView，所有导航和网络资源按源 manifest 的域名白名单校验。
- 下载使用流式 HTTP，限制重定向必须继续落在白名单内；安装必须由用户点击操作，Android 11+ 会在设置页请求“允许安装未知应用”。Android 上也可在设置中启用 Shizuku，点击安装后通过 Shizuku 执行，并在完成后核对本机安装版本。
- APKVision 源通过站点搜索页获取结果，再用隐藏浏览器解析详情，并从下载页解析受信任的直链。站点改版或 Cloudflare 验证可能导致源暂时不可用。
- Android 端会自动扫描 `assets/sources/` 下的 `.js` 文件，并从每个脚本的 manifest 注册内置源。源管理也支持从 HTTPS URL 或系统文件提供器导入源；ZIP 内的全部 `.js` 文件会逐个尝试导入。

Web 调试目标保留确定性的测试源，原生能力会显示为不可用；这是因为浏览器不能安全地模拟系统安装器和隐藏 WebView。
