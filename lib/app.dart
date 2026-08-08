import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'pages/debug_sheet.dart';
import 'pages/downloads_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/sources_page.dart';

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
  bool searchTranslationLoading = false;
  final searchController = TextEditingController();
  final homeKey = GlobalKey<HomePageState>();

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
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.horizontal,
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
              ),
              child: searchOpen
                  ? SizedBox(
                      key: const ValueKey('search-field'),
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
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              searchTranslationLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: '翻译为英文',
                                      onPressed: _translateSearch,
                                      icon: const Icon(
                                        Icons.translate_outlined,
                                        size: 20,
                                      ),
                                    ),
                              IconButton(
                                tooltip: '清空搜索',
                                onPressed: searchController.clear,
                                icon: const Icon(Icons.clear, size: 20),
                              ),
                            ],
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: const OutlineInputBorder(),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    )
                  : const Text('APK Mesh', key: ValueKey('app-title')),
            ),
            actions: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: searchOpen
                    ? IconButton(
                        key: const ValueKey('close-search'),
                        tooltip: '关闭搜索',
                        onPressed: () => setState(() => searchOpen = false),
                        icon: const Icon(Icons.close),
                      )
                    : IconButton(
                        key: const ValueKey('open-search'),
                        tooltip: '搜索',
                        onPressed: _openSearch,
                        icon: const Icon(Icons.search),
                      ),
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

  Future<void> _translateSearch() async {
    final query = searchController.text.trim();
    if (query.isEmpty || searchTranslationLoading) return;
    setState(() => searchTranslationLoading = true);
    try {
      final translated = await widget.state.translateToEnglish(query);
      if (mounted && searchController.text.trim() == query) {
        searchController.value = TextEditingValue(
          text: translated,
          selection: TextSelection.collapsed(offset: translated.length),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('翻译失败：$error')));
      }
    } finally {
      if (mounted) setState(() => searchTranslationLoading = false);
    }
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
