/** APK Award development source for APK Mesh's QuickJS contract. */
const ORIGIN = 'https://apkaward.com';
const SITEMAP_URL = `${ORIGIN}/sitemap.xml`;
const INDEX_TTL_MS = 6 * 60 * 60 * 1000;
const DETAIL_TTL_MS = 30 * 60 * 1000;
const SITEMAP_CONCURRENCY = 6;
const ACRONYMS = new Set(['apk', 'fps', 'gta', 'hd', 'nba', 'obb', 'psp', 'rpg', 'vr', 'xapk']);
let index;
let indexCachedAt = 0;
let indexPromise;
const titleCache = new Map();

function decodeXml(value) {
  return value.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
}

function cleanText(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function normalizeSearch(value) {
  const text = String(value || '');
  const decomposed = typeof text.normalize === 'function' ? text.normalize('NFKD') : text;
  return cleanText(decomposed)
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function humanize(slug) {
  return slug.split('-').filter(Boolean).map((word) => {
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

function extractSearchTitle(html) {
  const match = /<h1\b[^>]*>([\s\S]*?)<\/h1>/i.exec(html);
  if (!match) return '';
  return stripApkSuffix(decodeXml(match[1].replace(/<[^>]+>/g, ' ')));
}

async function fetchText(url) {
  return apkmesh.request(url, {headers: {
    Accept: 'application/xml,text/xml,text/html;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.8',
    Referer: `${ORIGIN}/`,
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36',
  }});
}

function parseSitemapIndex(xml) {
  return [...xml.matchAll(/<sitemap\b[\s\S]*?<loc>\s*([^<]+?)\s*<\/loc>[\s\S]*?<\/sitemap>/gi)]
    .map((match) => decodeXml(cleanText(match[1])))
    .filter((url) => /^https:\/\/apkaward\.com\/sitemap-pt-post-\d{4}-\d{2}\.xml$/i.test(url));
}

function parseUrlSitemap(xml) {
  const entries = [];
  for (const match of xml.matchAll(/<url\b[\s\S]*?>([\s\S]*?)<\/url>/gi)) {
    const block = match[1];
    const locMatch = /<loc>\s*([^<]+?)\s*<\/loc>/i.exec(block);
    if (!locMatch) continue;
    const loc = decodeXml(cleanText(locMatch[1]));
    const urlMatch = /^https:\/\/apkaward\.com\/([^\/?#]+)\/?$/i.exec(loc);
    if (!urlMatch) continue;

    let slug;
    try {
      slug = decodeURIComponent(urlMatch[1]).toLowerCase();
    } catch (_) {
      continue;
    }
    if (!/^[a-z0-9][a-z0-9-]{0,179}$/.test(slug)) continue;

    const lastmodMatch = /<lastmod>\s*([^<]+?)\s*<\/lastmod>/i.exec(block);
    const lastmod = lastmodMatch ? cleanText(lastmodMatch[1]) : '';
    entries.push({
      slug,
      id: `${ORIGIN}/${slug}`,
      label: humanize(slug),
      lastmod: Number.isNaN(Date.parse(lastmod)) ? null : lastmod,
    });
  }
  return entries;
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

async function buildIndex() {
  const root = await fetchText(SITEMAP_URL);
  const sitemapUrls = parseSitemapIndex(root);
  if (!sitemapUrls.length) throw new Error('APK Award sitemap index is empty');

  let failedSitemaps = 0;
  const groups = await mapLimit(sitemapUrls, SITEMAP_CONCURRENCY, async (url) => {
    try {
      return parseUrlSitemap(await fetchText(url));
    } catch (_) {
      failedSitemaps += 1;
      return [];
    }
  });

  const deduplicated = new Map();
  for (const entry of groups.flat()) {
    const current = deduplicated.get(entry.slug);
    if (!current || Date.parse(entry.lastmod || 0) > Date.parse(current.lastmod || 0)) {
      deduplicated.set(entry.slug, entry);
    }
  }
  const entries = [...deduplicated.values()];
  if (entries.length < 100 || failedSitemaps > sitemapUrls.length / 2) {
    throw new Error('APK Award sitemap index is incomplete');
  }
  entries.sort((left, right) => Date.parse(right.lastmod || 0) - Date.parse(left.lastmod || 0));
  return entries;
}

async function ensureIndex() {
  if (index && Date.now() - indexCachedAt < INDEX_TTL_MS) return index;
  if (!indexPromise) {
    indexPromise = buildIndex().then((entries) => {
      index = entries;
      indexCachedAt = Date.now();
      return entries;
    }).catch((error) => {
      if (index && index.length) return index;
      throw error;
    }).finally(() => {
      indexPromise = null;
    });
  }
  return indexPromise;
}

function diceCoefficient(left, right) {
  if (left === right) return 1;
  if (left.length < 2 || right.length < 2) return 0;
  const pairs = new Map();
  for (let offset = 0; offset < left.length - 1; offset += 1) {
    const pair = left.slice(offset, offset + 2);
    pairs.set(pair, (pairs.get(pair) || 0) + 1);
  }
  let matches = 0;
  for (let offset = 0; offset < right.length - 1; offset += 1) {
    const pair = right.slice(offset, offset + 2);
    const count = pairs.get(pair) || 0;
    if (count > 0) {
      pairs.set(pair, count - 1);
      matches += 1;
    }
  }
  return (2 * matches) / (left.length + right.length - 2);
}

function scoreEntry(entry, rawQuery) {
  const query = normalizeSearch(rawQuery);
  if (!query) return 0;
  const label = normalizeSearch(entry.label);
  const slugText = normalizeSearch(entry.slug);
  const words = [...new Set(`${label} ${slugText}`.split(' ').filter(Boolean))];
  const terms = query.split(' ');
  let score = 0;

  if (label === query || slugText === query) score += 1000;
  if (label.startsWith(query) || slugText.startsWith(query)) score += 420;
  if (label.includes(query) || slugText.includes(query)) score += 220;

  for (const term of terms) {
    if (words.includes(term)) {
      score += 90;
      continue;
    }
    if (words.some((word) => word.startsWith(term))) {
      score += 55;
      continue;
    }
    if (words.some((word) => word.includes(term))) {
      score += 30;
      continue;
    }
    const similarity = Math.max(0, ...words.map((word) => diceCoefficient(term, word)));
    if (term.length >= 4 && similarity >= 0.72) {
      score += Math.round(similarity * 25);
      continue;
    }
    return 0;
  }

  const acronym = words.map((word) => word[0]).join('');
  if (query.length >= 2 && acronym.startsWith(query.replaceAll(' ', ''))) score += 140;
  if (entry.lastmod) {
    const ageDays = Math.max(0, (Date.now() - Date.parse(entry.lastmod)) / 86400000);
    score += Math.max(0, 20 - Math.log10(ageDays + 1) * 8);
  }
  return score;
}

async function searchIndex(query) {
  const entries = await ensureIndex();
  return entries.map((entry) => ({entry, score: scoreEntry(entry, query)}))
    .filter((candidate) => candidate.score > 0)
    .sort((left, right) => right.score - left.score);
}

async function loadSearchTitle(entry) {
  const cached = titleCache.get(entry.slug);
  if (cached && cached.expiresAt > Date.now()) return cached.value || cached.promise;
  const pending = fetchText(entry.id).then(extractSearchTitle).then((title) => {
    if (!title) throw new Error('APK Award title is missing');
    titleCache.set(entry.slug, {value: title, expiresAt: Date.now() + DETAIL_TTL_MS});
    return title;
  }).catch(() => {
    titleCache.delete(entry.slug);
    return entry.label;
  });
  titleCache.set(entry.slug, {promise: pending, expiresAt: Date.now() + 30000});
  return pending;
}

function isDirectDownload(url) {
  return /^https:\/\/(?:[^/]+\.)?apkawards\.com\//i.test(url) || /^https:\/\/apkaward\.com\/wp-content\/uploads\//i.test(url);
}

async function resolveDownload(url) {
  if (isDirectDownload(url)) return url;
  if (!/^https:\/\/apkaward\.com\/\d+\/download\//i.test(url)) return null;
  const tab = await apkmesh.browser.open(url);
  try {
    await tab.waitFor('a.dowmapk[href], .dowmapk_box a[href], .link_a a[href]');
    const links = await tab.queryAll('a.dowmapk[href], .dowmapk_box a[href], .link_a a[href]', {url: '@href'});
    return links.map((item) => item.url).find(isDirectDownload) || null;
  } finally {
    await tab.close();
  }
}

globalThis.source = {
  manifest: {
    id: 'apkaward-demo',
    name: 'APK Award（测试源）',
    version: '0.3.0',
    minApiVersion: 1,
    homepage: 'https://apkaward.com',
    permissions: {
      network: ['apkaward.com', '*.apkaward.com', 'apkawards.com', '*.apkawards.com'],
      browser: true,
      download: true,
      install: true,
    },
  },

  async search(query, page = 1) {
    const normalized = normalizeSearch(query);
    if (normalized.length < 2) throw new TypeError('搜索关键词至少需要 2 个字符');
    const matches = await searchIndex(normalized);
    const selected = matches.slice(0, 24);
    const enriched = await mapLimit(selected, 4, async (candidate) => {
      const label = await loadSearchTitle(candidate.entry);
      const entry = {...candidate.entry, label};
      return {entry, score: Math.max(candidate.score, scoreEntry(entry, normalized))};
    });
    const ranked = enriched.concat(matches.slice(selected.length));
    ranked.sort((left, right) => right.score - left.score);
    const start = Math.max(0, (Number(page) - 1) * 20);
    return ranked.slice(start, start + 20).map(({entry}) => ({
      id: entry.id,
      name: entry.label,
      packageName: '',
      version: '',
      size: '',
      updatedAt: entry.lastmod || '',
      category: '',
      iconUrl: '',
      summary: '来自 APK Award 公开 sitemap',
    }));
  },

  async details(url) {
    const tab = await apkmesh.browser.open(url);
    try {
      await tab.waitFor('main, article');
      const app = await tab.query({
        id: 'link[rel="canonical"]@href',
        name: 'article.sac h1, h1, meta[property="og:title"]@content',
        packageName: '[data-package]@data-package',
        version: 'meta[itemprop="softwareVersion"]@content, .version',
        updatedAt: 'meta[itemprop="dateModified"]@content, time@datetime',
        category: '.category, [rel="category"]',
        iconUrl: 'meta[property="og:image"]@content, article.sac .pic img@src',
        summary: 'meta[name="description"]@content, meta[property="og:description"]@content',
        description: '.entry-content, article',
      });
      const screenshotNodes = await tab.queryAll('.screenshots img, .gallery img, article.sac img', {url: '@src'});
      app.screenshots = screenshotNodes.map((item) => item.url).filter(Boolean);
      const commentNodes = await tab.queryAll('.comment-content, .comment-body', {text: '@text'});
      app.comments = commentNodes.map((item) => item.text).filter(Boolean);
      const downloadNodes = await tab.queryAll('.newapksdw a.aabbadownpk, a[href*="download"]', {
        label: '@text',
        url: '@href',
        onclick: '@onclick',
        size: '.zipsize@text, [data-size]@data-size',
      });
      const candidates = downloadNodes.map((item) => {
        const direct = /(?:apk_mod|apk_gmod|freedown)\s*\(\s*this\s*,\s*(['"])(https?:\/\/.*?)\1/i.exec(item.onclick || '');
        const target = direct ? direct[2] : item.url;
        return {label: (item.label || '').trim(), url: target, size: item.size || ''};
      }).filter((item) => item.label && item.url).slice(0, 20);
      app.downloads = [];
      for (const item of candidates) {
        const resolved = await resolveDownload(item.url);
        if (resolved && !app.downloads.some((download) => download.url === resolved)) {
          app.downloads.push({...item, url: resolved});
        }
      }
      return app;
    } finally {
      await tab.close();
    }
  },
};
