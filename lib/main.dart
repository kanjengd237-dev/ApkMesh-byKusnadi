import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/app_state.dart';
import 'core/debug_log.dart';
import 'core/models.dart';
import 'core/source_runtime.dart';
import 'widgets/app_icon.dart';
import 'widgets/app_result_tile.dart';
import 'widgets/package_lookup_sheet.dart';

void _showAppDetails(BuildContext context, AppState state, AppListing app) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DetailsSheet(app: app, state: state),
  );
}

void main() => runApp(const ApkMeshApp());

class ApkMeshApp extends StatefulWidget {
  const ApkMeshApp({super.key});

  @override
  State<ApkMeshApp> createState() => _ApkMeshAppState();
}

class _ApkMeshAppState extends State<ApkMeshApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.initialize();
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff315f8c),
      brightness: Brightness.light,
    );
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp(
        title: 'APK Mesh',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: Shell(state: state),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({required this.state, super.key});
  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  bool searchOpen = false;
  bool searchResultsVisible = false;
  bool searchLoading = false;
  final searchController = TextEditingController();
  final homeKey = GlobalKey<_HomePageState>();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        key: homeKey,
        state: widget.state,
        controller: searchController,
        onSearchLoadingChanged: _handleSearchLoadingChanged,
      ),
      DownloadsPage(state: widget.state),
      SourcesPage(state: widget.state),
      SettingsPage(state: widget.state),
    ];
    final destinations = const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '主页',
      ),
      NavigationDestination(
        icon: Icon(Icons.download_outlined),
        selectedIcon: Icon(Icons.download),
        label: '下载',
      ),
      NavigationDestination(
        icon: Icon(Icons.hub_outlined),
        selectedIcon: Icon(Icons.hub),
        label: '源管理',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            bottom: index == 0 && searchLoading
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(3),
                    child: LinearProgressIndicator(minHeight: 3),
                  )
                : null,
            leading: index == 0 && searchResultsVisible
                ? IconButton(
                    tooltip: '返回主页',
                    onPressed: _returnHome,
                    icon: const Icon(Icons.arrow_back),
                  )
                : null,
            title: searchOpen
                ? SizedBox(
                    width: (constraints.maxWidth - 160).clamp(140.0, 520.0),
                    height: 46,
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submitSearch(),
                      decoration: InputDecoration(
                        hintText: '搜索应用名称或包名',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: IconButton(
                          tooltip: '清空搜索',
                          onPressed: searchController.clear,
                          icon: const Icon(Icons.clear, size: 20),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: const OutlineInputBorder(),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  )
                : const Text('APK Mesh'),
            actions: [
              if (!searchOpen)
                IconButton(
                  tooltip: '搜索',
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                )
              else
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: () => setState(() => searchOpen = false),
                  icon: const Icon(Icons.close),
                ),
              IconButton(
                tooltip: '调试',
                onPressed: () => _showDebugSheet(context),
                icon: const Icon(Icons.bug_report_outlined),
              ),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (value) =>
                      setState(() => index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('主页'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download),
                      label: Text('下载'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.hub_outlined),
                      selectedIcon: Icon(Icons.hub),
                      label: Text('源管理'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(index: index, children: pages),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (value) =>
                      setState(() => index = value),
                  destinations: destinations,
                ),
        );
      },
    );
  }

  void _openSearch() {
    setState(() {
      index = 0;
      searchOpen = true;
    });
  }

  void _handleSearchLoadingChanged(bool loading) {
    if (!mounted || searchLoading == loading) return;
    setState(() => searchLoading = loading);
  }

  Future<void> _submitSearch() async {
    final hasQuery = searchController.text.trim().isNotEmpty;
    setState(() {
      index = 0;
      searchOpen = false;
      searchResultsVisible = hasQuery;
    });
    await homeKey.currentState?.search();
  }

  void _returnHome() {
    setState(() {
      index = 0;
      searchOpen = false;
      searchResultsVisible = false;
    });
    searchController.clear();
    homeKey.currentState?.showHome();
  }

  void _showDebugSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DebugSheet(state: widget.state),
    );
  }
}

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
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<AppListing> results = const [];
  SourceHome home = const SourceHome();
  bool loading = false;
  bool loadingMore = false;
  bool homeLoading = false;
  bool homeLoaded = false;
  String? error;
  String? homeError;
  String? submittedQuery;
  String _selectedTab = 'home';
  String? _loadedHomeSourceId;
  final Map<String, Future<SourceCategory>> _categoryLoads = {};
  int _searchGeneration = 0;
  int _homeGeneration = 0;
  SearchResultRanker? _searchRanker;
  Map<String, int> _searchSourceOrder = const {};
  Map<String, Map<String, int>> _searchResultOrder = {};
  Set<String> _searchSourceIds = const {};
  Set<String> _searchExhaustedSources = {};
  Set<String> _searchFailedSources = {};
  Map<String, String> _searchPageErrors = {};
  String? _lastShownSearchError;
  int _nextSearchPage = 2;
  late final ScrollController _contentScrollController;
  GlobalKey<AnimatedListState> _resultsListKey = GlobalKey<AnimatedListState>();
  int _animatedResultCount = 0;

  @override
  void initState() {
    super.initState();
    _contentScrollController = ScrollController()
      ..addListener(_onContentScroll);
    widget.state.addListener(_onStateChanged);
    _loadHome();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _contentScrollController
      ..removeListener(_onContentScroll)
      ..dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted || submittedQuery != null) return;
    if (_loadedHomeSourceId == widget.state.homeSourceId) return;
    _categoryLoads.clear();
    setState(() {
      homeLoaded = false;
      homeLoading = false;
      _selectedTab = 'home';
    });
    _loadHome();
  }

  Future<void> _loadHome({bool force = false}) async {
    if ((homeLoaded && !force) || homeLoading) return;
    if (force) _categoryLoads.clear();
    final generation = ++_homeGeneration;
    setState(() {
      homeLoading = true;
      homeError = null;
    });
    try {
      final content = await widget.state.home();
      if (!mounted || generation != _homeGeneration) return;
      setState(() {
        home = content;
        _loadedHomeSourceId = widget.state.homeSourceId;
        homeLoading = false;
        homeLoaded = true;
        if (!home.categories.any(
          (category) =>
              'category:${category.sourceId}:${category.id}' == _selectedTab,
        )) {
          _selectedTab = 'home';
        }
        if (content.recommended.isEmpty &&
            content.categories.isEmpty &&
            widget.state.sourceErrors.isNotEmpty) {
          homeError = widget.state.sourceErrors.entries
              .map((entry) => '${entry.key}：${entry.value}')
              .join('\n');
        }
      });
    } catch (loadError) {
      if (!mounted || generation != _homeGeneration) return;
      setState(() {
        homeLoading = false;
        homeLoaded = true;
        homeError = loadError.toString();
      });
    }
  }

  Future<void> search({bool preserveSelectedTab = false}) async {
    final query = widget.controller.text.trim();
    final refreshTab = preserveSelectedTab ? _activeTab(_tabs) : null;
    final sourceId = refreshTab?.sourceId;
    final sourceIds = sourceId == null ? null : {sourceId};
    final generation = ++_searchGeneration;
    _resultsListKey = GlobalKey<AnimatedListState>();
    _animatedResultCount = 0;
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
    loadingMore = false;
    if (query.isEmpty) {
      setState(() {
        submittedQuery = null;
        results = const [];
        loading = false;
        error = null;
        _selectedTab = 'home';
      });
      widget.onSearchLoadingChanged?.call(false);
      await _loadHome();
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
        onSourcePage: (page) {
          if (!mounted || generation != _searchGeneration) return;
          _handleSearchPage(page);
        },
      );
      if (mounted && generation == _searchGeneration) {
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
    for (final app in newResults) {
      _insertRegisteredSearchResult(app);
    }
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
    // A repeated page cannot produce more useful results, so stop requesting
    // it even if the source does not signal the end with an empty array.
    if (newResults.isEmpty) _searchExhaustedSources.add(page.sourceId);
    return newResults;
  }

  void _appendSearchResults(List<AppListing> newResults) {
    if (newResults.isEmpty) return;
    final sortedResults = [...newResults]..sort(_compareSearchResults);
    final startIndex = results.length;
    final listKey = _resultsListKey;
    final animatedList = listKey.currentState;
    setState(() {
      results = [...results, ...sortedResults];
      if (animatedList == null) _animatedResultCount = results.length;
    });
    if (animatedList != null) {
      for (var index = 0; index < sortedResults.length; index++) {
        animatedList.insertItem(
          startIndex + index,
          duration: const Duration(milliseconds: 260),
        );
      }
      _animatedResultCount += sortedResults.length;
    }
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
      builder: (_) => _SearchErrorSheet(message: message),
    );
  }

  bool get _hasSearchSourcesToLoad => _searchSourceIds.any(
    (sourceId) =>
        !_searchExhaustedSources.contains(sourceId) &&
        !_searchFailedSources.contains(sourceId),
  );

  void _onContentScroll() {
    if (!mounted || submittedQuery == null || loading || loadingMore) return;
    if (!_contentScrollController.hasClients ||
        _contentScrollController.position.extentAfter > 480) {
      return;
    }
    unawaited(_loadNextSearchPage());
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
      );
      if (!mounted || generation != _searchGeneration) return;
      final newResults = <AppListing>[];
      for (final result in pages) {
        newResults.addAll(_collectSearchPageResults(result));
      }
      // A pagination request is one logical batch: sort only this batch and
      // append it after the results already visible to the user.
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

  void _insertRegisteredSearchResult(AppListing app) {
    var insertionIndex = results.length;
    for (var index = 0; index < results.length; index++) {
      if (_compareSearchResults(app, results[index]) < 0) {
        insertionIndex = index;
        break;
      }
    }

    final listKey = _resultsListKey;
    final animatedList = listKey.currentState;
    setState(() {
      results = [...results]..insert(insertionIndex, app);
      if (animatedList == null) _animatedResultCount = results.length;
    });
    if (animatedList != null) {
      animatedList.insertItem(
        insertionIndex,
        duration: const Duration(milliseconds: 260),
      );
      _animatedResultCount += 1;
    }
  }

  void showHome() {
    ++_searchGeneration;
    _resultsListKey = GlobalKey<AnimatedListState>();
    _animatedResultCount = 0;
    setState(() {
      submittedQuery = null;
      results = const [];
      loading = false;
      loadingMore = false;
      error = null;
      _selectedTab = 'home';
    });
    widget.onSearchLoadingChanged?.call(false);
    _loadHome();
  }

  Future<void> _refreshContent() async {
    final activeTab = _activeTab(_tabs);
    if (submittedQuery != null) {
      await search(preserveSelectedTab: true);
      return;
    }
    final category = activeTab.category;
    if (category != null) {
      final key = '${category.sourceId}:${category.id}';
      final future = widget.state.category(category);
      _categoryLoads[key] = future;
      setState(() {});
      try {
        await future;
      } catch (_) {
        // FutureBuilder renders the category error in the refreshed tab.
      }
      return;
    }
    await _loadHome(force: true);
  }

  List<_ContentTab> get _tabs {
    if (submittedQuery == null) {
      return [
        const _ContentTab(id: 'home', label: '主页'),
        ...home.categories.map(
          (category) => _ContentTab(
            id: 'category:${category.sourceId}:${category.id}',
            label: category.name,
            category: category,
          ),
        ),
      ];
    }
    return [
      const _ContentTab(id: 'all', label: '全部源'),
      ...widget.state.sources
          .where((source) => source.status == SourceStatus.enabled)
          .map(
            (source) => _ContentTab(
              id: 'source:${source.id}',
              label: source.name,
              sourceId: source.id,
            ),
          ),
    ];
  }

  _ContentTab _activeTab(List<_ContentTab> tabs) {
    for (final tab in tabs) {
      if (tab.id == _selectedTab) return tab;
    }
    return tabs.first;
  }

  Widget _buildTabBar(
    BuildContext context,
    List<_ContentTab> tabs,
    _ContentTab activeTab,
  ) {
    final tabKey = tabs.map((tab) => tab.id).join('|');
    final activeIndex = tabs.indexWhere((tab) => tab.id == activeTab.id);
    return DefaultTabController(
      key: ValueKey(tabKey),
      length: tabs.length,
      initialIndex: activeIndex < 0 ? 0 : activeIndex,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        onTap: (index) {
          if (index < tabs.length) {
            setState(() => _selectedTab = tabs[index].id);
          }
        },
        tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
      ),
    );
  }

  Future<SourceCategory> _categoryFuture(SourceCategory category) {
    final key = '${category.sourceId}:${category.id}';
    return _categoryLoads.putIfAbsent(
      key,
      () => category.apps.isNotEmpty
          ? Future<SourceCategory>.value(category)
          : widget.state.category(category),
    );
  }

  List<Widget> _buildHomeContent(BuildContext context, _ContentTab activeTab) {
    if (homeLoading && !homeLoaded) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (homeError != null &&
        home.recommended.isEmpty &&
        home.categories.isEmpty) {
      return [
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('首页内容加载失败'),
            subtitle: Text(homeError!),
          ),
        ),
      ];
    }
    if (activeTab.category != null) {
      return [
        _CategoryTabContent(
          category: activeTab.category!,
          future: _categoryFuture(activeTab.category!),
          state: widget.state,
        ),
      ];
    }
    final recommended = home.recommended.take(12).toList();
    if (recommended.isEmpty) {
      return const [
        EmptyMessage(
          icon: Icons.home_work_outlined,
          title: '暂无推荐应用',
          detail: '当前主页源没有返回推荐应用。',
        ),
      ];
    }
    return [
      Text('推荐应用', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      ...recommended.asMap().entries.map(
        (entry) => AppResultTile(
          app: entry.value,
          state: widget.state,
          onOpen: (app) => _showAppDetails(context, widget.state, app),
          showDivider: entry.key < recommended.length - 1,
        ),
      ),
    ];
  }

  Widget _buildAnimatedResults(BuildContext context) {
    return AnimatedList(
      key: _resultsListKey,
      initialItemCount: _animatedResultCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: animation,
          child: AppResultTile(
            app: results[index],
            state: widget.state,
            onOpen: (app) => _showAppDetails(context, widget.state, app),
            showDivider: index < results.length - 1,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchContent(
    BuildContext context,
    _ContentTab activeTab,
  ) {
    final visibleResults = activeTab.sourceId == null
        ? results
        : results.where((app) => app.sourceId == activeTab.sourceId).toList();
    final resultList = activeTab.sourceId == null
        ? _buildAnimatedResults(context)
        : Column(
            children: visibleResults
                .asMap()
                .entries
                .map(
                  (entry) => AppResultTile(
                    app: entry.value,
                    state: widget.state,
                    onOpen: (app) =>
                        _showAppDetails(context, widget.state, app),
                    showDivider: entry.key < visibleResults.length - 1,
                  ),
                )
                .toList(),
          );
    return [
      if (loading && visibleResults.isEmpty) const _SearchLoadingView(),
      if (!loading && visibleResults.isEmpty)
        EmptyMessage(
          icon: Icons.manage_search,
          title: '未找到结果',
          detail: error == null
              ? activeTab.sourceId == null
                    ? '已在所有启用的源中搜索“$submittedQuery”。'
                    : '当前源没有返回“$submittedQuery”的结果。'
              : '源请求未完成，请打开错误详情查看原因。',
        ),
      if (visibleResults.isNotEmpty) resultList,
      if (loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final showingHome = submittedQuery == null;
    final tabs = _tabs;
    final activeTab = _activeTab(tabs);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildTabBar(context, tabs, activeTab),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshContent,
            child: ListView(
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
                  ...(showingHome
                      ? _buildHomeContent(context, activeTab)
                      : _buildSearchContent(context, activeTab)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchLoadingView extends StatefulWidget {
  const _SearchLoadingView({
    this.icon = Icons.manage_search,
    this.label = '正在搜索',
  });

  final IconData icon;
  final String label;

  @override
  State<_SearchLoadingView> createState() => _SearchLoadingViewState();
}

class _SearchLoadingViewState extends State<_SearchLoadingView>
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
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(sweep, 0),
                end: Alignment(sweep + 0.9, 0),
                colors: [
                  scheme.primary.withValues(alpha: 0.45),
                  scheme.primary,
                  scheme.onPrimary,
                  scheme.primary,
                  scheme.primary.withValues(alpha: 0.45),
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

class _SearchErrorSheet extends StatelessWidget {
  const _SearchErrorSheet({required this.message});

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

class _ContentTab {
  const _ContentTab({
    required this.id,
    required this.label,
    this.category,
    this.sourceId,
  });

  final String id;
  final String label;
  final SourceCategory? category;
  final String? sourceId;
}

class _CategoryTabContent extends StatelessWidget {
  const _CategoryTabContent({
    required this.category,
    required this.future,
    required this.state,
  });

  final SourceCategory category;
  final Future<SourceCategory> future;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SourceCategory>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Text('分类加载失败：${snapshot.error}');
        }
        final apps = snapshot.data?.apps ?? const <AppListing>[];
        if (apps.isEmpty) {
          return const EmptyMessage(
            icon: Icons.apps_outage_outlined,
            title: '分类暂无应用',
            detail: '该源没有返回可用应用。',
          );
        }
        return Column(
          children: apps
              .asMap()
              .entries
              .map(
                (entry) => AppResultTile(
                  app: entry.value,
                  state: state,
                  onOpen: (app) => _showAppDetails(context, state, app),
                  showDivider: entry.key < apps.length - 1,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

enum _DownloadClearAction { all, completed }

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tasks = state.downloads;
    final completedCount = tasks
        .where((task) => task.status == DownloadStatus.completed)
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                '下载管理',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            PopupMenuButton<_DownloadClearAction>(
              enabled: tasks.isNotEmpty,
              tooltip: '清理下载',
              icon: const Icon(Icons.delete_sweep_outlined),
              onSelected: (action) =>
                  _confirmClearDownloads(context, state, action),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _DownloadClearAction.all,
                  child: Text('清除全部'),
                ),
                PopupMenuItem(
                  value: _DownloadClearAction.completed,
                  enabled: completedCount > 0,
                  child: Text('清除已下载'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (tasks.isEmpty)
          const EmptyMessage(
            icon: Icons.download_done_outlined,
            title: '暂无下载任务',
            detail: '从应用详情中选择文件后，任务会显示在这里。',
          )
        else
          ...tasks.asMap().entries.map(
            (entry) => _DownloadTaskTile(
              task: entry.value,
              state: state,
              showDivider: entry.key < tasks.length - 1,
            ),
          ),
      ],
    );
  }
}

Future<void> _confirmClearDownloads(
  BuildContext context,
  AppState state,
  _DownloadClearAction action,
) async {
  final completedOnly = action == _DownloadClearAction.completed;
  final count = state.downloads
      .where(
        (task) => !completedOnly || task.status == DownloadStatus.completed,
      )
      .length;
  if (count == 0) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(completedOnly ? '清除已下载文件？' : '清除全部下载？'),
      content: Text(
        completedOnly
            ? '将删除 $count 个已下载文件及其记录。'
            : '将删除 $count 个下载文件及其记录，进行中的任务也会取消。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await state.clearDownloads(completedOnly: completedOnly);
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.state,
    this.showDivider = true,
  });
  final DownloadTask task;
  final AppState state;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (task.status) {
      DownloadStatus.downloading => (Icons.downloading, scheme.primary),
      DownloadStatus.paused => (Icons.pause_circle_outline, scheme.tertiary),
      DownloadStatus.completed => (Icons.check_circle_outline, scheme.primary),
      DownloadStatus.failed => (Icons.error_outline, scheme.error),
      DownloadStatus.canceled => (Icons.cancel_outlined, scheme.outline),
    };
    final detail = _downloadTaskDetail(task);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Icon(icon, color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.file.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _downloadTaskControls(context, task, state),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 52,
            color: scheme.outlineVariant.withValues(alpha: .65),
          ),
      ],
    );
  }
}

Widget _downloadTaskControls(
  BuildContext context,
  DownloadTask task,
  AppState state,
) {
  switch (task.status) {
    case DownloadStatus.downloading:
    case DownloadStatus.paused:
      final paused = task.status == DownloadStatus.paused;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: LinearProgressIndicator(value: task.progress, minHeight: 4),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: paused ? '继续下载' : '暂停下载',
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            onPressed: () =>
                paused ? state.resumeDownload(task) : state.pauseDownload(task),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: '取消下载',
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            onPressed: () => state.cancelDownload(task),
            icon: const Icon(Icons.close),
          ),
        ],
      );
    case DownloadStatus.completed:
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          icon: const Icon(Icons.install_mobile_outlined),
          label: const Text('安装'),
          onPressed: () => _installDownloadTask(context, state, task),
        ),
      );
    case DownloadStatus.failed:
      return Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          tooltip: '重试下载',
          onPressed: () => state.retryDownload(task),
          icon: const Icon(Icons.refresh),
        ),
      );
    case DownloadStatus.canceled:
      return const SizedBox.shrink();
  }
}

