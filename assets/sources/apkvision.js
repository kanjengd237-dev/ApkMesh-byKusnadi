/** APKVision development source for APK Mesh's QuickJS contract. */
const ORIGIN = 'https://apkvision.org';
const SEARCH_PATH = '/?s=';
const SEARCH_HEADERS = {
  Accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.8',
  Referer: `${ORIGIN}/`,
  'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36',
};
const ACRONYMS = new Set(['apk', 'api', 'fps', 'gta', 'hd', 'mcpe', 'mod', 'nba', 'pe', 'psp', 'rpg', 'vr', 'xapk']);

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

function absoluteUrl(url) {
  const value = cleanText(url);
  if (value.startsWith('//')) return `https:${value}`;
  if (value.startsWith('/')) return `${ORIGIN}${value}`;
  return value;
}

function isApkVisionUrl(url) {
  return /^https:\/\/(?:[^/]+\.)?apkvision\.org\//i.test(url);
}

function humanize(value) {
  return String(value || '').split('-').filter(Boolean).map((word) => {
    const lower = word.toLowerCase();
    if (ACRONYMS.has(lower)) return lower.toUpperCase();
    return lower[0].toUpperCase() + lower.slice(1);
  }).join(' ');
}

function stripApkSuffix(title) {
  return cleanText(title)
    .replace(/\s+APK(?:\s*[+:-].*)?$/i, '')
    .replace(/\s+-\s+Download Free for Android.*$/i, '')
    .trim();
}

function extractVersion(value) {
  const match = /\bv?\d+(?:\.\d+)+(?:\s+[A-Za-z][\w-]*)?/i.exec(cleanText(value));
  return match ? match[0] : '';
}

