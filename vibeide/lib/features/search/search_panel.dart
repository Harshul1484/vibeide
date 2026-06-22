import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/editor/editor_provider.dart';
import 'package:vibeide/features/shell/shell_layout.dart';
import 'search_provider.dart';

// ── State providers ──────────────────────────────────────────────────────────

final _searchQueryProvider = StateProvider<String>((ref) => '');
final _searchCaseSensitiveProvider = StateProvider<bool>((ref) => false);
final _searchRegexProvider = StateProvider<bool>((ref) => false);
final _searchResultsProvider =
    StateProvider<SearchResults?>((ref) => null);
final _searchLoadingProvider = StateProvider<bool>((ref) => false);

// Tracks which file groups are collapsed: file path -> collapsed
final _collapsedFilesProvider =
    StateProvider<Set<String>>((ref) => const {});

// ── Panel ────────────────────────────────────────────────────────────────────

class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    ref.read(_searchQueryProvider.notifier).state = query;
    ref.read(_searchLoadingProvider.notifier).state = true;
    ref.read(_collapsedFilesProvider.notifier).state = const {};

    try {
      final results = await runSearch(
        ref,
        query,
        caseSensitive: ref.read(_searchCaseSensitiveProvider),
        regex: ref.read(_searchRegexProvider),
      );
      ref.read(_searchResultsProvider.notifier).state = results;
    } finally {
      ref.read(_searchLoadingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final sandboxState = ref.watch(sandboxProvider);
    final project = ref.watch(activeProjectProvider);
    final isLoading = ref.watch(_searchLoadingProvider);
    final results = ref.watch(_searchResultsProvider);
    final caseSensitive = ref.watch(_searchCaseSensitiveProvider);
    final useRegex = ref.watch(_searchRegexProvider);

    final isReady = sandboxState == SandboxState.ready && project != null;

    return Container(
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              'SEARCH',
              style: TextStyle(
                color: c.fgMuted,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Search input row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.bg,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: isReady,
                      style: TextStyle(color: c.fg, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle:
                            TextStyle(color: c.fgMuted, fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _doSearch(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Case-sensitive toggle
                _ToggleBtn(
                  label: 'Aa',
                  active: caseSensitive,
                  tooltip: 'Match Case',
                  onTap: () => ref
                      .read(_searchCaseSensitiveProvider.notifier)
                      .state = !caseSensitive,
                  c: c,
                ),
                const SizedBox(width: 2),
                // Regex toggle
                _ToggleBtn(
                  label: '.*',
                  active: useRegex,
                  tooltip: 'Use Regular Expression',
                  onTap: () => ref
                      .read(_searchRegexProvider.notifier)
                      .state = !useRegex,
                  c: c,
                ),
              ],
            ),
          ),
          // Results summary / status
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: _buildSummary(c, isReady, isLoading, results),
          ),
          const Divider(height: 1, color: Color(0xFF3E3E42)),
          // Results list
          Expanded(
            child: isLoading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.accent),
                    ),
                  )
                : _buildResults(c, project, results),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
    VsCodeColors c,
    bool isReady,
    bool isLoading,
    SearchResults? results,
  ) {
    if (!isReady) {
      return Text(
        'Open a project to search',
        style: TextStyle(color: c.fgMuted, fontSize: 11),
      );
    }
    if (isLoading) {
      return Text(
        'Searching…',
        style: TextStyle(color: c.fgMuted, fontSize: 11),
      );
    }
    if (results == null) {
      return Text(
        'Type to search',
        style: TextStyle(color: c.fgMuted, fontSize: 11),
      );
    }
    if (results.hits.isEmpty) {
      return Text(
        'No results',
        style: TextStyle(color: c.fgMuted, fontSize: 11),
      );
    }
    return Text(
      '${results.hits.length} result${results.hits.length == 1 ? '' : 's'} '
      'in ${results.fileCount} file${results.fileCount == 1 ? '' : 's'}',
      style: TextStyle(color: c.fgMuted, fontSize: 11),
    );
  }

  Widget _buildResults(
    VsCodeColors c,
    dynamic project,
    SearchResults? results,
  ) {
    if (results == null || results.hits.isEmpty) {
      return const SizedBox.shrink();
    }

    // Group hits by file
    final Map<String, List<SearchHit>> byFile = {};
    for (final hit in results.hits) {
      byFile.putIfAbsent(hit.file, () => []).add(hit);
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final entry in byFile.entries)
          _FileGroup(
            filePath: entry.key,
            hits: entry.value,
            projectLocalPath: project?.localPath ?? '',
            colors: c,
          ),
      ],
    );
  }
}

// ── File group (collapsible) ─────────────────────────────────────────────────

class _FileGroup extends ConsumerWidget {
  final String filePath;
  final List<SearchHit> hits;
  final String projectLocalPath;
  final VsCodeColors colors;

  const _FileGroup({
    required this.filePath,
    required this.hits,
    required this.projectLocalPath,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    final collapsed =
        ref.watch(_collapsedFilesProvider).contains(filePath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File header row
        InkWell(
          onTap: () {
            final cur = ref.read(_collapsedFilesProvider);
            if (cur.contains(filePath)) {
              ref.read(_collapsedFilesProvider.notifier).state =
                  Set.from(cur)..remove(filePath);
            } else {
              ref.read(_collapsedFilesProvider.notifier).state =
                  Set.from(cur)..add(filePath);
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  collapsed
                      ? Codicons.chevronRight
                      : Codicons.chevronDown,
                  size: 12,
                  color: c.fgMuted,
                ),
                const SizedBox(width: 4),
                Icon(Codicons.fileCode, size: 13, color: c.fgMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    filePath,
                    style: TextStyle(
                        color: c.fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                // Count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.accent.withAlpha(51),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${hits.length}',
                    style: TextStyle(
                        color: c.accent, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Hit rows
        if (!collapsed)
          for (final hit in hits)
            _HitRow(
              hit: hit,
              projectLocalPath: projectLocalPath,
              colors: c,
            ),
      ],
    );
  }
}

// ── Single hit row ───────────────────────────────────────────────────────────

class _HitRow extends ConsumerWidget {
  final SearchHit hit;
  final String projectLocalPath;
  final VsCodeColors colors;

  const _HitRow({
    required this.hit,
    required this.projectLocalPath,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;
    return InkWell(
      onTap: () {
        // Open the file in the editor.
        // TODO(search): jump to specific line once editor supports it.
        final absPath = projectLocalPath.isNotEmpty
            ? '$projectLocalPath/${hit.file}'
            : hit.file;
        ref.read(openTabsProvider.notifier).openFile(absPath);
        // Switch to editor tab so the file is visible.
        ref.read(activeTabProvider.notifier).state = ActivityTab.editor;
      },
      child: Container(
        padding:
            const EdgeInsets.only(left: 28, right: 8, top: 2, bottom: 2),
        child: Row(
          children: [
            // Line number
            SizedBox(
              width: 36,
              child: Text(
                '${hit.line}',
                style: TextStyle(
                    color: c.fgMuted,
                    fontSize: 11,
                    fontFamily: 'monospace'),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            // Match text
            Expanded(
              child: Text(
                hit.text.trim(),
                style: TextStyle(
                    color: c.fg,
                    fontSize: 12,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small toggle button ──────────────────────────────────────────────────────

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final VsCodeColors c;

  const _ToggleBtn({
    required this.label,
    required this.active,
    required this.tooltip,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.accent.withAlpha(51) : Colors.transparent,
            border: Border.all(
              color: active ? c.accent : Colors.transparent,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? c.accent : c.fgMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