String? _downloadTaskDetail(DownloadTask task) {
  switch (task.status) {
    case DownloadStatus.downloading:
      final total = task.total;
      final progress = total != null && total > 0
          ? '${_formatByteCount(task.received)} / ${_formatByteCount(total)} · ${((task.progress ?? 0) * 100).toStringAsFixed(0)}%'
          : task.received > 0
          ? '已下载 ${_formatByteCount(task.received)}'
          : '正在连接';
      final stats = <String>[];
      final speed = task.speedBytesPerSecond;
      if (speed != null && speed > 0) {
        stats.add('速度 ${_formatByteCount(speed)}/s');
      }
      final remaining = task.estimatedRemaining;
      if (remaining != null) {
        stats.add('预计 ${_formatDownloadDuration(remaining)}');
      }
      return [progress, ...stats].join(' · ');
    case DownloadStatus.paused:
      final progress = task.received > 0
          ? '已下载 ${_formatByteCount(task.received)}'
          : '尚未开始传输';
      return '已暂停 · $progress';
    case DownloadStatus.completed:
      return null;
    case DownloadStatus.failed:
      return '下载失败\n${task.error ?? '未知错误'}';
    case DownloadStatus.canceled:
      return '已取消';
  }
}

String _formatByteCount(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String _formatDownloadDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 1 ? 1 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = totalSeconds % 3600 ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return minutes > 0 ? '$hours 小时 $minutes 分钟' : '$hours 小时';
  }
  if (minutes > 0) {
    return seconds > 0 ? '$minutes 分钟 $seconds 秒' : '$minutes 分钟';
  }
  return '$seconds 秒';
}

