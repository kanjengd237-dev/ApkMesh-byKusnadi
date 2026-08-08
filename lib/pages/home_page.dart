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
      } catch (_) {}
      return;
    }
    await _loadHome(force: true);
  }

  List<ContentTab> get _tabs {
    if (submittedQuery == null) {
      return [
        const ContentTab(id: 'home', label: '主页'),
        ...home.categories.map(
          (category) => ContentTab(
            id: 'category:${category.sourceId}:${category.id}',
            label: category.name,
            category: category,
          ),
        ),
      ];
    }
    return [
      const ContentTab(id: 'all', label: '全部源'),
      ...widget.state.sources
          .where((source) => source.status == SourceStatus.enabled)
          .map(
            (source) => ContentTab(
              id: 'source:${source.id}',
              label: source.name,
              sourceId: source.id,
            ),
          ),
    ];
  }

  ContentTab _activeTab(List<ContentTab> tabs) {
    for (final tab in tabs) {
      if (tab.id == _selectedTab) return tab;
    }
    return tabs.first;
  }

  Widget _buildTabBar(
    BuildContext context,
    List<ContentTab> tabs,
    ContentTab activeTab,
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

  List<Widget> _buildHomeContent(BuildContext context, ContentTab activeTab) {
    if (homeLoading && !homeLoaded) {
      return const [
        SearchLoadingView(icon: Icons.home_outlined, label: '正在加载首页'),
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
        CategoryTabContent(
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
          onOpen: (app) => showAppDetails(context, widget.state, app),
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
      itemBuilder: (context, index, animation) {
        final easedAnimation = animation.drive(
          CurveTween(curve: Curves.easeOutCubic),
        );
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(easedAnimation);
        return SizeTransition(
          sizeFactor: easedAnimation,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: easedAnimation,
            child: SlideTransition(
              position: offsetAnimation,
              child: AppResultTile(
                app: results[index],
                state: widget.state,
                onOpen: (app) => showAppDetails(context, widget.state, app),
                showDivider: index < results.length - 1,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchStage(
    BuildContext context,
    ContentTab activeTab,
    List<AppListing> visibleResults,
  ) {
    final Widget stage;
    final Key stageKey;
    if (visibleResults.isNotEmpty) {
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
                          showAppDetails(context, widget.state, app),
                      showDivider: entry.key < visibleResults.length - 1,
                    ),
                  )
                  .toList(),
            );
      stage = resultList;
      stageKey = ValueKey('results:${activeTab.id}');
    } else if (loading) {
      stage = const SearchLoadingView();
      stageKey = const ValueKey('search-loading');
    } else {
      stage = EmptyMessage(
        icon: Icons.manage_search,
        title: '未找到结果',
        detail: error == null
            ? activeTab.sourceId == null
                  ? '已在所有启用的源中搜索“$submittedQuery”。'
                  : '当前源没有返回“$submittedQuery”的结果。'
            : '源请求未完成，请打开错误详情查看原因。',
      );
      stageKey = ValueKey('search-empty:${activeTab.id}:$submittedQuery');
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final easedAnimation = animation.drive(
          CurveTween(curve: Curves.easeOutCubic),
        );
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(easedAnimation);
        return FadeTransition(
          opacity: easedAnimation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: KeyedSubtree(key: stageKey, child: stage),
    );
  }

  List<Widget> _buildSearchContent(BuildContext context, ContentTab activeTab) {
    final visibleResults = activeTab.sourceId == null
        ? results
        : results.where((app) => app.sourceId == activeTab.sourceId).toList();
    return [
      _buildSearchStage(context, activeTab, visibleResults),
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
    this.category,
    this.sourceId,
  });

  final String id;
  final String label;
  final SourceCategory? category;
  final String? sourceId;
}

class CategoryTabContent extends StatelessWidget {
  const CategoryTabContent({
    required this.category,
    required this.future,
    required this.state,
    super.key,
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
                  onOpen: (app) => showAppDetails(context, state, app),
                  showDivider: entry.key < apps.length - 1,
                ),
              )
              .toList(),
        );
      },
    );
  }
}