function categoryFromUrl(url) {
  const parts = url.replace(/^https:\/\/[^/]+\//i, '').split('/').filter(Boolean);
  return parts.length > 1 ? humanize(parts[parts.length - 2]) : '';
}

function searchUrl(query, page) {
  const number = Math.max(1, Number(page) || 1);
  const suffix = number > 1 ? `&paged=${number}` : '';
  return `${ORIGIN}${SEARCH_PATH}${encodeURIComponent(query)}${suffix}`;
}

async function fetchText(url) {
  return apkmesh.request(url, {headers: SEARCH_HEADERS});
}

function parseSearchResults(html) {
  const entries = [];
  const resultPattern = /<a\b([^>]*\bclass\s*=\s*["'][^"']*\bmain-news\b[^"']*["'][^>]*)>([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(resultPattern)) {
    const openingTag = `<a${match[1]}>`;
    const id = absoluteUrl(attribute(openingTag, 'href'));
    if (!isApkVisionUrl(id)) continue;

    const block = match[2];
    const titleMatch = /<div\b[^>]*\bclass\s*=\s*["'][^"']*\bmain-news-title\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i.exec(block);
    const versionMatch = /<div\b[^>]*\bclass\s*=\s*["'][^"']*\bmain-news-cat\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i.exec(block);
    const imageMatch = /<img\b[^>]*>/i.exec(block);
    const name = stripApkSuffix(textFromHtml(titleMatch ? titleMatch[1] : ''));
    if (!name) continue;

    entries.push({
      id,
      name,
      packageName: '',
      version: extractVersion(textFromHtml(versionMatch ? versionMatch[1] : '')),
      size: '',
      updatedAt: '',
      category: categoryFromUrl(id),
      iconUrl: imageMatch ? absoluteUrl(attribute(imageMatch[0], 'src')) : '',
      summary: '来自 APKVision 搜索接口',
    });
  }
  return entries;
}

function rowField(rows, label) {
  const expected = cleanText(label).toLowerCase();
  const row = rows.find((item) => cleanText(item.label).toLowerCase() === expected);
  return row ? cleanText(row.value) : '';
}

function extractSize(value) {
  const match = /\b\d+(?:\.\d+)?\s*(?:KB|MB|GB)\b/i.exec(cleanText(value));
  return match ? match[0] : '';
}

function downloadLabel(value) {
  return cleanText(value)
    .replace(/^Download\s+/i, '')
    .replace(/\s+\b\d+(?:\.\d+)?\s*(?:KB|MB|GB)\b\s*$/i, '')
    .trim();
}

function isDirectDownload(url) {
  return /^https:\/\/dl\.apkvision\.org\//i.test(url);
}

async function resolveDownload(url) {
  if (isDirectDownload(url)) return url;
  if (!/^https:\/\/apkvision\.org\/[^?#]+\/download\//i.test(url)) return null;

  const html = await fetchText(url);
  const linkMatch = /<a\b[^>]*\bid\s*=\s*["']durl["'][^>]*>/i.exec(html);
  if (!linkMatch) return null;
  const direct = absoluteUrl(attribute(linkMatch[0], 'href'));
  return isDirectDownload(direct) ? direct : null;
}

async function mapLimit(items, limit, mapper) {
  const results = new Array(items.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      results[currentIndex] = await mapper(items[currentIndex], currentIndex);
    }
  }
  await Promise.all(Array.from({length: Math.min(limit, items.length)}, worker));
  return results;
}

globalThis.source = {
  manifest: {
    id: 'apkvision-demo',
    name: 'APKVision（测试源）',
    version: '1.0.0',
    minApiVersion: 1,
    homepage: `${ORIGIN}/`,
    permissions: {
      network: ['apkvision.org', '*.apkvision.org'],
      browser: true,
      download: true,
      install: true,
    },
  },

  async search(query, page = 1) {
    const normalized = cleanText(query);
    if (normalized.length < 2) throw new TypeError('搜索关键词至少需要 2 个字符');
    return parseSearchResults(await fetchText(searchUrl(normalized, page)));
  },

  async details(url) {
    const tab = await apkmesh.browser.open(url);
    try {
      await tab.waitFor('#MobileApplication');
      const app = await tab.query({
        id: 'link[rel="canonical"]@href',
        name: '.ver-top-h1 h1@text',
        version: '.ver-top-version@text',
        updatedAt: '.appinfo tr:nth-child(1) td@text',
        category: '.appinfo tr:nth-child(4) td@text',
        iconUrl: '.ver-top-l img@src',
        summary: 'meta[name="description"]@content',
        description: '.body-post > .b-content@text',
      });
      const infoRows = await tab.queryAll('.appinfo tr', {
        label: 'th@text',
        value: 'td@text',
      });
      app.id = absoluteUrl(app.id || url);
      app.name = stripApkSuffix(app.name || '');
      app.version = cleanText(app.version);
      app.updatedAt = rowField(infoRows, 'Updated') || cleanText(app.updatedAt);
      app.category = rowField(infoRows, 'Genre') || cleanText(app.category);
      app.iconUrl = absoluteUrl(app.iconUrl || '');
      app.summary = cleanText(app.summary);
      app.description = cleanText(app.description);
      app.packageName = rowField(infoRows, 'Package name');

      const screenshotNodes = await tab.queryAll('.app_screens_list img', {url: '@src'});
      app.screenshots = screenshotNodes.map((item) => absoluteUrl(item.url)).filter(Boolean);

      const commentNodes = await tab.queryAll('.comment-content, .comment-body', {text: '@text'});
      app.comments = commentNodes.map((item) => cleanText(item.text)).filter(Boolean);

      const downloadNodes = await tab.queryAll('.b-dwn-spoiler__links a.fdl-btn', {
        label: '.fdl-btn-title@text',
        url: '@href',
      });
      const candidates = downloadNodes.map((item) => ({
        label: downloadLabel(item.label),
        url: absoluteUrl(item.url),
        size: extractSize(item.label),
      })).filter((item) => item.label && isApkVisionUrl(item.url)).slice(0, 20);
      const resolved = await mapLimit(candidates, 4, async (item) => {
        try {
          const direct = await resolveDownload(item.url);
          return direct ? {...item, url: direct} : null;
        } catch (_) {
          return null;
        }
      });
      app.downloads = resolved.filter(Boolean).filter((item, index, all) =>
        all.findIndex((candidate) => candidate.url === item.url) === index,
      );
      return app;
    } finally {
      await tab.close();
    }
  },
};
