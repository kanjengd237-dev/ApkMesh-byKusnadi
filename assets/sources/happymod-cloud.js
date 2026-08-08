/** HappyMod.cloud source for APK Mesh's QuickJS contract. */
const ORIGIN = 'https://www.happymod.cloud';
const SEARCH_URL = `${ORIGIN}/search.html`;
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
  const match = new RegExp(`\\b${escapedName}\\s*=\\s*(["'])([\\s\\S]*?)\\1`, 'i').exec(tag || '');
  return match ? decodeHtml(match[2]).trim() : '';
}

function resolveUrl(url, baseUrl = ORIGIN) {
  const value = cleanText(url);
  if (!value) return '';
  if (value.startsWith('//')) return `https:${value}`;
  if (/^https?:\/\//i.test(value)) return value;
  const base = /^https?:\/\/[^/]+/i.exec(baseUrl || '');
  const origin = base ? base[0] : ORIGIN;
  if (value.startsWith('/')) return `${origin}${value}`;
  const directory = String(baseUrl || ORIGIN).replace(/\/[^/]*$/, '');
  return `${directory}/${value}`;
}

function absoluteUrl(url) {
  return resolveUrl(url, ORIGIN);
}

function isHappyModUrl(url) {
  return /^https:\/\/www\.happymod\.cloud\//i.test(`${url}/`);
}

function extractVersion(value) {
  const match = /\bv?\d+(?:\.\d+)+(?:[A-Za-z][\w.-]*)?/i.exec(cleanText(value));
  return match ? match[0].replace(/^v/i, '') : '';
}

function extractSize(value) {
  const match = /\b\d+(?:\.\d+)?\s*(?:KB|MB|GB)\b/i.exec(cleanText(value));
  return match ? match[0] : '';
}

function imageUrl(block, baseUrl = ORIGIN) {
  const imageMatch = /<img\b[^>]*>/i.exec(block || '');
  if (!imageMatch) return '';
  for (const name of ['data-src', 'data-lazy-src', 'data-original', 'src']) {
    const value = attribute(imageMatch[0], name);
    if (value && !/^data:/i.test(value)) return resolveUrl(value, baseUrl);
  }
  return '';
}

function packageFromUrl(url) {
  const match = /\/([^/?#]+)\/?(?:[?#].*)?$/i.exec(url || '');
  return match ? match[1] : '';
}

function uniqueStrings(values) {
  return values.filter((value, index, all) => value && all.indexOf(value) === index);
}

function parseSearchResults(html) {
  const entries = [];
  const pattern = /<a\b([^>]*\bclass\s*=\s*["'][^"']*\blist-box\b[^"']*["'][^>]*)>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const openingTag = `<a${match[1]}>`;
    const id = absoluteUrl(attribute(openingTag, 'href'));
    if (!isHappyModUrl(id)) continue;

    const block = match[2];
    const titleMatch = /<div\b[^>]*\bclass\s*=\s*["'][^"']*\blist-info-title\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i.exec(block);
    const metadata = [...block.matchAll(/<div\b[^>]*\bclass\s*=\s*["'][^"']*\blist-info-text\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/gi)]
      .map((item) => textFromHtml(item[1]));
    const name = cleanText(titleMatch ? titleMatch[1] : attribute(openingTag, 'title'));
    if (!name) continue;

    entries.push({
      id,
      name,
      packageName: packageFromUrl(id),
      version: extractVersion(metadata[0] || ''),
      size: extractSize(metadata[0] || ''),
      updatedAt: '',
      category: '',
      iconUrl: imageUrl(block),
      description: cleanText(metadata[1] || ''),
    });
  }
  return entries;
}

function searchUrl(query) {
  return `${SEARCH_URL}?q=${encodeURIComponent(query)}`;
}

async function fetchText(url, referer = `${ORIGIN}/`) {
  return apkmesh.request(url, {
    headers: {...SEARCH_HEADERS, Referer: referer},
  });
}

function isNotFoundError(error) {
  const message = error && error.message ? error.message : String(error || '');
  return /\bHTTP\s+404\b/i.test(message) ||
    /\bstatus(?:\s+code)?\s*[:=]?\s*404\b/i.test(message);
}

function rowValue(html, label) {
  const pattern = new RegExp(
    `<dt\\b[^>]*class\\s*=\\s*["'][^"']*\\badditional-title\\b[^"']*["'][^>]*>\\s*[\\s\\S]*?${label}[\\s\\S]*?<\\/dt>\\s*<dd\\b[^>]*class\\s*=\\s*["'][^"']*\\badditional-info\\b[^"']*["'][^>]*>([\\s\\S]*?)<\\/dd>`,
    'i',
  );
  const match = pattern.exec(html || '');
  return match ? textFromHtml(match[1]) : '';
}

function parseStructuredData(html) {
  for (const match of String(html || '').matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      const value = JSON.parse(match[1].trim());
      const nodes = value && Array.isArray(value['@graph']) ? value['@graph'] : [value];
      const app = nodes.find((item) => item && item['@type'] === 'MobileApplication');
      if (app) return app;
    } catch (_) {
      // Ignore unrelated or malformed structured data blocks.
    }
  }
  return {};
}

function parseDescription(html) {
  const section = /<section\b[^>]*\bclass\s*=\s*["'][^"']*\bdescription\b[^"']*["'][^>]*>([\s\S]*?)<\/section>/i.exec(html || '');
  if (!section) return '';
  const paragraph = /<p\b[^>]*>([\s\S]*?)<\/p>/i.exec(section[1]);
  return textFromHtml(paragraph ? paragraph[1] : section[1]);
}

function parseComments(html) {
  const comments = [];
  for (const match of String(html || '').matchAll(/<[^>]*\bclass\s*=\s*["'][^"']*\bcomments-content\b[^"']*["'][^>]*>([\s\S]*?)<\//gi)) {
    const value = textFromHtml(match[1]);
    if (value) comments.push(value);
  }
  return uniqueStrings(comments);
}

function parseDownloadCandidates(html, detailUrl) {
  const candidates = [];
  const pattern = /<a\b([^>]*\bclass\s*=\s*["'][^"']*\bdownload-btn\b[^"']*["'][^>]*)>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const openingTag = `<a${match[1]}>`;
    const url = resolveUrl(attribute(openingTag, 'href'), detailUrl);
    if (!isHappyModUrl(url) || !/\/download\.html$/i.test(url)) continue;
    candidates.push({
      label: 'HappyMod 下载页面',
      url,
      size: extractSize(match[2]),
    });
  }
  return candidates;
}

function downloadLabel(value) {
  return cleanText(value)
    .replace(/^Download\s+/i, '')
    .replace(/\s*\([^)]*\)\s*$/, '')
    .trim() || 'APK';
}

function parseDownloadPageLinks(html, pageUrl) {
  const entries = [];
  const pattern = /<a\b([^>]*\bclass\s*=\s*["'][^"']*\bdownload-border\b[^"']*["'][^>]*)>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const openingTag = `<a${match[1]}>`;
    const url = resolveUrl(attribute(openingTag, 'href'), pageUrl);
    if (!isHappyModUrl(url) || !/(?:downloading|original-downloading)\.html$/i.test(url)) continue;
    const text = textFromHtml(match[2]);
    entries.push({
      label: downloadLabel(text),
      url,
      size: extractSize(text),
    });
  }
  return entries;
}

function parseDirectDownload(html) {
  const match = /\bdlink\s*=\s*["'](https:\/\/[^"']+)["']/i.exec(html || '');
  if (!match || !/^https:\/\/spdn\.poumod\.com\//i.test(match[1])) return '';
  return match[1];
}

function uniqueDownloads(items) {
  return items.filter((item, index, all) =>
    item.url && all.findIndex((candidate) => candidate.url === item.url) === index,
  );
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

globalThis.source = {
  manifest: {
    id: 'happymod-cloud',
    name: 'HappyMod.cloud',
    version: '1.0.0',
    minApiVersion: 1,
    homepage: `${ORIGIN}/`,
    description: '读取 HappyMod.cloud 的应用搜索、详情和 APK 下载项。',
    packageLookup: true,
    permissions: {
      network: ['www.happymod.cloud', 'spdn.poumod.com'],
      browser: false,
      download: true,
      install: true,
    },
    debugProjects: [
      {
        id: 'search-keyword',
        name: '搜索关键词',
        description: '读取 HappyMod.cloud 搜索结果并检查包名和图标。',
        inputLabel: '关键词',
        placeholder: '例如 micro battles',
        defaultInput: 'micro battles',
      },
      {
        id: 'app-details',
        name: '获取应用详情',
        description: '读取详情页、应用描述和可解析的 APK 下载项。',
        inputLabel: '应用详情 URL',
        placeholder: '粘贴 HappyMod.cloud 详情页 URL',
        defaultInput: 'https://www.happymod.cloud/micro-battles/com.donutgames.microbattles/',
      },
    ],
  },

  async search(query, page = 1) {
    const normalized = cleanText(query);
    if (normalized.length < 2) throw new TypeError('搜索关键词至少需要 2 个字符');
    if (Number(page) > 1) return [];
    try {
      return parseSearchResults(await fetchText(searchUrl(normalized)));
    } catch (error) {
      if (isNotFoundError(error)) return [];
      throw error;
    }
  },

  async packageLookupUrl(packageName) {
    const normalized = cleanText(packageName);
    if (!/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$/.test(normalized)) return '';
    const results = await this.search(normalized);
    const match = results.find((item) => item.packageName === normalized);
    return match ? match.id : '';
  },

  async detailsMetadata(url) {
    const id = absoluteUrl(url);
    if (!isHappyModUrl(id)) throw new TypeError('无效的 HappyMod.cloud 详情地址');
    const openUrl = /\/$/.test(id) ? id : `${id}/`;
    const html = await fetchText(openUrl);
    const structured = parseStructuredData(html);
    const canonicalMatch = /<link\b[^>]*\brel\s*=\s*["']canonical["'][^>]*>/i.exec(html);
    const titleMatch = /<h1\b[^>]*class\s*=\s*["'][^"']*\b(?:pdt-info|info-title-wrap)[^"']*["'][^>]*>([\s\S]*?)<\/h1>/i.exec(html);
    const iconMatch = /<figure\b[^>]*class\s*=\s*["'][^"']*\bpdt-icon\b[^"']*["'][^>]*>([\s\S]*?)<\/figure>/i.exec(html);
    const updatedMatch = /<time\b[^>]*class\s*=\s*["'][^"']*\bpdt-info-data\b[^"']*["'][^>]*>([\s\S]*?)<\/time>/i.exec(html);
    const summaryMatch = /<meta\b[^>]*name\s*=\s*["']description["'][^>]*>/i.exec(html);
    const heading = cleanText(titleMatch ? titleMatch[1] : structured.name || '');
    const name = heading
      .replace(/\s+v?\d+(?:\.\d+)+[\w.-]*.*$/i, '')
      .replace(/\s+Mod\s+APK.*$/i, '')
      .trim();
    const packageName = rowValue(html, 'Package Name') ||
      (/store\/apps\/details\?id=([^&"']+)/i.exec(html) || [])[1] || packageFromUrl(openUrl);
    const app = {
      id: absoluteUrl(canonicalMatch ? attribute(canonicalMatch[0], 'href') : openUrl),
      name: name || cleanText(structured.name || 'HappyMod 应用'),
      packageName: cleanText(packageName),
      version: rowValue(html, 'Latest Version') || cleanText(structured.softwareVersion || extractVersion(heading)),
      size: extractSize(/class\s*=\s*["'][^"']*\bdownload-btn\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i.exec(html)?.[1] || '') || cleanText(structured.fileSize || ''),
      updatedAt: cleanText(updatedMatch ? updatedMatch[1] : '') || rowValue(html, 'Updated on') || cleanText(structured.datePublished || ''),
      category: rowValue(html, 'Category'),
      iconUrl: imageUrl(iconMatch ? iconMatch[1] : '') || cleanText(structured.thumbnailUrl || ''),
      summary: cleanText(summaryMatch ? attribute(summaryMatch[0], 'content') : structured.description || ''),
      description: parseDescription(html),
      screenshots: [],
      comments: parseComments(html),
      downloadCandidates: parseDownloadCandidates(html, openUrl),
    };
    return app;
  },

  async resolveDownloads(candidates, requestId) {
    const resolved = [];
    for (let index = 0; index < (candidates || []).length; index += 1) {
      const candidate = candidates[index];
      try {
        const pageHtml = await fetchText(candidate.url, candidate.url);
        const links = parseDownloadPageLinks(pageHtml, candidate.url);
        const pages = links.length ? links : [{label: candidate.label, url: candidate.url, size: candidate.size}];
        const files = [];
        for (const page of pages) {
          const html = page.url === candidate.url ? pageHtml : await fetchText(page.url, page.url);
          const direct = parseDirectDownload(html);
          if (!direct) continue;
          files.push({
            label: page.label,
            url: direct,
            size: page.size || candidate.size,
            headers: {Referer: page.url},
          });
        }
        const downloads = uniqueDownloads(files);
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
          packageName: item.packageName,
          version: item.version,
          size: item.size,
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
          packageName: app.packageName,
          version: app.version,
          size: app.size,
          category: app.category,
          updatedAt: app.updatedAt,
          description: app.description,
          downloads: app.downloads.length,
        },
      };
    }
    throw new Error(`未知调试项目：${projectId}`);
  },
};