Future<void> _installDownloadTask(
  BuildContext context,
  AppState state,
  DownloadTask task,
) async {
  try {
    final installed = await state.installTask(task);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(installed ? '已交给系统安装器' : '请完成系统安装权限设置后重试')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('安装失败：$error')));
  }
}

class SourcesPage extends StatelessWidget {
  const SourcesPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('源管理', style: Theme.of(context).textTheme.headlineMedium),
            FilledButton.icon(
              onPressed: () => _showAddSource(context),
              icon: const Icon(Icons.add),
              label: const Text('导入源'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Column(
          children: state.sources
              .map((source) => SourceTile(source: source, state: state))
              .toList(),
        ),
      ],
    );
  }

  void _showAddSource(BuildContext context) {
    final url = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var busy = false;
        String? error;

        return StatefulBuilder(
          builder: (dialogBuildContext, setDialogState) {
            Future<void> runImport(
              Future<SourceImportResult> Function() action,
            ) async {
              setDialogState(() {
                busy = true;
                error = null;
              });
              try {
                final result = await action();
                if (!dialogContext.mounted) return;
                if (result.imported.isEmpty) {
                  setDialogState(() {
                    error = result.failures.entries
                        .map((entry) => '${entry.key}: ${entry.value}')
                        .join('\n');
                  });
                  return;
                }
                Navigator.pop(dialogContext);
                final message = result.failures.isEmpty
                    ? '已导入 ${result.imported.length} 个源'
                    : '已导入 ${result.imported.length} 个源，失败 ${result.failures.length} 个';
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                }
              } catch (importError) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  error = importError.toString();
                });
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    busy = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('导入源'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: url,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: '源 URL',
                        hintText: 'https://example.com/source.js',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => runImport(() async {
                              final result = await FilePicker.platform
                                  .pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['js', 'zip'],
                                    allowMultiple: false,
                                    withData: true,
                                  );
                              if (result == null) {
                                return const SourceImportResult(
                                  imported: [],
                                  failures: {},
                                );
                              }
                              final file = result.files.single;
                              final bytes =
                                  file.bytes ?? await file.xFile.readAsBytes();
                              return state.importSourceBytes(bytes, file.name);
                            }),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('从系统文件选择 JS 或 ZIP'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(dialogBuildContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          if (url.text.trim().isEmpty) {
                            setDialogState(() {
                              error = '请输入源 URL';
                            });
                            return;
                          }
                          runImport(() => state.importSourceUrl(url.text));
                        },
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('从 URL 导入'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(url.dispose);
  }
}

class SourceTile extends StatelessWidget {
  const SourceTile({required this.source, required this.state, super.key});
  final ApkSource source;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final enabled = source.status == SourceStatus.enabled;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Icon(
                  source.builtIn ? Icons.inventory_2_outlined : Icons.code,
                ),
              ),
              title: Text(source.name),
              subtitle: Text(
                '${source.description}\n${source.homepage} · v${source.version}',
              ),
              isThreeLine: false,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ChoiceChip(
                  label: const Text('主页'),
                  selected: source.homeSource,
                  onSelected: enabled
                      ? (selected) {
                          if (selected) state.setHomeSource(source.id);
                        }
                      : null,
                ),
                if (!source.builtIn)
                  IconButton(
                    tooltip: '删除源',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => state.removeSource(source.id),
                  ),
                Switch(
                  value: enabled,
                  onChanged: (value) => state.toggleSource(source.id, value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
    children: [
      Text('设置', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 20),
      const ListTile(
        leading: Icon(Icons.download_outlined),
        title: Text('下载目录'),
        subtitle: Text('系统默认下载目录'),
      ),
      const Divider(),
      ListTile(
        leading: Icon(Icons.security_outlined),
        title: Text('安装权限'),
        subtitle: const Text('安装 APK 前需要允许本应用安装未知来源的应用'),
        trailing: state.host.supportsInstall
            ? IconButton(
                tooltip: '打开系统安装权限',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => state.host.requestInstallPermission(),
              )
            : null,
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.policy_outlined),
        title: Text('法律与安全'),
        subtitle: Text('请只导入你有权访问的站点源，并在安装前核验签名。'),
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('关于 APK Mesh'),
        subtitle: Text('开源源聚合客户端 · 0.1.0'),
      ),
    ],
  );
}

