# APK Mesh Source API v1

源是由 QuickJS 执行的单个 JavaScript 文件。脚本必须设置 `globalThis.source`，其中包含 `manifest`、`search()` 和 `details()`。宿主会验证返回值并在展示前附加源标识。源还可以可选实现 `home()` 和 `category()`，为主页提供推荐应用与分类入口。

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
    debugProjects: [
      {
        id: 'search-keyword',
        name: '搜索关键词',
        description: '调用 search() 并在调试面板中显示请求和结果。',
        inputLabel: '关键词',
        placeholder: '例如 minecraft',
        defaultInput: 'minecraft',
      },
    ],
  },
  async search(query, page) {},
  async details(idOrUrl) {},
};
```

`search()` 返回应用摘要数组。每项包含 `id`、`name`、`packageName`、`version`、`size`、`updatedAt`、`category`、`iconUrl` 和 `summary`。

`details()` 返回完整应用对象，并增加 `description`、`screenshots`、`comments` 和 `downloads`。`downloads` 每项包含 `label`、`url` 和 `size`。`screenshots` 是截图 URL 数组；源应在解析懒加载图片时同时检查 `src`、`data-src` 等属性。

## 可选主页与分类接口

```js
async home() {
  return {
    recommended: await this.search('featured'),
    categories: [
      { id: 'games/action', name: '动作', description: '动作类应用' },
    ],
  };
}

async category(categoryId) {
  return {
    id: categoryId,
    name: '动作',
    apps: [],
  };
}
```

`home()` 返回 `recommended` 推荐应用数组和 `categories` 分类数组。分类至少包含 `id`、`name`，可包含 `description`。用户点击分类时，宿主调用 `category(categoryId)`，返回包含 `id`、`name` 和 `apps` 应用数组的分类对象。`apps` 中的应用字段与 `search()` 返回值相同。

`debugProjects` 是可选的调试项目声明。调试面板会按声明生成输入框和运行按钮，并调用 `debug(projectId, input)`。项目应返回 `{ title, summary, data }`，其中 `data` 会以结构化文本显示在运行结果下方。项目可以复用 `search()`、`details()` 或其他已声明的宿主能力；例如详情项目调用 `apkmesh.browser.open()` 时，面板会同步显示活动 WebView，点击标签即可打开可视化查看器。

```js
async debug(projectId, input) {
  if (projectId === 'search-keyword') {
    const results = await this.search(input);
    return {
      title: '搜索完成',
      summary: `返回 ${results.length} 条结果`,
      data: results,
    };
  }
  throw new Error(`未知调试项目：${projectId}`);
}
```

## 宿主能力

- `apkmesh.request(url, options)`：受域名白名单限制的 HTTP 请求。
- `apkmesh.browser.open(url)`：打开隔离的隐藏 WebView 标签页，支持 `waitFor`、`query` 和 `queryAll`。
- `apkmesh.download(url, options)`：创建受白名单约束的下载任务并返回本地文件路径。
- `apkmesh.install(filePath)`：经用户确认后调用系统安装器；源不能静默安装。Android 会在需要时先打开未知来源安装权限页面。

所有能力均按 manifest 权限授权。网络重定向的每一跳都要重新检查域名；脚本没有任意文件读写、系统命令、Cookie 导出或后台安装权限。生产构建不应内置任何第三方源。
