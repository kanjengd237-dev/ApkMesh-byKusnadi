# APK Mesh Source API v1

源是由 QuickJS 执行的单个 JavaScript 文件。脚本必须设置 `globalThis.source`，其中包含 `manifest`、`search()` 和 `details()`。宿主会验证返回值并在展示前附加源标识。

## 必需接口

```js
globalThis.source = {
  manifest: {
    id: 'example',
    name: 'Example',
    version: '1.0.0',
    minApiVersion: 1,
    homepage: 'https://example.com',
    permissions: {
      network: ['example.com', '*.example.com'],
      browser: true,
      download: true,
      install: false,
    },
  },
  async search(query, page) {},
  async details(idOrUrl) {},
};
```

`search()` 返回应用摘要数组。每项包含 `id`、`name`、`packageName`、`version`、`size`、`updatedAt`、`category`、`iconUrl` 和 `summary`。

`details()` 返回完整应用对象，并增加 `description`、`screenshots`、`comments` 和 `downloads`。`downloads` 每项包含 `label`、`url` 和 `size`。

## 宿主能力

- `apkmesh.request(url, options)`：受域名白名单限制的 HTTP 请求。
- `apkmesh.browser.open(url)`：打开隔离的隐藏 WebView 标签页，支持 `waitFor`、`query` 和 `queryAll`。
- `apkmesh.download(url, options)`：创建可见下载任务并返回任务 ID。
- `apkmesh.install(taskId)`：经用户确认后调用系统安装器；源不能静默安装。

所有能力均按 manifest 权限授权。网络重定向的每一跳都要重新检查域名；脚本没有任意文件读写、系统命令、Cookie 导出或后台安装权限。生产构建不应内置任何第三方源。
