/** APKTodo metadata source for APK Mesh's QuickJS contract. */
const ORIGIN = 'https://apktodo.io';
const SEARCH_HEADERS = {
  Accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.8',
  Referer: `${ORIGIN}/`,
  'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36',
};

function decodeHtml(value) {
  return String(value || '')
    .replace(/&#x([0-9a-f]+);?/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);?/g, (_, decimal) => String.fromCodePoint(parseInt(decimal, 10)))
    .replace(/&(amp|lt|gt|quot|apos|nbsp);/gi, (_, entity) => ({
      amp: '&',
      lt: '<',
      gt: '>',
      quot: '"',
      apos: "'",
      nbsp: ' ',
    })[entity.toLowerCase()]);
}

function cleanText(value) {
  return decodeHtml(String(value || '').replace(/\s+/g, ' ')).trim();
}

function textFromHtml(value) {
  return cleanText(String(value || '')
    .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' '));
}

function attribute(tag, name) {
  const escapedName = String(name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`\\b${escapedName}\\s*=\\s*(['"])([\\s\\S]*?)\\1`, 'i').exec(tag || '');
  return match ? decodeHtml(match[2]).trim() : '';
}

function absoluteUrl(url) {
  const value = cleanText(url);
  if (value.startsWith('//')) return `https:${value}`;
  if (value.startsWith('/')) return `${ORIGIN}${value}`;
  return value;
}

function isApkTodoUrl(url) {
  return /^https:\/\/(?:apktodo\.io|[^/.]+\.apktodo\.io)\//i.test(`${url}/`);
}

function imageUrl(block) {
  const imageMatch = /<img\b[^>]*>/i.exec(block || '');
  if (!imageMatch) return '';
  for (const name of ['data-src', 'data-lazy-src', 'data-original', 'src']) {
    const value = attribute(imageMatch[0], name);
    if (value && !/no-image/i.test(value)) return absoluteUrl(value);
  }
  return '';
}

function extractVersion(value) {
  const match = /\bv?\d+(?:\.\d+)+(?:[A-Za-z][\w.-]*)?/i.exec(cleanText(value));
  return match ? match[0] : '';
}

function extractSize(value) {
  const match = /\b\d+(?:\.\d+)?\s*(?:KB|MB|GB)\b/i.exec(cleanText(value));
  return match ? match[0] : '';
}

