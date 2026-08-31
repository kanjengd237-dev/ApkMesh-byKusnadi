import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_state.dart';
import '../core/debug_log.dart';
import '../core/models.dart';
import '../core/source_runtime.dart';
import '../widgets/empty_message.dart';

class DebugSheet extends StatefulWidget {
  const DebugSheet({required this.state, super.key});
  final AppState state;

  @override
  State<DebugSheet> createState() => _DebugSheetState();
}

enum _DebugSection { overview, requests, webviews, projects, logs }

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
                            'Debug info',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            '${state.debug.requests.length} requests · ${state.debug.entries.length} logs',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Clear debug records',
                      onPressed:
                          state.debug.entries.isEmpty &&
                              state.debug.requests.isEmpty
                          ? null
                          : state.debug.clear,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                    IconButton(
                      tooltip: 'Close',
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
                      label: Text('Overview'),
                      icon: Icon(Icons.dashboard_outlined),
                    ),
                    ButtonSegment(
                      value: _DebugSection.requests,
                      label: Text('Requests'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                    ButtonSegment(
                      value: _DebugSection.webviews,
                      label: Text('WebView'),
                      icon: Icon(Icons.web_outlined),
                    ),
                    ButtonSegment(
                      value: _DebugSection.projects,
                      label: Text('Projects'),
                      icon: Icon(Icons.play_circle_outline),
                    ),
                    ButtonSegment(
                      value: _DebugSection.logs,
                      label: Text('Logs'),
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
      Text('Runtime', style: Theme.of(context).textTheme.titleMedium),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          state.sourceRuntimeReady
              ? Icons.check_circle_outline
              : Icons.warning_amber_outlined,
        ),
        title: Text(
          state.sourceRuntimeReady
              ? 'QuickJS source loaded'
              : 'Using demo source',
        ),
        subtitle: Text(
          state.runtimeError ??
              'Enabled sources: ${state.sources.where((source) => source.status == SourceStatus.enabled).map((source) => source.name).join(', ')}',
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.web_outlined),
        title: Text(
          'WebView: ${state.host.supportsBrowser ? 'Available' : 'Unavailable'}',
        ),
        subtitle: Text(
          '${tabs.where((tab) => tab.active).length} active tabs · Install capability: ${state.host.supportsInstall ? 'Available' : 'Unavailable'}',
        ),
      ),
      const SizedBox(height: 8),
      Text('WebView status', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      if (tabs.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.web_asset_off_outlined),
          title: Text('No WebView tabs'),
          subtitle: Text(
            'After running a debug project, you can tap a tab to view the page.',
          ),
        )
      else
        ...tabs
            .take(3)
            .map(
              (tab) => DebugTabTile(
                tab: tab,
                onTap: () => _showWebView(context, tab),
              ),
            ),
      const SizedBox(height: 8),
      Row(
        children: [
          Text(
            'Recent requests',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 8),
          Text('${state.debug.requests.length}'),
        ],
      ),
      if (requests.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.swap_horiz_outlined),
          title: Text('No requests'),
        )
      else
        ...requests.map(
          (request) => DebugRequestTile(
            request: request,
            onTap: () => _showRequest(context, request),
          ),
        ),
      const SizedBox(height: 8),
      Text('Runtime logs', style: Theme.of(context).textTheme.titleMedium),
      if (logs.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.article_outlined),
          title: Text('No logs'),
        )
      else
        ...logs.map((entry) => DebugLogTile(entry: entry)),
    ];
  }

  List<Widget> _buildRequests(BuildContext context) {
    final requests = state.debug.requests.reversed.toList();
    return [
      Row(
        children: [
          Text('Request log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${requests.length} · Tap to view'),
        ],
      ),
      const SizedBox(height: 8),
      if (requests.isEmpty)
        const EmptyMessage(
          icon: Icons.swap_horiz_outlined,
          title: 'No request records',
          detail:
              'Requests will appear here after running a search project or app search.',
        )
      else
        ...requests.map(
          (request) => DebugRequestTile(
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
          Text(
            'WebView status',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 8),
          Text('${tabs.length}'),
        ],
      ),
      const SizedBox(height: 8),
      if (tabs.isEmpty)
        const EmptyMessage(
          icon: Icons.web_asset_off_outlined,
          title: 'No WebView tabs',
          detail:
              'After running the "Get app details" project, you can open the corresponding tab for visual viewing.',
        )
      else
        ...tabs.map(
          (tab) =>
              DebugTabTile(tab: tab, onTap: () => _showWebView(context, tab)),
        ),
    ];
  }

  List<Widget> _buildProjects(BuildContext context) {
    final projects = state.debugProjects;
    return [
      Row(
        children: [
          Text(
            'Debug projects',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 8),
          Text('${projects.length}'),
        ],
      ),
      const SizedBox(height: 8),
      if (projects.isEmpty)
        const EmptyMessage(
          icon: Icons.play_disabled_outlined,
          title: 'No debug projects declared',
          detail:
              'Sources can declare triggerable debug flows in manifest.debugProjects.',
        )
      else
        ...projects.map((project) => DebugProjectTile(project: project)),
    ];
  }

  List<Widget> _buildLogs(BuildContext context) {
    final logs = state.debug.entries.reversed.toList();
    return [
      Row(
        children: [
          Text('Runtime logs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${logs.length}'),
        ],
      ),
      const SizedBox(height: 8),
      if (logs.isEmpty)
        const EmptyMessage(
          icon: Icons.article_outlined,
          title: 'No logs',
          detail:
              'After running a search, details, or debug project, runtime events will be displayed here.',
        )
      else
        ...logs.map((entry) => DebugLogTile(entry: entry)),
    ];
  }

  Future<void> _runProject(SourceDebugProject project) async {
    final controller = _inputFor(project);
    final input = controller.text.trim().isEmpty
        ? project.defaultInput.trim()
        : controller.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter ${project.inputLabel}')),
      );
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
        ).showSnackBar(SnackBar(content: Text('Debug project failed: $error')));
      }
    }
  }

  void _showRequest(BuildContext context, DebugRequestEntry request) {
    showDialog<void>(
      context: context,
      builder: (_) => DebugRequestDialog(request: request),
    );
  }

  void _showWebView(BuildContext context, BrowserTabDebugInfo tab) {
    showDialog<void>(
      context: context,
      builder: (_) => DebugWebViewDialog(state: state, tab: tab),
    );
  }
}