enum _DebugSection { overview, requests, webviews, projects, logs }

class DebugSheet extends StatefulWidget {
  const DebugSheet({required this.state, super.key});
  final AppState state;

  @override
  State<DebugSheet> createState() => _DebugSheetState();
}

class _DebugSheetState extends State<DebugSheet> {
  _DebugSection section = _DebugSection.overview;
  final Map<String, TextEditingController> _projectInputs = {};
  final Map<String, DebugProjectResult> _projectResults = {};
  final Set<String> _runningProjects = {};

  AppState get state => widget.state;

  @override
  void dispose() {
    for (final controller in _projectInputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _inputFor(SourceDebugProject project) =>
      _projectInputs.putIfAbsent(
        project.key,
        () => TextEditingController(text: project.defaultInput),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .9,
      minChildSize: .5,
      maxChildSize: .98,
      builder: (_, controller) => AnimatedBuilder(
        animation: state.debug,
        builder: (context, _) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '调试信息',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            '${state.debug.requests.length} 个请求 · ${state.debug.entries.length} 条日志',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '清空调试记录',
                      onPressed:
                          state.debug.entries.isEmpty &&
                              state.debug.requests.isEmpty
                          ? null
                          : state.debug.clear,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SegmentedButton<_DebugSection>(
                  segments: const [
                    ButtonSegment(
                      value: _DebugSection.overview,
                      label: Text('概览'),
                      icon: Icon(Icons.dashboard_outlined),
                    ),
                    ButtonSegment(
                      value: _DebugSection.requests,
                      label: Text('请求'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                    ButtonSegment(
                      value: _DebugSection.webviews,
                      label: Text('WebView'),
                      icon: Icon(Icons.web_outlined),
                    ),
                    ButtonSegment(
                      value: _DebugSection.projects,
                      label: Text('项目'),
                      icon: Icon(Icons.play_circle_outline),
                    ),
                    ButtonSegment(
                      value: _DebugSection.logs,
                      label: Text('日志'),
                      icon: Icon(Icons.notes_outlined),
                    ),
                  ],
                  selected: {section},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => section = value.first),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: _buildSection(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSection(BuildContext context) => switch (section) {
    _DebugSection.overview => _buildOverview(context),
    _DebugSection.requests => _buildRequests(context),
    _DebugSection.webviews => _buildWebviews(context),
    _DebugSection.projects => _buildProjects(context),
    _DebugSection.logs => _buildLogs(context),
  };

  List<Widget> _buildOverview(BuildContext context) {
    final requests = state.debug.requests.reversed.take(4).toList();
    final tabs = state.host.browserTabs;
    final logs = state.debug.entries.reversed.take(5).toList();
    return [
      Text('运行时', style: Theme.of(context).textTheme.titleMedium),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          state.sourceRuntimeReady
              ? Icons.check_circle_outline
              : Icons.warning_amber_outlined,
        ),
        title: Text(state.sourceRuntimeReady ? 'QuickJS 源已加载' : '使用演示源'),
        subtitle: Text(
          state.runtimeError ??
              '已启用源：${state.sources.where((source) => source.status == SourceStatus.enabled).map((source) => source.name).join('、')}',
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.web_outlined),
        title: Text('WebView：${state.host.supportsBrowser ? '可用' : '不可用'}'),
        subtitle: Text(
          '活动标签 ${tabs.where((tab) => tab.active).length} 个 · 安装能力：${state.host.supportsInstall ? '可用' : '不可用'}',
        ),
      ),
      const SizedBox(height: 8),
      Text('WebView 状态', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      if (tabs.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.web_asset_off_outlined),
          title: Text('暂无 WebView 标签'),
          subtitle: Text('调试项目运行后可点击标签查看页面。'),
        )
      else
        ...tabs
            .take(3)
            .map(
              (tab) => _DebugTabTile(
                tab: tab,
                onTap: () => _showWebView(context, tab),
              ),
            ),
      const SizedBox(height: 8),
      Row(
        children: [
          Text('最近请求', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${state.debug.requests.length} 个'),
        ],
      ),
      if (requests.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.swap_horiz_outlined),
          title: Text('暂无请求'),
        )
      else
        ...requests.map(
          (request) => _DebugRequestTile(
            request: request,
            onTap: () => _showRequest(context, request),
          ),
        ),
      const SizedBox(height: 8),
      Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
      if (logs.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.article_outlined),
          title: Text('暂无日志'),
        )
      else
        ...logs.map((entry) => _DebugLogTile(entry: entry)),
    ];
  }

  List<Widget> _buildRequests(BuildContext context) {
    final requests = state.debug.requests.reversed.toList();
    return [
      Row(
        children: [
          Text('请求记录', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${requests.length} 个 · 点击查看内容'),
        ],
      ),
      const SizedBox(height: 8),
      if (requests.isEmpty)
        const EmptyMessage(
          icon: Icons.swap_horiz_outlined,
          title: '暂无请求记录',
          detail: '运行搜索项目或应用搜索后，请求会出现在这里。',
        )
      else
        ...requests.map(
          (request) => _DebugRequestTile(
            request: request,
            onTap: () => _showRequest(context, request),
          ),
        ),
    ];
  }

  List<Widget> _buildWebviews(BuildContext context) {
    final tabs = state.host.browserTabs;
    return [
      Row(
        children: [
          Text('WebView 状态', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${tabs.length} 个'),
        ],
      ),
      const SizedBox(height: 8),
      if (tabs.isEmpty)
        const EmptyMessage(
          icon: Icons.web_asset_off_outlined,
          title: '暂无 WebView 标签',
          detail: '运行“获取应用详情”项目后，可以点开对应标签进行可视化查看。',
        )
      else
        ...tabs.map(
          (tab) =>
              _DebugTabTile(tab: tab, onTap: () => _showWebView(context, tab)),
        ),
    ];
  }

  List<Widget> _buildProjects(BuildContext context) {
    final projects = state.debugProjects;
    return [
      Row(
        children: [
          Text('调试项目', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${projects.length} 个'),
        ],
      ),
      const SizedBox(height: 8),
      if (projects.isEmpty)
        const EmptyMessage(
          icon: Icons.play_disabled_outlined,
          title: '源未声明调试项目',
          detail: '源可以在 manifest.debugProjects 中声明可触发的调试流程。',
        )
      else
        ...projects.map((project) => _DebugProjectTile(project: project)),
    ];
  }

  List<Widget> _buildLogs(BuildContext context) {
    final logs = state.debug.entries.reversed.toList();
    return [
      Row(
        children: [
          Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${logs.length} 条'),
        ],
      ),
      const SizedBox(height: 8),
      if (logs.isEmpty)
        const EmptyMessage(
          icon: Icons.article_outlined,
          title: '暂无日志',
          detail: '执行搜索、详情或调试项目后，运行事件会显示在这里。',
        )
      else
        ...logs.map((entry) => _DebugLogTile(entry: entry)),
    ];
  }

  Future<void> _runProject(SourceDebugProject project) async {
    final controller = _inputFor(project);
    final input = controller.text.trim().isEmpty
        ? project.defaultInput.trim()
        : controller.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入${project.inputLabel}')));
      return;
    }
    setState(() => _runningProjects.add(project.key));
    try {
      final result = await state.runDebugProject(project, input);
      if (mounted) {
        setState(() {
          _projectResults[project.key] = result;
          _runningProjects.remove(project.key);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _runningProjects.remove(project.key));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('调试项目失败：$error')));
      }
    }
  }

  void _showRequest(BuildContext context, DebugRequestEntry request) {
    showDialog<void>(
      context: context,
      builder: (_) => _DebugRequestDialog(request: request),
    );
  }

  void _showWebView(BuildContext context, BrowserTabDebugInfo tab) {
    showDialog<void>(
      context: context,
      builder: (_) => _DebugWebViewDialog(state: state, tab: tab),
    );
  }
}

class _DebugProjectTile extends StatelessWidget {
  const _DebugProjectTile({required this.project});
  final SourceDebugProject project;

  @override
  Widget build(BuildContext context) {
    final sheet = context.findAncestorStateOfType<_DebugSheetState>()!;
    final input = sheet._inputFor(project);
    final running = sheet._runningProjects.contains(project.key);
    final result = sheet._projectResults[project.key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline),
            title: Text(project.name),
            subtitle: Text('${project.sourceName}\n${project.description}'),
            isThreeLine: true,
          ),
          TextField(
            controller: input,
            enabled: !running,
            decoration: InputDecoration(
              labelText: project.inputLabel,
              hintText: project.placeholder,
              suffixIcon: IconButton(
                tooltip: '运行调试项目',
                onPressed: running ? null : () => sheet._runProject(project),
                icon: running
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
              ),
            ),
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(result.title),
                subtitle: SelectableText(
                  '${result.summary}\n${_prettyDebugValue(result.data)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DebugRequestTile extends StatelessWidget {
  const _DebugRequestTile({required this.request, required this.onTap});
  final DebugRequestEntry request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (request.state) {
      DebugRequestState.pending => scheme.tertiary,
      DebugRequestState.completed => scheme.primary,
      DebugRequestState.failed => scheme.error,
    };
    final status =
        request.statusCode?.toString() ??
        switch (request.state) {
          DebugRequestState.pending => '进行中',
          DebugRequestState.completed => '完成',
          DebugRequestState.failed => '失败',
        };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        request.state == DebugRequestState.failed
            ? Icons.error_outline
            : Icons.swap_horiz_outlined,
        color: color,
      ),
      title: Text('${request.method} $status'),
      subtitle: Text(
        '${request.url}\n${request.duration?.inMilliseconds ?? 0} ms · ${request.responseBody?.length ?? 0} 字符',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _DebugRequestDialog extends StatelessWidget {
  const _DebugRequestDialog({required this.request});
  final DebugRequestEntry request;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      child: SizedBox(
        width: size.width > 760 ? 700 : size.width * .92,
        height: size.height * .82,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${request.method} ${request.statusCode ?? '请求'}',
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(request.url),
                ),
              ),
              const SizedBox(height: 8),
              const TabBar(
                tabs: [
                  Tab(text: '响应内容'),
                  Tab(text: '请求详情'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _DebugBodyView(
                      body: request.responseBody ?? request.error ?? '暂无响应内容',
                    ),
                    _DebugMetadataView(request: request),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugBodyView extends StatelessWidget {
  const _DebugBodyView({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: SelectableText(
      _formatDebugBody(body),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );
}

class _DebugMetadataView extends StatelessWidget {
  const _DebugMetadataView({required this.request});
  final DebugRequestEntry request;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('请求头', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SelectableText(_formatHeaders(request.requestHeaders)),
      const SizedBox(height: 16),
      Text('响应头', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SelectableText(_formatHeaders(request.responseHeaders)),
      const SizedBox(height: 16),
      Text('状态', style: Theme.of(context).textTheme.titleSmall),
      SelectableText(
        '${request.state.name} · ${request.duration?.inMilliseconds ?? 0} ms${request.error == null ? '' : '\n${request.error}'}',
      ),
    ],
  );
}

class _DebugWebViewDialog extends StatefulWidget {
  const _DebugWebViewDialog({required this.state, required this.tab});
  final AppState state;
  final BrowserTabDebugInfo tab;

  @override
  State<_DebugWebViewDialog> createState() => _DebugWebViewDialogState();
}

class _DebugWebViewDialogState extends State<_DebugWebViewDialog> {
  String status = '正在加载';
  BrowserTabViewHandle? _tabView;

  @override
  void initState() {
    super.initState();
    _tabView = widget.state.host.browserTabView(widget.tab.id);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final canView =
        widget.state.host.supportsBrowser &&
        (widget.tab.url.startsWith('http://') ||
            widget.tab.url.startsWith('https://'));
    final attachedTab = _tabView;
    return Dialog(
      child: SizedBox(
        width: size.width > 900 ? 840 : size.width * .94,
        height: size.height * .84,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.web_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WebView 可视化查看',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${widget.tab.active ? '活动' : '历史'} · $status',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(widget.tab.url, maxLines: 2),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: canView
                  ? InAppWebView(
                      headlessWebView: attachedTab?.headlessWebView,
                      keepAlive: attachedTab?.keepAlive,
                      initialUrlRequest: attachedTab == null
                          ? URLRequest(url: WebUri(widget.tab.url))
                          : null,
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        incognito: true,
                      ),
                      shouldOverrideUrlLoading: attachedTab == null
                          ? null
                          : (_, action) async {
                              final next = action.request.url;
                              if (next == null ||
                                  !attachedTab.policy.permits(next)) {
                                return NavigationActionPolicy.CANCEL;
                              }
                              return NavigationActionPolicy.ALLOW;
                            },
                      shouldInterceptRequest: attachedTab == null
                          ? null
                          : (_, request) async {
                              final resource = request.url;
                              if ((resource.scheme == 'http' ||
                                      resource.scheme == 'https') &&
                                  !attachedTab.policy.permits(resource)) {
                                return WebResourceResponse(
                                  statusCode: 403,
                                  reasonPhrase: 'Source domain is not allowed',
                                  contentType: 'text/plain',
                                  data: Uint8List.fromList(
                                    utf8.encode('blocked by source policy'),
                                  ),
                                );
                              }
                              return null;
                            },
                      onWebViewCreated: attachedTab == null
                          ? null
                          : (controller) =>
                                widget.state.host.browserAdoptController(
                                  widget.tab.id,
                                  controller,
                                ),
                      onLoadStart: (_, _) {
                        if (mounted) setState(() => status = '加载中');
                      },
                      onLoadStop: (_, _) {
                        if (mounted) setState(() => status = '已加载');
                      },
                      onReceivedError: (_, _, _) {
                        if (mounted) setState(() => status = '加载失败');
                      },
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('当前平台不支持可视化 WebView，仅保留标签和操作记录。'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugTabTile extends StatelessWidget {
  const _DebugTabTile({required this.tab, required this.onTap});
  final BrowserTabDebugInfo tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = tab.active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        tab.active ? Icons.web : Icons.web_asset_off_outlined,
        color: color,
      ),
      title: Text('${tab.active ? '活动' : '已关闭'} · ${tab.state}'),
      subtitle: Text(
        '${tab.url}\n${tab.id} · ${_formatDebugTime(tab.startedAt)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: const Icon(Icons.open_in_new),
    );
  }
}

class _DebugLogTile extends StatelessWidget {
  const _DebugLogTile({required this.entry});
  final DebugLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      DebugLogLevel.error => Theme.of(context).colorScheme.error,
      DebugLogLevel.warning => Theme.of(context).colorScheme.tertiary,
      DebugLogLevel.info => Theme.of(context).colorScheme.primary,
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.level == DebugLogLevel.error
            ? Icons.error_outline
            : Icons.notes_outlined,
        color: color,
      ),
      title: Text(entry.message),
      subtitle: Text('${entry.category} · ${_formatDebugTime(entry.time)}'),
    );
  }
}

String _formatHeaders(Map<String, String> headers) {
  if (headers.isEmpty) return '无';
  return headers.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join('\\n');
}

String _formatDebugBody(String body) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
  } catch (_) {
    return body;
  }
}

String _prettyDebugValue(dynamic value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String _formatDebugTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class DetailsSheet extends StatefulWidget {
  const DetailsSheet({required this.app, required this.state, super.key});
  final AppListing app;
  final AppState state;

  @override
  State<DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<DetailsSheet> {
  AppDetails? detail;
  List<SourceDownloadProgress> downloads = const [];
  DetailLoadPhase phase = DetailLoadPhase.loadingDetails;
  String? error;
  bool _openingBrowser = false;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    if (app is AppDetails) {
      detail = app;
      downloads = app.downloads
          .map(
            (file) => SourceDownloadProgress(
              candidate: SourceDownloadCandidate(
                label: file.label,
                url: file.url,
                size: file.size,
                headers: file.headers,
              ),
              files: [file],
            ),
          )
          .toList(growable: false);
      phase = DetailLoadPhase.complete;
    } else {
      unawaited(_loadDetails());
    }
  }

  Future<void> _loadDetails() async {
    try {
      await widget.state.loadDetails(
        widget.app,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            detail = progress.details;
            downloads = progress.downloads;
            phase = progress.phase;
            error = progress.error;
          });
        },
      );
    } catch (value) {
      if (!mounted) return;
      setState(() => error = value.toString());
    }
  }

  Future<void> _openInBrowser() async {
    if (_openingBrowser) return;
    final url = (detail?.id ?? widget.app.id).trim();
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _showDetailsMessage('当前应用没有可打开的网页地址');
      return;
    }

    late final SourcePolicy policy;
    try {
      policy = widget.state.registry.scriptFor(widget.app.sourceId).policy;
    } catch (value) {
      _showDetailsMessage('无法读取源权限：$value');
      return;
    }
    if (!policy.allowBrowser || !policy.permits(uri)) {
      _showDetailsMessage('该源不允许打开此网页');
      return;
    }

    setState(() => _openingBrowser = true);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('系统没有可用的浏览器');
    } catch (value) {
      if (mounted) _showDetailsMessage('浏览器打开失败：$value');
    } finally {
      if (mounted) setState(() => _openingBrowser = false);
    }
  }

  Future<void> _switchSource() async {
    final query = (detail?.name ?? widget.app.name).trim();
    if (query.isEmpty) {
      _showDetailsMessage('当前应用没有可用于搜索的名称');
      return;
    }

    final selected = await showModalBottomSheet<AppListing>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SourceMatchSheet(
        query: query,
        current: widget.app,
        state: widget.state,
      ),
    );
    if (!mounted || selected == null) return;
    _showAppDetails(context, widget.state, selected);
  }

  void _showDetailsMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final displayApp = detail ?? widget.app;
    final metadataChips = buildAppInfoChips(
      displayApp,
      onPackageTap: displayApp.packageName.trim().isEmpty
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => PackageLookupSheet(
                packageName: displayApp.packageName,
                state: widget.state,
                onAppTap: (app) => _showAppDetails(context, widget.state, app),
              ),
            ),
    );
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .45,
        maxChildSize: .94,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                AppIcon(url: displayApp.iconUrl),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayApp.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (metadataChips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _FadingHorizontalChips(children: metadataChips),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (detail == null && error == null)
              const _SearchLoadingView(
                icon: Icons.article_outlined,
                label: '正在加载详情',
              ),
            if (error != null)
              Text(detail == null ? '源详情加载失败：$error' : '下载链接解析失败：$error'),
            if (detail != null) ..._buildDetailContent(context, detail!),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '浏览器打开',
          onPressed: _openingBrowser ? null : _openInBrowser,
          icon: _openingBrowser
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_browser_outlined),
        ),
        IconButton(
          tooltip: '切换源',
          onPressed: _switchSource,
          icon: const Icon(Icons.swap_horiz),
        ),
      ],
    );
  }

  List<Widget> _buildDetailContent(BuildContext context, AppDetails detail) {
    final content = <Widget>[_buildDetailActions(context)];
    content.add(const SizedBox(height: 8));
    if (detail.description.trim().isNotEmpty) {
      content.add(_ExpandableDescription(text: detail.description));
      content.add(const SizedBox(height: 20));
    }
    if (detail.screenshots.isNotEmpty) {
      content.add(Text('截图', style: Theme.of(context).textTheme.titleMedium));
      content.add(const SizedBox(height: 8));
      content.add(_ScreenshotGallery(urls: detail.screenshots));
      content.add(const SizedBox(height: 20));
    }
    if (downloads.isNotEmpty || phase == DetailLoadPhase.resolvingDownloads) {
      content.add(
        Row(
          children: [
            Expanded(
              child: Text(
                '下载文件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (phase == DetailLoadPhase.resolvingDownloads &&
                downloads.isNotEmpty)
              Text(
                '${downloads.where((item) => item.completed).length}/${downloads.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      );
      content.add(const SizedBox(height: 8));
      if (downloads.isEmpty) {
        content.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('正在查找下载项…'),
          ),
        );
      } else {
        final rows = <Widget>[];
        for (final progress in downloads) {
          final files = progress.files;
          if (files != null && files.isNotEmpty) {
            rows.addAll(
              files.map(
                (file) => _SourceDownloadTile(
                  file: file,
                  sourceId: widget.app.sourceId,
                  state: widget.state,
                  showDivider: true,
                ),
              ),
            );
          } else {
            rows.add(_PendingSourceDownloadTile(progress: progress));
          }
        }
        for (var index = 0; index < rows.length; index += 1) {
          if (rows[index] is _SourceDownloadTile) {
            final tile = rows[index] as _SourceDownloadTile;
            rows[index] = _SourceDownloadTile(
              file: tile.file,
              sourceId: tile.sourceId,
              state: tile.state,
              showDivider: index < rows.length - 1,
            );
          }
        }
        content.addAll(rows);
      }
    }
    if (detail.comments.isNotEmpty) {
      if (content.isNotEmpty) content.add(const SizedBox(height: 20));
      content.add(Text('评论', style: Theme.of(context).textTheme.titleMedium));
      content.addAll(
        detail.comments.map(
          (comment) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.comment_outlined),
            title: Text(comment),
          ),
        ),
      );
    }
    return content;
  }
}

class _FadingHorizontalChips extends StatefulWidget {
  const _FadingHorizontalChips({required this.children});

  final List<Widget> children;

  @override
  State<_FadingHorizontalChips> createState() => _FadingHorizontalChipsState();
}

class _FadingHorizontalChipsState extends State<_FadingHorizontalChips> {
  late final ScrollController _controller;
  bool _fadeLeft = false;
  bool _fadeRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateFadeEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFadeEdges());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateFadeEdges)
      ..dispose();
    super.dispose();
  }

  void _updateFadeEdges() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final fadeLeft = position.pixels > 0.5;
    final fadeRight = position.pixels < position.maxScrollExtent - 0.5;
    if (!mounted || (fadeLeft == _fadeLeft && fadeRight == _fadeRight)) {
      return;
    }
    setState(() {
      _fadeLeft = fadeLeft;
      _fadeRight = fadeRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chips = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          for (var index = 0; index < widget.children.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            widget.children[index],
          ],
        ],
      ),
    );
    if (!_fadeLeft && !_fadeRight) {
      return SizedBox(height: 40, child: chips);
    }

    final colors = _fadeLeft && _fadeRight
        ? <Color>[
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ]
        : _fadeLeft
        ? <Color>[Colors.transparent, Colors.black, Colors.black]
        : <Color>[Colors.black, Colors.black, Colors.transparent];
    final stops = _fadeLeft && _fadeRight
        ? const [0.0, 0.08, 0.92, 1.0]
        : _fadeLeft
        ? const [0.0, 0.08, 1.0]
        : const [0.0, 0.92, 1.0];
    return SizedBox(
      height: 40,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) =>
            LinearGradient(colors: colors, stops: stops).createShader(bounds),
        child: chips,
      ),
    );
  }
}

