# APK Mesh Source Debugger

独立的 Python 源调试器，用于在不安装 Android 应用、不连接 Android 设备的情况下执行 APK Mesh JavaScript 源。

它实现了当前 Source API 的主要宿主能力：

- QuickJS 执行源脚本；
- `apkmesh.request()` 和手动白名单重定向；
- Playwright 无头 Chromium 作为浏览器宿主；
- `waitFor`、`query`、`queryAll` 的 CSS/属性查询契约；
- 独立目录保存下载文件；
- `install()` 明确报告 Android 能力不可用；
- live 请求、录制和完全离线的精确 URL fixture 回放；
- 请求、响应、浏览器导航、选择器和异常 trace。

## 初始化

需要 Python 3.12+ 和已经安装的 `uv`：

```bash
cd tools/source_debugger
uv sync
uv run playwright install chromium
```

`playwright install chromium` 只需要执行一次，用于下载 Playwright 自己管理的浏览器。它不需要 Android SDK 或 Android 设备。

选项要放在源文件路径之前；例如 `--json`、`--mode replay` 和 `--trace`。


```bash
uv run apkmesh-debug [选项] SOURCE [操作参数]
```

查看源 manifest：

```bash
uv run apkmesh-debug ../../assets/sources/apkvision.js inspect
```

在线搜索（live 模式是默认值）：

```bash
uv run apkmesh-debug --mode live --trace traces/search.json ../../assets/sources/apkvision.js search minecraft
```

录制 HTTP 响应和浏览器最终 DOM 页面快照，生成可离线回放的目录：

```bash
uv run apkmesh-debug --mode record --record-dir fixtures/apkvision \
  ../../assets/sources/apkvision.js search minecraft
```

在线读取详情：

```bash
uv run apkmesh-debug ../../assets/sources/apkvision.js details \
  https://apkvision.org/games/arcade/minecraft-pe-apk-55409/
```

运行源声明的调试项目：

```bash
uv run apkmesh-debug ../../assets/sources/apkvision.js debug \
  search-keyword minecraft
```

机器可读输出：

```bash
uv run apkmesh-debug --json ../../assets/sources/apkvision.js search minecraft
```

## 离线回放

回放目录包含一个 `replay.json`，响应可以直接写入 `body`，也可以通过 `body_file` 引用文件：

```json
{
  "responses": {
    "GET https://example.test/?s=demo": {
      "status": 200,
      "headers": {"content-type": "text/html; charset=utf-8"},
      "body_file": "search-demo.html"
    }
  }
}
```

执行回放时，未登记的 URL 会失败，不会访问网络：

```bash
uv run apkmesh-debug --mode replay --fixture-dir fixtures/example \
  ../../assets/sources/example.js search demo
```

当前 APKVision 源的离线详情测试通常需要登记搜索页、详情页和下载解析页。浏览器页面的子资源也必须登记；如果详情 fixture 本身已经包含所需 DOM，则只登记主文档即可。

## 测试

```bash
uv run pytest
```

默认情况下不会自动创建 fixture。需要完全断网执行时，必须显式使用 `--mode replay`；回放中未登记的 URL 会失败，不会访问网络。正式调试第三方源前，应确认自己有权访问相关站点，并遵守站点条款。
