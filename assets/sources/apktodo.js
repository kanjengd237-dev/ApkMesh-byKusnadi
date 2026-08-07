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

function resolveUrl(url, baseUrl) {
  const value = cleanText(url);
  if (!value) return '';
  if (value.startsWith('//')) return `https:${value}`;
  if (/^https?:\/\//i.test(value)) return value;
  const base = /^https?:\/\/[^/]+/i.exec(baseUrl || '');
  const origin = base ? base[0] : ORIGIN;
  return value.startsWith('/') ? `${origin}${value}` : `${origin}/${value}`;
}

function absoluteUrl(url) {
  return resolveUrl(url, ORIGIN);
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

async function fetchText(url, referer = ORIGIN) {
  return apkmesh.request(url, {
    headers: {...SEARCH_HEADERS, Referer: referer},
  });
}

function isNotFoundError(error) {
  const message = error && error.message ? error.message : String(error || '');
  return /\bHTTP\s+404\b/i.test(message) ||
    /\bstatus(?:\s+code)?\s*[:=]?\s*404\b/i.test(message);
}

async function fetchSearchText(url) {
  try {
    return await fetchText(url);
  } catch (error) {
    if (isNotFoundError(error)) return null;
    throw error;
  }
}

function downloadHeaders(referer) {
  return {...SEARCH_HEADERS, Referer: referer};
}

function isApkDownloadUrl(url, label = '') {
  if (/^https:\/\/files\.apktodo\.store\/[^?#]+\.(?:apk|apks|xapk|zip)(?:[?#]|$)/i.test(url)) {
    return true;
  }
  return /^https:\/\/(?:www\.)?apktodo\.net\/download\/mod\/[^?#]+/i.test(url) &&
    /\bAPK\b/i.test(label);
}

function isApkTodoLandingUrl(url) {
  return /^https:\/\/(?:www\.)?apktodo\.net\/(?!download(?:\/|$))[^?#]+\/?$/i.test(url);
}

function downloadLabel(value) {
  return cleanText(value)
    .replace(/^Download\s+/i, '')
    .replace(/\s*\[[^\]]+\]\s*$/, '')
    .trim() || 'APK';
}

function parseDownloadTargets(html, referer) {
  const entries = [];
  function addTarget(openingTag, body) {
    const url = resolveUrl(attribute(openingTag, 'href'), referer);
    if (!url) return;
    const text = textFromHtml(body);
    entries.push({
      label: downloadLabel(text),
      url,
      size: extractSize(text),
      text,
      headers: downloadHeaders(referer),
    });
  }

  const anchorPattern = /<a\b([^>]*\bclass\s*=\s*['"][^'"]*\bitem-apk\b[^'"]*['"][^>]*)>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(anchorPattern)) {
    addTarget(`<a${match[1]}>`, match[2]);
  }

  const containerPattern = /<div\b([^>]*\bclass\s*=\s*['"][^'"]*\bitem-apk\b[^'"]*['"][^>]*)>([\s\S]*?)<\/div>/gi;
  for (const match of html.matchAll(containerPattern)) {
    const anchorMatch = /<a\b([^>]*)>([\s\S]*?)<\/a>/i.exec(match[2]);
    if (anchorMatch) addTarget(`<a${anchorMatch[1]}>`, anchorMatch[2]);
  }
  return entries;
}

function parseDownloadLinks(html, referer) {
  return parseDownloadTargets(html, referer)
      .filter((item) => isApkDownloadUrl(item.url, item.text))
      .map((item) => ({
        label: item.label,
        url: item.url,
        size: item.size,
        headers: item.headers,
      }));
}

function uniqueDownloads(items) {
  return items.filter((item, index, all) =>
    all.findIndex((candidate) => candidate.url === item.url) === index,
  );
}

async function resolveDownloadPage(downloadPage) {
  const prepareHtml = await fetchText(downloadPage, downloadPage);
  const linkMatch = /<div\b[^>]*\bid\s*=\s*['"]download-container['"][^>]*>[\s\S]*?<a\b([^>]*)>/i.exec(prepareHtml);
  if (!linkMatch) return [];
  const downloadTag = `<a${linkMatch[1]}>`;
  const downloadUrl = resolveUrl(attribute(downloadTag, 'href'), downloadPage);
  if (!downloadUrl) return [];

  const downloadHtml = await fetchText(downloadUrl, downloadUrl);
  const downloads = parseDownloadLinks(downloadHtml, downloadUrl);
  const landingTargets = parseDownloadTargets(downloadHtml, downloadUrl)
    .filter((item) => isApkTodoLandingUrl(item.url));

  for (const landing of landingTargets) {
    const landingHtml = await fetchText(landing.url, downloadUrl);
    const landingLink = /<div\b[^>]*\bclass\s*=\s*['"][^'"]*\bbtn_download\b[^'"]*['"][^>]*>[\s\S]*?<a\b([^>]*)>/i.exec(landingHtml);
    if (!landingLink) continue;
    const landingTag = `<a${landingLink[1]}>`;
    const landingDownloadUrl = resolveUrl(attribute(landingTag, 'href'), landing.url);
    if (!/^https:\/\/(?:www\.)?apktodo\.net\/download\//i.test(landingDownloadUrl)) continue;
    const landingDownloadHtml = await fetchText(landingDownloadUrl, landing.url);
    downloads.push(...parseDownloadLinks(landingDownloadHtml, landingDownloadUrl));
  }
  return uniqueDownloads(downloads);
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

async function reportDetailProgress(requestId, index, downloads, error) {
  if (!requestId) return;
  try {
    await apkmesh.detailProgress(requestId, {
      index,
      downloads: downloads || [],
      error: error ? String(error) : null,
    });
  } catch (_) {
    // Progress delivery must not abort link resolution.
  }
}

const CATEGORIES = [
  {id: `${ORIGIN}/games/`, name: 'Games', description: 'Android 游戏'},
  {id: `${ORIGIN}/apps/`, name: 'Apps', description: 'Android 应用'},
];

globalThis.source = {
  manifest: {
    id: 'apktodo',
    name: 'APKTodo',
    version: '1.0.0',
    minApiVersion: 1,
    homepage: `${ORIGIN}/`,
    description: '读取 APKTodo 应用元数据、截图、详情和下载项。',
    permissions: {
      network: ['*'],
      browser: true,
      download: true,
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
    const html = await fetchSearchText(searchUrl(normalized, page));
    return html === null ? [] : parseSearchResults(html);
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

  async detailsMetadata(url) {
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
      app.downloadPage = resolveUrl(app.downloadPage || '', openUrl);
      app.downloadCandidates = app.downloadPage
        ? [{label: 'APK 下载链接', url: app.downloadPage, size: ''}]
        : [];
      return app;
    } finally {
      await tab.close();
    }
  },

  async resolveDownloads(candidates, requestId) {
    const resolved = [];
    for (let index = 0; index < (candidates || []).length; index += 1) {
      const candidate = candidates[index];
      try {
        const downloads = await resolveDownloadPage(candidate.url);
        await reportDetailProgress(requestId, index, downloads, null);
        resolved.push(...downloads);
      } catch (error) {
        await reportDetailProgress(requestId, index, [], error);
      }
    }
    return uniqueDownloads(resolved);
  },

  async details(url) {
    const app = await this.detailsMetadata(url);
    app.downloads = await this.resolveDownloads(app.downloadCandidates);
    delete app.downloadCandidates;
    return app;
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
        summary: `已读取 ${app.name}；下载项 ${app.downloads.length} 个`,
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