class _SourceMatchSheet extends StatefulWidget {
  const _SourceMatchSheet({
    required this.query,
    required this.current,
    required this.state,
  });

  final String query;
  final AppListing current;
  final AppState state;

  @override
  State<_SourceMatchSheet> createState() => _SourceMatchSheetState();
}

class _SourceMatchSheetState extends State<_SourceMatchSheet> {
  final _listKey = GlobalKey<AnimatedListState>();
  final _seen = <String>{};
  final _sourceErrors = <String, String>{};
  final _matches = <AppListing>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    try {
      await widget.state.searchPage(
        widget.query,
        page: 1,
        onSourcePage: _handleSourcePage,
      );
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (value) {
      if (!mounted) return;
      setState(() => _loading = false);
      _sourceErrors['search'] = value.toString();
    }
  }

  void _handleSourcePage(SourceSearchPage page) {
    if (!page.succeeded) {
      _sourceErrors[page.sourceName] = page.error ?? '源搜索失败';
      return;
    }
    for (final app in page.results) {
      final key = '${app.sourceId}:${app.id}';
      final isCurrent =
          app.sourceId == widget.current.sourceId &&
          app.id == widget.current.id;
      if (isCurrent ||
          app.name.trim() != widget.query ||
          !_seen.add(key) ||
          !mounted) {
        continue;
      }
      final index = _matches.length;
      setState(() => _matches.add(app));
      _listKey.currentState?.insertItem(
        index,
        duration: const Duration(milliseconds: 260),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .68,
        minChildSize: .38,
        maxChildSize: .94,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '切换源',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  widget.query,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 3,
              child: _loading
                  ? const LinearProgressIndicator(minHeight: 3)
                  : const SizedBox.shrink(),
            ),
            Expanded(child: _buildResults(controller)),
            if (!_loading && _sourceErrors.isNotEmpty && _matches.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  '部分源搜索失败：${_sourceErrors.keys.join('、')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ScrollController controller) {
    if (_matches.isEmpty) {
      if (_loading) {
        return const _SearchLoadingView(
          icon: Icons.manage_search,
          label: '正在搜索',
        );
      }
      final failed = _sourceErrors.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(failed ? Icons.error_outline : Icons.search_off, size: 48),
              const SizedBox(height: 12),
              Text(
                failed ? '同名应用搜索失败' : '没有找到完全同名的应用',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                failed ? _sourceErrors.values.join('\n') : '仅展示所有启用源的第一页结果。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedList(
      key: _listKey,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      initialItemCount: _matches.length,
      itemBuilder: (context, index, animation) {
        final app = _matches[index];
        return SizeTransition(
          sizeFactor: animation,
          child: AppResultTile(
            app: app,
            state: widget.state,
            onOpen: (selected) => Navigator.of(context).pop(selected),
            showDivider: index < _matches.length - 1,
          ),
        );
      },
    );
  }
}

class _PendingSourceDownloadTile extends StatelessWidget {
  const _PendingSourceDownloadTile({required this.progress});

  final SourceDownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = progress.error != null;
    final empty = progress.files != null && progress.files!.isEmpty;
    final detail =
        progress.error ?? (empty ? '未找到可用下载链接' : progress.candidate.size);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 40,
            child: Align(
              alignment: Alignment.topLeft,
              child: failed
                  ? SizedBox.square(
                      dimension: 22,
                      child: Icon(Icons.error_outline, color: scheme.error),
                    )
                  : progress.resolving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : SizedBox.square(
                      dimension: 22,
                      child: Icon(
                        Icons.link_off_outlined,
                        color: scheme.outline,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress.candidate.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text});
  final String text;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = DefaultTextStyle.of(context).style;
        final scheme = Theme.of(context).colorScheme;
        final suffixStyle = textStyle.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        );
        final direction = Directionality.of(context);
        final fullPainter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          maxLines: 3,
          textDirection: direction,
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = fullPainter.didExceedMaxLines;
        final span = expanded || !canExpand
            ? TextSpan(text: widget.text, style: textStyle)
            : _collapsedSpan(
                textStyle: textStyle,
                suffixStyle: suffixStyle,
                direction: direction,
                maxWidth: constraints.maxWidth > 16
                    ? constraints.maxWidth - 16
                    : constraints.maxWidth,
              );
        final text = AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Text.rich(
            span,
            maxLines: expanded || !canExpand ? null : 3,
            overflow: TextOverflow.clip,
          ),
        );
        if (!canExpand) return text;
        return Material(
          color: scheme.surfaceContainerLow.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(padding: const EdgeInsets.all(8), child: text),
          ),
        );
      },
    );
  }

  TextSpan _collapsedSpan({
    required TextStyle textStyle,
    required TextStyle suffixStyle,
    required TextDirection direction,
    required double maxWidth,
  }) {
    const suffix = '... 点击展开';
    final codePoints = widget.text.runes.toList();

    bool fits(int count) {
      final prefix = String.fromCharCodes(codePoints.take(count));
      final painter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: prefix, style: textStyle),
            TextSpan(text: suffix, style: suffixStyle),
          ],
        ),
        maxLines: 3,
        textDirection: direction,
      )..layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines;
    }

    var low = 0;
    var high = codePoints.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (fits(middle)) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return TextSpan(
      children: [
        TextSpan(
          text: String.fromCharCodes(codePoints.take(low)).trimRight(),
          style: textStyle,
        ),
        TextSpan(text: suffix, style: suffixStyle),
      ],
    );
  }
}

