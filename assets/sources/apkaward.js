/** APK Award development source for APK Mesh's QuickJS contract. */
const ORIGIN = 'https://apkaward.com';
let sitemapPromise;
const sitemapCache = new Map();

function decodeXml(value) {
  return value.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
}

function normalize(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function humanize(slug) {
  return slug.split('-').filter(Boolean).map((word) => word.length <= 4 ? word.toUpperCase() : word[0].toUpperCase() + word.slice(1)).join(' ');
}

async function fetchText(url) {
  return apkmesh.request(url, {headers: {Accept: 'application/xml,text/xml,text/html;q=0.9,*/*;q=0.8'}});
}

async function getSitemapUrls() {
  if (sitemapPromise) return sitemapPromise;
  sitemapPromise = fetchText(`${ORIGIN}/sitemap.xml`).then((root) =>
    [...root.matchAll(/<loc>\s*(https:\/\/apkaward\.com\/sitemap-pt-post-\d{4}-\d{2}\.xml)\s*<\/loc>/gi)]
      .map((match) => decodeXml(match[1])),
  ).catch((error) => {
    sitemapPromise = null;
    throw error;
  });
  return sitemapPromise;
}

async function loadSitemap(url) {
  if (sitemapCache.has(url)) return sitemapCache.get(url);
  const pending = fetchText(url).then((xml) =>
    [...xml.matchAll(/<url>[\s\S]*?<loc>\s*(https:\/\/apkaward\.com\/([^<\/?#]+)\/?)\s*<\/loc>[\s\S]*?(?:<lastmod>([^<]+)<\/lastmod>)?[\s\S]*?<\/url>/gi)]
      .map((match) => ({
        id: decodeXml(match[1]),
        slug: decodeXml(match[2]).toLowerCase(),
        updatedAt: match[3] || '',
      })),
  ).catch((error) => {
    sitemapCache.delete(url);
    throw error;
  });
  sitemapCache.set(url, pending);
  return pending;
}

async function searchIndex(terms) {
  const sitemapUrls = await getSitemapUrls();
  const matches = new Map();
  for (let offset = 0; offset < sitemapUrls.length; offset += 6) {
    const batch = await Promise.all(sitemapUrls.slice(offset, offset + 6).map(async (url) => {
      try {
        return await loadSitemap(url);
      } catch (_) {
        return [];
      }
    }));
    batch.flat().forEach((entry) => {
      const text = normalize(entry.slug);
      if (!terms.every((term) => text.includes(term))) return;
      const joined = terms.join(' ');
      const exact = text === joined ? 1000 : 0;
      const prefix = text.startsWith(joined) ? 200 : 0;
      const score = exact + prefix + terms.reduce((total, term) => total + (text.split(' ').includes(term) ? 50 : 10), 0);
      const previous = matches.get(entry.slug);
      if (!previous || score > previous.score) matches.set(entry.slug, {...entry, score});
    });
    // Newer sitemap groups are searched first. Stop once one group contains matches.
    if (matches.size) break;
  }
  return [...matches.values()].sort((left, right) => right.score - left.score);
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
    version: '0.2.0',
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
    const terms = normalize(query).split(' ').filter(Boolean);
    if (!terms.length) return [];
    const index = await searchIndex(terms);
    return index.slice((page - 1) * 20, page * 20).map((entry) => ({
      id: entry.id,
      name: humanize(entry.slug),
      packageName: '',
      version: '',
      size: '',
      updatedAt: entry.updatedAt,
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