function parseSearchResults(html) {
  const entries = [];
  const pattern = /<a\b([^>]*\bclass\s*=\s*['"][^'"]*\bblog\b[^'"]*\bsearch\b[^'"]*['"][^>]*)>([\s\S]*?)<\/a>\s*<\/li>/gi;
  for (const match of html.matchAll(pattern)) {
    const openingTag = `<a${match[1]}>`;
    const id = absoluteUrl(attribute(openingTag, 'href'));
    if (!isApkTodoUrl(id)) continue;
    const block = match[2];
    const titleMatch = /<div\b[^>]*\bclass\s*=\s*['"][^'"]*\btitle\b[^'"]*['"][^>]*>([\s\S]*?)<\/div>/i.exec(block);
    const timeMatch = /<time\b[^>]*>/i.exec(block);
    const name = cleanText(titleMatch ? titleMatch[1] : attribute(openingTag, 'title'));
    if (!name) continue;
    entries.push({
      id,
      name,
      packageName: '',
      version: '',
      size: '',
      updatedAt: timeMatch ? attribute(timeMatch[0], 'datetime') : '',
      category: '',
      iconUrl: imageUrl(block),
      summary: '来自 APKTodo 搜索结果',
    });
  }
  return entries;
}

function parseGridResults(html) {
  const entries = [];
  const pattern = /<a\b([^>]*\bclass\s*=\s*['"][^'"]*\bapk_new\b[^'"]*['"][^>]*)>([\s\S]*?)<\/a>\s*<\/li>/gi;
  for (const match of html.matchAll(pattern)) {
    const openingTag = `<a${match[1]}>`;
    const id = absoluteUrl(attribute(openingTag, 'href'));
    if (!isApkTodoUrl(id)) continue;
    const block = match[2];
    const titleMatch = /<h3\b[^>]*\bclass\s*=\s*['"][^'"]*\btitle\b[^'"]*['"][^>]*>([\s\S]*?)<\/h3>/i.exec(block);
    const categoryMatch = /<div\b[^>]*\bclass\s*=\s*['"][^'"]*\bcategory\b[^'"]*['"][^>]*>([\s\S]*?)<\/div>/i.exec(block);
    const metaMatch = /<div\b[^>]*\bclass\s*=\s*['"][^'"]*\bmeta\b[^'"]*['"][^>]*>([\s\S]*?)<\/div>/i.exec(block);
    const versionMatch = /<span\b[^>]*\bclass\s*=\s*['"][^'"]*\btext_meta\b[^'"]*['"][^>]*>([\s\S]*?)<\/span>/i.exec(block);
    const meta = metaMatch ? textFromHtml(metaMatch[1]) : '';
    const name = cleanText(titleMatch ? titleMatch[1] : attribute(openingTag, 'title'));
    if (!name) continue;
    entries.push({
      id,
      name,
      packageName: '',
      version: extractVersion(versionMatch ? versionMatch[1] : meta),
      size: extractSize(meta),
      updatedAt: '',
      category: cleanText(categoryMatch ? categoryMatch[1] : ''),
      iconUrl: imageUrl(block),
      summary: '来自 APKTodo 目录',
    });
  }
  return entries;
}

function parseIconResults(html) {
  const entries = [];
  const pattern = /<a\b([^>]*\bclass\s*=\s*['"][^'"]*\bapk-icon\b[^'"]*['"][^>]*)>([\s\S]*?)<\/a>\s*<\/li>/gi;
  for (const match of html.matchAll(pattern)) {
    const openingTag = `<a${match[1]}>`;
    const id = absoluteUrl(attribute(openingTag, 'href'));
    if (!isApkTodoUrl(id)) continue;
    const block = match[2];
    const titleMatch = /<p\b[^>]*\bclass\s*=\s*['"][^'"]*\btitle\b[^'"]*['"][^>]*>([\s\S]*?)<\/p>/i.exec(block);
    const categoryMatch = /<p\b[^>]*\bclass\s*=\s*['"][^'"]*\bcate\b[^'"]*['"][^>]*>([\s\S]*?)<\/p>/i.exec(block);
    const versionMatch = /<div\b[^>]*\bclass\s*=\s*['"][^'"]*\bctVersion\b[^'"]*['"][^>]*>[\s\S]*?<p\b[^>]*>([\s\S]*?)<\/p>/i.exec(block);
    const sizeMatch = /<div\b[^>]*\bclass\s*=\s*['"][^'"]*\bctSize\b[^'"]*['"][^>]*>[\s\S]*?<p\b[^>]*>([\s\S]*?)<\/p>/i.exec(block);
    const name = cleanText(titleMatch ? titleMatch[1] : attribute(openingTag, 'title'));
    if (!name) continue;
    entries.push({
      id,
      name,
      packageName: '',
      version: extractVersion(versionMatch ? versionMatch[1] : ''),
      size: extractSize(sizeMatch ? sizeMatch[1] : ''),
      updatedAt: '',
      category: cleanText(categoryMatch ? categoryMatch[1] : ''),
      iconUrl: imageUrl(block),
      summary: '来自 APKTodo 分类目录',
    });
  }
  return entries;
}

function rowField(rows, label) {
  const expected = cleanText(label).toLowerCase();
  const row = rows.find((item) => cleanText(item.label).toLowerCase() === expected);
  return row ? cleanText(row.value) : '';
}

function searchUrl(query, page) {
  const number = Math.max(1, Number(page) || 1);
  const suffix = number > 1 ? `&page=${number}` : '';
  return `${ORIGIN}/?s=${encodeURIComponent(query)}${suffix}`;
}

async function fetchText(url) {
  return apkmesh.request(url, {headers: SEARCH_HEADERS});
}

function parseStructuredData(nodes) {
  for (const node of nodes || []) {
    try {
      const value = JSON.parse(cleanText(node.text));
      if (value && (value['@type'] === 'MobileApplication' || value['@type'] === 'SoftwareApplication')) {
        return value;
      }
    } catch (_) {
      // A page can contain unrelated or malformed JSON-LD blocks.
    }
  }
  return {};
}

function uniqueStrings(values) {
  return values.filter((value, index, all) => value && all.indexOf(value) === index);
}

const CATEGORIES = [
  {id: `${ORIGIN}/games/`, name: 'Games', description: 'Android 游戏'},
  {id: `${ORIGIN}/apps/`, name: 'Apps', description: 'Android 应用'},
];

globalThis.source = {
  manifest: {
    id: 'apktodo',
    name: 'APKTodo（元数据测试源）',
    version: '1.0.0',
    minApiVersion: 1,
    homepage: `${ORIGIN}/`,
    description: '读取 APKTodo 应用元数据、截图和详情页地址，不自动下载第三方中转文件。',
    permissions: {
      network: ['apktodo.io', '*.apktodo.io'],
      browser: true,
      download: false,
      install: false,
    },
    debugProjects: [
      {
        id: 'search-keyword',
        name: '搜索关键词',
        description: '读取 APKTodo 搜索结果并检查子域名详情地址。',
        inputLabel: '关键词',
        placeholder: '例如 hello',
        defaultInput: 'hello',
      },
      {
        id: 'app-details',
        name: '获取应用详情',
        description: '打开 APKTodo 子域名详情页，读取元数据、截图和下载页地址。',
        inputLabel: '应用详情 URL',
        placeholder: '粘贴源详情页 URL',
        defaultInput: 'https://hello-neighbor-fredbear.apktodo.io/',
      },
      {
        id: 'catalog',
        name: '检查主页与分类',
        description: '调用源主页和分类实现，汇总每个分类返回的应用数量。',
        inputLabel: '分类数量上限',
        placeholder: '0 表示全部',
        defaultInput: '0',
      },
    ],
  },

  async home() {
    const html = await fetchText(`${ORIGIN}/`);
    return {
      recommended: parseGridResults(html).slice(0, 24),
      categories: CATEGORIES,
    };
  },

  async search(query, page = 1) {
    const normalized = cleanText(query);
    if (normalized.length < 2) throw new TypeError('搜索关键词至少需要 2 个字符');
    return parseSearchResults(await fetchText(searchUrl(normalized, page)));
  },

  async category(categoryId) {
    const id = absoluteUrl(categoryId).replace(/\/+$/, '') + '/';
    const match = new RegExp(`^${ORIGIN}/(games|apps)/$`, 'i').exec(id);
    if (!match) throw new TypeError('无效的分类地址');
    const html = await fetchText(id);
    return {
      id,
      name: match[1].toLowerCase() === 'games' ? 'Games' : 'Apps',
      apps: parseIconResults(html),
    };
  },

  async details(url) {
    const id = absoluteUrl(url);
    if (!isApkTodoUrl(id)) throw new TypeError('无效的 APKTodo 详情地址');

    const openUrl = /\/$/.test(id) ? id : `${id}/`;
    const tab = await apkmesh.browser.open(openUrl);
    try {
      await tab.waitFor('.page_single_new');
      const app = await tab.query({
        id: 'link[rel="canonical"]@href',
        name: '.page_single_new .thumb_title h1.title@text',
        category: '.page_single_new .thumb_title .cate@text',
        iconUrl: '.page_single_new .thumb_title img@data-src',
        summary: 'meta[name="description"]@content',
        downloadPage: '.page_single_new .btn_download a@href',
      });
      const rows = await tab.queryAll('.table_info tr', {
        label: 'th@text',
        value: 'td@text',
      });
      const structured = parseStructuredData(await tab.queryAll('script[type="application/ld+json"]', {text: '@text'}));
      const screenshotNodes = await tab.queryAll('.apk-slider-holder img.ss-item', {
        src: '@src',
        dataSrc: '@data-src',
      });
      const commentNodes = await tab.queryAll('.comment-content, .comment-body', {text: '@text'});
      const screenshots = screenshotNodes.map((item) => absoluteUrl(item.dataSrc || item.src || ''));
      const structuredScreenshots = Array.isArray(structured.screenshot)
        ? structured.screenshot.map((item) => typeof item === 'string' ? item : item && item.url)
        : structured.screenshot && Array.isArray(structured.screenshot.url)
          ? structured.screenshot.url
          : structured.screenshot && structured.screenshot.url
            ? [structured.screenshot.url]
            : [];

      app.id = absoluteUrl(app.id || id);
      app.name = rowField(rows, 'Name') || cleanText(app.name || structured.name || '');
      app.name = app.name.replace(/\s+APK(?:\s+v?\d[\w.-]*)?\s*$/i, '').trim();
      app.packageName = '';
      app.version = rowField(rows, 'Last version') || cleanText(structured.softwareVersion || '');
      app.size = rowField(rows, 'Size') || cleanText(structured.fileSize || '');
      app.updatedAt = rowField(rows, 'Updated') || cleanText(structured.dateModified || structured.datePublished || '');
      app.category = rowField(rows, 'Category') || cleanText(app.category || structured.applicationSubCategory || structured.applicationCategory || '');
      app.iconUrl = absoluteUrl(app.iconUrl || structured.thumbnailUrl || structured.image || '');
      app.summary = cleanText(app.summary || structured.description || '');
      const descriptionResult = await tab.query({description: '.apk_content@text'});
      app.description = cleanText(descriptionResult.description || '');
      app.screenshots = uniqueStrings(screenshots.concat(structuredScreenshots.map(absoluteUrl)));
      app.comments = uniqueStrings(commentNodes.map((item) => cleanText(item.text)));
      // The site's /prepare -> apktodo.net -> files.apktodo.store chain is not exposed as a download.
      app.downloads = [];
      app.downloadPage = absoluteUrl(app.downloadPage || '');
      app.downloadNote = app.downloadPage
        ? '下载页需要人工核验，当前源不会自动下载第三方中转文件。'
        : '';
      return app;
    } finally {
      await tab.close();
    }
  },

  async debug(projectId, input) {
    const value = cleanText(input);
    if (projectId === 'search-keyword') {
      const results = await this.search(value);
      return {
        title: '搜索完成',
        summary: `关键词“${value}”返回 ${results.length} 条结果`,
        data: results.map((item) => ({
          name: item.name,
          id: item.id,
          updatedAt: item.updatedAt,
          iconUrl: item.iconUrl,
        })),
      };
    }
    if (projectId === 'app-details') {
      const app = await this.details(value);
      return {
        title: '详情读取完成',
        summary: `已读取 ${app.name}；下载项 ${app.downloads.length} 个（已禁用不可信中转）`,
        data: {
          name: app.name,
          version: app.version,
          size: app.size,
          category: app.category,
          updatedAt: app.updatedAt,
          screenshots: app.screenshots.length,
          downloadPage: app.downloadPage,
          downloads: app.downloads.length,
        },
      };
    }
    if (projectId === 'catalog') {
      const home = await this.home();
      const limit = Math.max(0, Number(value) || 0);
      const selected = limit > 0 ? home.categories.slice(0, limit) : home.categories;
      const categories = [];
      for (const category of selected) {
        const result = await this.category(category.id);
        categories.push({id: result.id, name: result.name, apps: result.apps.length});
      }
      return {
        title: '主页与分类检查完成',
        summary: `推荐应用 ${home.recommended.length} 个；检查分类 ${categories.length} 个`,
        data: {
          recommended: home.recommended.length,
          categories,
        },
      };
    }
    throw new Error(`未知调试项目：${projectId}`);
  },
};