class _ScreenshotGallery extends StatelessWidget {
  const _ScreenshotGallery({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _ScreenshotThumbnail(
          url: urls[index],
          onTap: () => _showScreenshot(context, index),
        ),
      ),
    );
  }

  void _showScreenshot(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (_) => _ScreenshotViewer(urls: urls, initialIndex: index),
    );
  }
}

class _ScreenshotThumbnail extends StatefulWidget {
  const _ScreenshotThumbnail({required this.url, required this.onTap});
  final String url;
  final VoidCallback onTap;

  @override
  State<_ScreenshotThumbnail> createState() => _ScreenshotThumbnailState();
}

class _ScreenshotThumbnailState extends State<_ScreenshotThumbnail> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double _aspectRatio = 1;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _ScreenshotThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _removeImageListener();
      _aspectRatio = 1;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final stream = NetworkImage(widget.url).resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      final image = info.image;
      if (!mounted || image.height == 0) return;
      final ratio = image.width / image.height;
      if ((ratio - _aspectRatio).abs() > .01) {
        setState(() => _aspectRatio = ratio);
      }
    });
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (190 * _aspectRatio).clamp(112.0, 360.0);
    return SizedBox(
      width: width,
      height: 190,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}

class _ScreenshotViewer extends StatefulWidget {
  const _ScreenshotViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_ScreenshotViewer> createState() => _ScreenshotViewerState();
}