class DebugProjectTile extends StatelessWidget {
  const DebugProjectTile({required this.project, super.key});
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
                tooltip: 'Run debug project',
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
                  '${result.summary}\n${prettyDebugValue(result.data)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DebugRequestTile extends StatelessWidget {
  const DebugRequestTile({
    required this.request,
    required this.onTap,
    super.key,
  });
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
          DebugRequestState.pending => 'In progress',
          DebugRequestState.completed => 'Completed',
          DebugRequestState.failed => 'Failed',
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
        '${request.url}\n${request.duration?.inMilliseconds ?? 0} ms · ${request.responseBody?.length ?? 0} chars',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class DebugRequestDialog extends StatelessWidget {
  const DebugRequestDialog({required this.request, super.key});
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
                        '${request.method} ${request.statusCode ?? 'Request'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
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
                  Tab(text: 'Response'),
                  Tab(text: 'Request details'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    DebugBodyView(
                      body:
                          request.responseBody ??
                          request.error ??
                          'No response content',
                    ),
                    DebugMetadataView(request: request),
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

class DebugBodyView extends StatelessWidget {
  const DebugBodyView({required this.body, super.key});
  final String body;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: SelectableText(
      formatDebugBody(body),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );
}

class DebugMetadataView extends StatelessWidget {
  const DebugMetadataView({required this.request, super.key});
  final DebugRequestEntry request;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Request headers', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SelectableText(formatHeaders(request.requestHeaders)),
      const SizedBox(height: 16),
      Text('Response headers', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SelectableText(formatHeaders(request.responseHeaders)),
      const SizedBox(height: 16),
      Text('Status', style: Theme.of(context).textTheme.titleSmall),
      SelectableText(
        '${request.state.name} · ${request.duration?.inMilliseconds ?? 0} ms${request.error == null ? '' : '\n${request.error}'}',
      ),
    ],
  );
}

class DebugWebViewDialog extends StatefulWidget {
  const DebugWebViewDialog({required this.state, required this.tab, super.key});
  final AppState state;
  final BrowserTabDebugInfo tab;

  @override
  State<DebugWebViewDialog> createState() => _DebugWebViewDialogState();
}

class _DebugWebViewDialogState extends State<DebugWebViewDialog> {
  String status = 'Loading';
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
                          'WebView visual viewer',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${widget.tab.active ? 'Active' : 'History'} · $status',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
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
                        if (mounted) setState(() => status = 'Loading');
                      },
                      onLoadStop: (_, _) {
                        if (mounted) setState(() => status = 'Loaded');
                      },
                      onReceivedError: (_, _, _) {
                        if (mounted) setState(() => status = 'Load failed');
                      },
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Visual WebView is not supported on this platform; only tabs and operations are retained.',
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class DebugTabTile extends StatelessWidget {
  const DebugTabTile({required this.tab, required this.onTap, super.key});
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
      title: Text('${tab.active ? 'Active' : 'Closed'} · ${tab.state}'),
      subtitle: Text(
        '${tab.url}\n${tab.id} · ${formatDebugTime(tab.startedAt)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: const Icon(Icons.open_in_new),
    );
  }
}

class DebugLogTile extends StatelessWidget {
  const DebugLogTile({required this.entry, super.key});
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
      subtitle: Text('${entry.category} · ${formatDebugTime(entry.time)}'),
    );
  }
}

String formatHeaders(Map<String, String> headers) {
  if (headers.isEmpty) return 'None';
  return headers.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join('\n');
}

String formatDebugBody(String body) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
  } catch (_) {
    return body;
  }
}

String prettyDebugValue(dynamic value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String formatDebugTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
