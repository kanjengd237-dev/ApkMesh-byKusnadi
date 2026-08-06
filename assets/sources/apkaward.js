/** APK Award development source for APK Mesh's QuickJS contract. */
globalThis.source = {
  manifest: {
    id: 'apkaward-demo',
    name: 'APK Award（测试源）',
    version: '0.1.0',
    minApiVersion: 1,
    homepage: 'https://apkaward.com',
    permissions: {
      network: ['apkaward.com', '*.apkaward.com'],
      browser: true,
      download: true,
      install: false,
    },
  },

  async search(query, page = 1) {
    const tab = await apkmesh.browser.open(
      `https://apkaward.com/?s=${encodeURIComponent(query)}&paged=${page}`,
    );
    await tab.waitFor('article, .post, main');
    return tab.queryAll('article, .post', {
      id: 'a@href',
      name: 'h2, h3, .entry-title',
      iconUrl: 'img@src',
      summary: '.entry-summary, p',
    });
  },

  async details(url) {
    const tab = await apkmesh.browser.open(url);
    await tab.waitFor('main, article');
    const app = await tab.query({
      id: 'link[rel="canonical"]@href',
      name: 'h1',
      packageName: '[data-package]@data-package',
      version: '.version, [data-version]',
      updatedAt: 'time@datetime',
      category: '.category, [rel="category"]',
      iconUrl: 'article img@src',
      description: '.entry-content, article',
      screenshots: ['.screenshots img@src', '.gallery img@src'],
      comments: ['.comment-content', '.comment-body'],
    });
    app.downloads = await tab.queryAll('a[href*="download"]', {
      label: '@text',
      url: '@href',
      size: '[data-size]@data-size',
    });
    return app;
  },
};
