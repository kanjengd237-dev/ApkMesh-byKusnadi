import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/source_runtime.dart';
import '../widgets/app_result_tile.dart';
import '../widgets/empty_message.dart';
import 'details_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.state,
    required this.controller,
    this.onSearchLoadingChanged,
    super.key,
  });

  final AppState state;
  final TextEditingController controller;
  final ValueChanged<bool>? onSearchLoadingChanged;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  List<AppListing> results = const [];
  SourceCatalog catalog = const SourceCatalog();
  bool loading = false;
  bool loadingMore = false;
  bool catalogLoading = false;
  bool catalogLoaded = false;
  String? error;
  String? catalogError;
  String? submittedQuery;
  String _selectedTab = '';
  String? _loadedCatalogSourceId;
  final Map<String, _CatalogTabLoadState> _catalogTabStates = {};
  int _searchGeneration = 0;
  int _catalogGeneration = 0;
  SearchResultRanker? _searchRanker;
  Map<String, int> _searchSourceOrder = const {};
  Map<String, Map<String, int>> _searchResultOrder = {};
  Set<String> _searchSourceIds = const {};
  Set<String> _searchExhaustedSources = {};
  Set<String> _searchFailedSources = {};
  Map<String, String> _searchPageErrors = {};
  String? _lastShownSearchError;
  int _nextSearchPage = 2;
  final List<AppListing> _pendingSearchResults = [];
  Timer? _searchMergeTimer;
  SourceSearchCancellation? _searchCancellation;
  late final ScrollController _contentScrollController;

  @override
  void initState() {
    super.initState();
    _contentScrollController = ScrollController()
      ..addListener(_onContentScroll);
    widget.state.addListener(_onStateChanged);
    _loadCatalog();
  }

  @override
  void dispose() {
    _searchCancellation?.cancel();
    _searchMergeTimer?.cancel();
    widget.state.removeListener(_onStateChanged);
    _contentScrollController
      ..removeListener(_onContentScroll)
      ..dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted || submittedQuery != null) return;
    if (_loadedCatalogSourceId == widget.state.homeSourceId) return;
    _catalogTabStates.clear();
    setState(() {
      catalog = const SourceCatalog();
      catalogLoaded = false;
      catalogLoading = false;
      _selectedTab = '';
    });
    _loadCatalog();
  }

  Future<void> _loadCatalog({bool force = false}) async {
    if ((catalogLoaded && !force) || catalogLoading) return;
    if (force) _catalogTabStates.clear();
    final generation = ++_catalogGeneration;
    setState(() {
      catalogLoading = true;
      catalogError = null;
    });
    try {
      final content = await widget.state.catalog();
      if (!mounted || generation != _catalogGeneration) return;
      final selected = _selectCatalogTab(content);
      setState(() {
        catalog = content;
        _loadedCatalogSourceId = widget.state.homeSourceId;
        catalogLoading = false;
        catalogLoaded = true;
        _selectedTab = selected == null ? '' : _catalogTabKey(selected);
        if (content.tabs.isEmpty && widget.state.sourceErrors.isNotEmpty) {
          catalogError = widget.state.sourceErrors.entries
              .map((entry) => '${entry.key}：${entry.value}')
              .join('\n');
        }
      });
      if (selected != null) await _loadCatalogTab(selected);
    } catch (loadError) {
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        catalogLoading = false;
        catalogLoaded = true;
        catalogError = loadError.toString();
      });
    }
  }

  SourceCatalogTab? _selectCatalogTab(SourceCatalog content) {
    for (final tab in content.tabs) {
      if (_catalogTabKey(tab) == _selectedTab) return tab;
    }
    for (final tab in content.tabs) {
      if (tab.id == content.defaultTabId) return tab;
    }
    return content.tabs.firstOrNull;
  }

  String _catalogTabKey(SourceCatalogTab tab) =>
      'catalog:${tab.sourceId}:${tab.id}';

  Future<void> _loadCatalogTab(
    SourceCatalogTab tab, {
    bool refresh = false,
  }) async {
    final key = _catalogTabKey(tab);
    final state = _catalogTabStates.putIfAbsent(
      key,
      () => _CatalogTabLoadState(),
    );
    if (state.loading || (!refresh && (state.loaded && !state.hasMore))) {
      return;
    }
    if (!refresh && state.loaded && !tab.paged) return;

    final generation = _catalogGeneration;
    final page = refresh ? 1 : state.nextPage;
    setState(() {
      state.loading = true;
      state.error = null;
    });
    try {
      final result = await widget.state.catalogPage(tab, page: page);
      if (!mounted || generation != _catalogGeneration) return;
      final seenIds = refresh ? <String>{} : state.seenIds;
      final newApps = <AppListing>[];
      for (final app in result.apps) {
        if (seenIds.add(app.id)) newApps.add(app);
      }
      setState(() {
        if (refresh) {
          state.seenIds
            ..clear()
            ..addAll(seenIds);
        }
        state
          ..apps = page == 1 ? newApps : [...state.apps, ...newApps]
          ..loaded = true
          ..nextPage = page + 1
          ..hasMore = tab.paged && result.hasMore && newApps.isNotEmpty
          ..error = null;
      });
    } catch (loadError) {
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        state
          ..loaded = true
          ..error = loadError.toString();
      });
    } finally {
      if (mounted && generation == _catalogGeneration) {
        setState(() => state.loading = false);
      }
    }
  }

  Future<void> search({bool preserveSelectedTab = false}) async {
    final query = widget.controller.text.trim();
    final refreshTab = preserveSelectedTab ? _activeTab(_tabs) : null;
    final sourceId = refreshTab?.sourceId;
    final sourceIds = sourceId == null ? null : {sourceId};
    final generation = ++_searchGeneration;
    _searchCancellation?.cancel();
    final cancellation = SourceSearchCancellation();
    _searchCancellation = cancellation;
    _searchRanker = null;
    _searchSourceOrder = const {};
    _searchResultOrder = {};
    _searchSourceIds =
        (sourceIds ??
                widget.state.sources
                    .where((source) => source.status == SourceStatus.enabled)
                    .map((source) => source.id))
            .toSet();
    _searchExhaustedSources = {};
    _searchFailedSources = {};
    _searchPageErrors = {};
    _lastShownSearchError = null;
    _nextSearchPage = 2;
    _searchMergeTimer?.cancel();
    _searchMergeTimer = null;
    _pendingSearchResults.clear();
    loadingMore = false;
    if (query.isEmpty) {
      final selected = _selectCatalogTab(catalog);
      setState(() {
        submittedQuery = null;
        results = const [];
        loading = false;
        error = null;
        _selectedTab = selected == null ? '' : _catalogTabKey(selected);
      });
      widget.onSearchLoadingChanged?.call(false);
      _searchCancellation = null;
      if (_loadedCatalogSourceId != widget.state.homeSourceId) {
        await _loadCatalog(force: true);
      } else if (selected != null) {
        await _loadCatalogTab(selected);
      }
      return;
    }
    _searchRanker = SearchResultRanker(query);
    _searchSourceOrder = {
      for (var index = 0; index < widget.state.sources.length; index++)
        widget.state.sources[index].id: index,
    };
    _searchResultOrder = {};
    setState(() {
      loading = true;
      error = null;
      results = const [];
      submittedQuery = query;
      _selectedTab = refreshTab?.id ?? 'all';
    });
    widget.onSearchLoadingChanged?.call(true);
    try {
      final pages = await widget.state.searchPage(
        query,
        page: 1,
        sourceIds: sourceIds,
        cancellation: cancellation,
        onSourcePage: (page) {
          if (!mounted || generation != _searchGeneration) return;
          _handleSearchPage(page);
        },
      );
      if (mounted && generation == _searchGeneration) {
        _flushSearchResults();
        final found = pages.fold<int>(
          0,
          (total, page) => total + page.results.length,
        );
        final searchError = _searchPageErrors.isNotEmpty
            ? _formatSearchPageErrors()
            : found == 0 && widget.state.sourceErrors.isNotEmpty
            ? widget.state.sourceErrors.entries
                  .map((entry) => '${entry.key}：${entry.value}')
                  .join('\n')
            : null;
        setState(() {
          loading = false;
          error = searchError;
        });
        if (searchError != null) _showSearchErrorSnackBar(searchError);
        widget.onSearchLoadingChanged?.call(false);
      }
    } catch (searchError) {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          loading = false;
          error = searchError.toString();
        });
        _showSearchErrorSnackBar(searchError.toString());
        widget.onSearchLoadingChanged?.call(false);
      }
    }
  }

  void _handleSearchPage(SourceSearchPage page) {
    final newResults = _collectSearchPageResults(page);
    if (newResults.isEmpty) return;
    _pendingSearchResults.addAll(newResults);
    _searchMergeTimer ??= Timer(
      const Duration(milliseconds: 16),
      _flushSearchResults,
    );
  }

  List<AppListing> _collectSearchPageResults(SourceSearchPage page) {
    if (!page.succeeded) {
      _searchFailedSources.add(page.sourceId);
      _searchPageErrors[page.sourceId] = page.error!;
      return const [];
    }
    if (page.results.isEmpty) {
      _searchExhaustedSources.add(page.sourceId);
      return const [];
    }

    final resultOrder = _searchResultOrder.putIfAbsent(
      page.sourceId,
      () => <String, int>{},
    );
    final newResults = <AppListing>[];
    for (final app in page.results) {
      if (resultOrder.containsKey(app.id)) continue;
      resultOrder[app.id] = resultOrder.length;
      newResults.add(app);
    }
    if (newResults.isEmpty) _searchExhaustedSources.add(page.sourceId);
    return newResults;
  }

  String _formatSearchPageErrors() => _searchPageErrors.entries
      .map((entry) => '${entry.key}：${entry.value}')
      .join('\n');

  void _showSearchErrorSnackBar(String message) {
    if (!mounted || message.isEmpty || message == _lastShownSearchError) {
      return;
    }
    _lastShownSearchError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('搜索源加载失败'),
          action: SnackBarAction(
            label: '详情',
            onPressed: () => _showSearchErrorDetails(message),
          ),
        ),
      );
    });
  }

  void _showSearchErrorDetails(String message) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SearchErrorSheet(message: message),
    );
  }

  bool get _hasSearchSourcesToLoad => _searchSourceIds.any(
    (sourceId) =>
        !_searchExhaustedSources.contains(sourceId) &&
        !_searchFailedSources.contains(sourceId),
  );

  void _onContentScroll() {
    if (!_contentScrollController.hasClients ||
        _contentScrollController.position.extentAfter > 480) {
      return;
    }
    if (submittedQuery != null) {
      if (!loading && !loadingMore) unawaited(_loadNextSearchPage());
      return;
    }
    final tab = _activeTab(_tabs)?.catalogTab;
    if (tab == null || !tab.paged) return;
    final state = _catalogTabStates[_catalogTabKey(tab)];
    if (state == null || state.loading || !state.hasMore) return;
    unawaited(_loadCatalogTab(tab));
  }

  Future<void> _loadNextSearchPage() async {
    if (loading || loadingMore || !_hasSearchSourcesToLoad) return;
    final generation = _searchGeneration;
    final sourceIds = _searchSourceIds
        .where(
          (sourceId) =>
              !_searchExhaustedSources.contains(sourceId) &&
              !_searchFailedSources.contains(sourceId),
        )
        .toSet();
    if (sourceIds.isEmpty) return;

    final page = _nextSearchPage++;
    setState(() => loadingMore = true);
    try {
      final pages = await widget.state.searchPage(
        submittedQuery!,
        page: page,
        sourceIds: sourceIds,
        cancellation: _searchCancellation,
      );
      if (!mounted || generation != _searchGeneration) return;
      final newResults = <AppListing>[];
      for (final result in pages) {
        newResults.addAll(_collectSearchPageResults(result));
      }
      _appendSearchResults(newResults);
      if (_searchPageErrors.isNotEmpty) {
        final searchError = _formatSearchPageErrors();
        setState(() => error = searchError);
        _showSearchErrorSnackBar(searchError);
      }
    } catch (loadError) {
      if (mounted && generation == _searchGeneration) {
        final message = loadError.toString();
        setState(() => error = message);
        _showSearchErrorSnackBar(message);
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => loadingMore = false);
      }
    }
  }

  void _appendSearchResults(List<AppListing> newResults) {
    if (newResults.isEmpty) return;
    final sortedResults = [...newResults]..sort(_compareSearchResults);
    setState(() => results = [...results, ...sortedResults]);
  }

  int _compareSearchResults(AppListing left, AppListing right) {
    final ranker = _searchRanker;
    if (ranker == null) return 0;

    final scoreOrder = ranker.score(right).compareTo(ranker.score(left));
    if (scoreOrder != 0) return scoreOrder;

    const fallbackOrder = 1 << 30;
    final sourceOrder = (_searchSourceOrder[left.sourceId] ?? fallbackOrder)
        .compareTo(_searchSourceOrder[right.sourceId] ?? fallbackOrder);
    if (sourceOrder != 0) return sourceOrder;

    final leftResultOrder =
        _searchResultOrder[left.sourceId]?[left.id] ?? fallbackOrder;
    final rightResultOrder =
        _searchResultOrder[right.sourceId]?[right.id] ?? fallbackOrder;
    return leftResultOrder.compareTo(rightResultOrder);
  }

  void _mergeRegisteredSearchResults(List<AppListing> newResults) {
    if (newResults.isEmpty) return;
    final merged = [...results, ...newResults]..sort(_compareSearchResults);
    setState(() => results = merged);
  }

  void _flushSearchResults() {
    _searchMergeTimer?.cancel();
    _searchMergeTimer = null;
    if (!mounted || _pendingSearchResults.isEmpty) return;
    final pending = List<AppListing>.of(_pendingSearchResults);
    _pendingSearchResults.clear();
    _mergeRegisteredSearchResults(pending);
  }

  void showHome() {
    ++_searchGeneration;
    _searchCancellation?.cancel();
    _searchCancellation = null;
    _searchMergeTimer?.cancel();
    _searchMergeTimer = null;
    _pendingSearchResults.clear();
    final selected = _selectCatalogTab(catalog);
    setState(() {
      submittedQuery = null;
      results = const [];
      loading = false;
      loadingMore = false;
      error = null;
      _selectedTab = selected == null ? '' : _catalogTabKey(selected);
    });
    widget.onSearchLoadingChanged?.call(false);
    if (_loadedCatalogSourceId != widget.state.homeSourceId) {
      _loadCatalog(force: true);
    } else if (selected != null) {
      _loadCatalogTab(selected);
    } else {
      _loadCatalog();
    }
  }

  Future<void> _refreshContent() async {
    final activeTab = _activeTab(_tabs);
    if (submittedQuery != null) {
      await search(preserveSelectedTab: true);
      return;
    }
    final catalogTab = activeTab?.catalogTab;
    if (catalogTab != null) await _loadCatalogTab(catalogTab, refresh: true);
  }

  List<ContentTab> get _tabs {
    if (submittedQuery == null) {
      return catalog.tabs
          .map(
            (tab) => ContentTab(
              id: _catalogTabKey(tab),
              label: tab.name,
              catalogTab: tab,
            ),
          )
          .toList(growable: false);
    }
    final tabs = <ContentTab>[const ContentTab(id: 'all', label: '全部源')];
    final selectedSourceId = _selectedTab.startsWith('source:')
        ? _selectedTab.substring('source:'.length)
        : null;
    if (selectedSourceId != null) {
      final selected = widget.state.sources
          .where(
            (source) =>
                source.id == selectedSourceId &&
                source.status == SourceStatus.enabled,
          )
          .firstOrNull;
      if (selected != null) {
        tabs.add(
          ContentTab(
            id: 'source:${selected.id}',
            label: selected.name,
            sourceId: selected.id,
          ),
        );
      }
    }
    return tabs;
  }

  ContentTab? _activeTab(List<ContentTab> tabs) {
    for (final tab in tabs) {
      if (tab.id == _selectedTab) return tab;
    }
    return tabs.firstOrNull;
  }

  Widget _buildTabBar(
    BuildContext context,
    List<ContentTab> tabs,
    ContentTab activeTab,
  ) {
    final tabKey = tabs.map((tab) => tab.id).join('|');
    final activeIndex = tabs.indexWhere((tab) => tab.id == activeTab.id);
    final tabBar = DefaultTabController(
      key: ValueKey(tabKey),
      length: tabs.length,
      initialIndex: activeIndex < 0 ? 0 : activeIndex,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        onTap: (index) {
          if (index < tabs.length) {
            final tab = tabs[index];
            setState(() => _selectedTab = tab.id);
            if (tab.catalogTab != null) {
              unawaited(_loadCatalogTab(tab.catalogTab!));
            }
          }
        },
        tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
      ),
    );
    if (submittedQuery == null) return tabBar;
    return Row(
      children: [
        Expanded(child: tabBar),
        IconButton(
          tooltip: '筛选搜索源',
          onPressed: _showSourcePicker,
          icon: const Icon(Icons.filter_list),
        ),
      ],
    );
  }

  Future<void> _showSourcePicker() async {
    final sources = widget.state.sources
        .where((source) => source.status == SourceStatus.enabled)
        .toList(growable: false);
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SourcePickerSheet(sources: sources),
    );
    if (!mounted || selectedId == null) return;
    setState(() => _selectedTab = 'source:$selectedId');
  }

  Widget _buildStaticContent(List<Widget> children) => ListView(
    controller: _contentScrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
    children: children,
  );

  Widget _buildCatalogView(BuildContext context, ContentTab? activeTab) {
    if (!widget.state.hasEnabledSource) {
      return _buildStaticContent(const [
        EmptyMessage(
          icon: Icons.hub_outlined,
          title: '没有启用的源',
          detail: '请先在源管理中启用一个源。',
        ),
      ]);
    }
    if (catalogLoading && !catalogLoaded) {
      return _buildStaticContent(const [
        SearchLoadingView(icon: Icons.home_outlined, label: '正在加载首页'),
      ]);
    }
    if (catalogError != null && catalog.tabs.isEmpty) {
      return _buildStaticContent([
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('首页内容加载失败'),
            subtitle: Text(catalogError!),
            trailing: IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadCatalog(force: true),
            ),
          ),
        ),
      ]);
    }
    final tab = activeTab?.catalogTab;
    if (tab == null) {
      return _buildStaticContent(const [
        EmptyMessage(
          icon: Icons.home_work_outlined,
          title: '暂无目录内容',
          detail: '当前主页源没有返回可用标签。',
        ),
      ]);
    }
    final state = _catalogTabStates[_catalogTabKey(tab)];
    if (state == null || (state.loading && !state.loaded)) {
      return _buildStaticContent([
        SearchLoadingView(icon: Icons.apps_outlined, label: '正在加载${tab.name}'),
      ]);
    }
    if (state.error != null && state.apps.isEmpty) {
      return _buildStaticContent([
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text('${tab.name}加载失败'),
            subtitle: Text(state.error!),
            trailing: IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadCatalogTab(tab, refresh: true),
            ),
          ),
        ),
      ]);
    }
    if (state.apps.isEmpty) {
      return _buildStaticContent(const [
        EmptyMessage(
          icon: Icons.apps_outage_outlined,
          title: '暂无应用',
          detail: '该标签没有返回可用应用。',
        ),
      ]);
    }
    final hasFooter = state.loading || state.error != null;
    return ListView.builder(
      controller: _contentScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      itemCount: state.apps.length + (hasFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < state.apps.length) {
          return AppResultTile(
            app: state.apps[index],
            state: widget.state,
            onOpen: (app) => showAppDetails(context, widget.state, app),
            showDivider: index < state.apps.length - 1,
          );
        }
        if (state.loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('加载下一页失败'),
          trailing: IconButton(
            tooltip: '重试',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadCatalogTab(tab),
          ),
        );
      },
    );
  }

  Widget _buildSearchEmpty(BuildContext context, ContentTab activeTab) {
    if (loading) return const SearchLoadingView();
    return EmptyMessage(
      icon: Icons.manage_search,
      title: '未找到结果',
      detail: error == null
          ? activeTab.sourceId == null
                ? '已在所有启用的源中搜索“$submittedQuery”。'
                : '当前源没有返回“$submittedQuery”的结果。'
          : '源请求未完成，请打开错误详情查看原因。',
    );
  }

  Widget _buildSearchView(BuildContext context, ContentTab activeTab) {
    final visibleResults = activeTab.sourceId == null
        ? results
        : results.where((app) => app.sourceId == activeTab.sourceId).toList();
    if (!widget.state.hasEnabledSource || visibleResults.isEmpty) {
      return ListView(
        controller: _contentScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        children: [
          if (!widget.state.hasEnabledSource)
            const EmptyMessage(
              icon: Icons.hub_outlined,
              title: '没有启用的源',
              detail: '请先在源管理中启用一个源。',
            )
          else
            _buildSearchEmpty(context, activeTab),
        ],
      );
    }
    final itemCount = visibleResults.length + (loadingMore ? 1 : 0);
    return ListView.builder(
      controller: _contentScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == visibleResults.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return AppResultTile(
          app: visibleResults[index],
          state: widget.state,
          onOpen: (app) => showAppDetails(context, widget.state, app),
          showDivider: index < visibleResults.length - 1,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingHome = submittedQuery == null;
    final tabs = _tabs;
    final activeTab = _activeTab(tabs);
    return Column(
      children: [
        if (activeTab != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildTabBar(context, tabs, activeTab),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshContent,
            child: showingHome
                ? _buildCatalogView(context, activeTab)
                : _buildSearchView(context, activeTab!),
          ),
        ),
      ],
    );
  }
}