class _ScreenshotViewerState extends State<_ScreenshotViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_currentIndex + 1} / ${widget.urls.length}'),
          actions: [
            IconButton(
              tooltip: '保存图片',
              onPressed: _saving ? null : _saveCurrent,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        body: PhotoViewGallery.builder(
          pageController: _pageController,
          itemCount: widget.urls.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          loadingBuilder: (context, event) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          builder: (context, index) => PhotoViewGalleryPageOptions(
            imageProvider: NetworkImage(widget.urls[index]),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained * .8,
            maxScale: PhotoViewComputedScale.covered * 3,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCurrent() async {
    setState(() => _saving = true);
    try {
      final response = await http.get(Uri.parse(widget.urls[_currentIndex]));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('图片请求失败：HTTP ${response.statusCode}');
      }
      await Gal.putImageBytes(
        response.bodyBytes,
        album: 'APK Mesh',
        name: _imageName(widget.urls[_currentIndex], _currentIndex),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已保存到系统相册')));
    } on GalException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存图片失败：${error.toString()}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存图片失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _imageName(String url, int index) {
    final path = Uri.tryParse(url)?.path ?? '';
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    final last = parts.isEmpty ? null : parts.last;
    final base = (last ?? '')
        .replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return base.isEmpty ? 'apkmesh_screenshot_${index + 1}' : 'apkmesh_$base';
  }
}

class _SourceDownloadTile extends StatelessWidget {
  const _SourceDownloadTile({
    required this.file,
    required this.sourceId,
    required this.state,
    this.showDivider = true,
  });

  final SourceDownload file;
  final String sourceId;
  final AppState state;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final task = state.downloadFor(file.url);
        final taskDetail = task == null ? null : _downloadTaskDetail(task);
        final detail = task == null ? file.size.trim() : (taskDetail ?? '');
        final (icon, color) = switch (task?.status) {
          DownloadStatus.completed => (
            Icons.check_circle_outline,
            scheme.primary,
          ),
          DownloadStatus.paused => (
            Icons.pause_circle_outline,
            scheme.tertiary,
          ),
          DownloadStatus.canceled => (Icons.cancel_outlined, scheme.outline),
          DownloadStatus.failed => (Icons.error_outline, scheme.error),
          _ => (Icons.file_download_outlined, scheme.primary),
        };

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Icon(icon, color: color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: task == null
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _downloadTitle(context, file.label),
                                    if (detail.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      _downloadDetail(context, detail, scheme),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              _downloadButton(context),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _downloadTitle(context, file.label),
                              if (detail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _downloadDetail(context, detail, scheme),
                              ],
                              const SizedBox(height: 8),
                              _downloadTaskControls(context, task, state),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              Divider(
                height: 1,
                indent: 52,
                color: scheme.outlineVariant.withValues(alpha: .65),
              ),
          ],
        );
      },
    );
  }

  Widget _downloadTitle(BuildContext context, String label) {
    return Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _downloadDetail(
    BuildContext context,
    String detail,
    ColorScheme scheme,
  ) {
    return Text(
      detail,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    );
  }

  Widget _downloadButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: () {
          state.startDownload(file, sourceId);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已开始下载，可在下载页查看进度')));
        },
        icon: const Icon(Icons.download),
        label: const Text('下载'),
      ),
    );
  }
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({
    required this.icon,
    required this.title,
    required this.detail,
    super.key,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  );
}