class _SourcePickerSheet extends StatefulWidget {
  const _SourcePickerSheet({required this.sources});

  final List<ApkSource> sources;

  @override
  State<_SourcePickerSheet> createState() => _SourcePickerSheetState();
}

class _SourcePickerSheetState extends State<_SourcePickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _query.text.trim().toLowerCase();
    final sources = keyword.isEmpty
        ? widget.sources
        : widget.sources
              .where(
                (source) =>
                    source.name.toLowerCase().contains(keyword) ||
                    source.id.toLowerCase().contains(keyword) ||
                    source.homepage.toLowerCase().contains(keyword),
              )
              .toList(growable: false);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '筛选搜索源',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索源名称或域名',
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                return ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(source.name),
                  subtitle: Text(source.homepage),
                  onTap: () => Navigator.pop(context, source.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SearchLoadingView extends StatefulWidget {
  const SearchLoadingView({
    this.icon = Icons.manage_search,
    this.label = '正在搜索',
    super.key,
  });

  final IconData icon;
  final String label;

  @override
  State<SearchLoadingView> createState() => _SearchLoadingViewState();
}

class _SearchLoadingViewState extends State<SearchLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 300,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final sweep = -1.8 + (_controller.value * 3.6);
            final highlight = Color.lerp(
              scheme.primary,
              scheme.onPrimary,
              0.5,
            )!;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(sweep, 0),
                end: Alignment(sweep + 1.5, 0),
                colors: [
                  scheme.primary,
                  Color.lerp(scheme.primary, highlight, 0.5)!,
                  highlight,
                  Color.lerp(scheme.primary, highlight, 0.5)!,
                  scheme.primary,
                ],
                stops: const [0, 0.3, 0.5, 0.7, 1],
              ).createShader(bounds),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 88, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                widget.label,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchErrorSheet extends StatelessWidget {
  const SearchErrorSheet({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '搜索错误详情',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '复制报错信息',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: message));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已复制报错信息')));
                  },
                ),
              ],
            ),
            const Divider(),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: SelectableText(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContentTab {
  const ContentTab({
    required this.id,
    required this.label,
    this.catalogTab,
    this.sourceId,
  });

  final String id;
  final String label;
  final SourceCatalogTab? catalogTab;
  final String? sourceId;
}

class _CatalogTabLoadState {
  List<AppListing> apps = const [];
  final Set<String> seenIds = {};
  int nextPage = 1;
  bool loaded = false;
  bool loading = false;
  bool hasMore = true;
  String? error;
}
