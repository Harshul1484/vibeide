import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/ai/ai_provider.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'package:vibeide/features/editor/editor_provider.dart';
import 'package:vibeide/features/explorer/explorer_provider.dart';
import 'git_graph_view.dart';
import 'git_provider.dart';
import 'pr_screen.dart';
import 'pr_list_screen.dart';

class ScmPanel extends ConsumerStatefulWidget {
  const ScmPanel({super.key});

  @override
  ConsumerState<ScmPanel> createState() => _ScmPanelState();
}

class _ScmPanelState extends ConsumerState<ScmPanel> {
  bool _pulling = false;
  bool _fetching = false;
  bool _graphExpanded = true;

  // ── helpers ──────────────────────────────────────────────────────────────

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? Colors.red.shade800 : Colors.green.shade800,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _refreshAll() async {
    ref.invalidate(gitStatusProvider);
    ref.invalidate(fileTreeProvider);
    ref.invalidate(conflictedFilesProvider);
    ref.invalidate(mergeInProgressProvider);
    ref.invalidate(behindCountProvider);
    ref.invalidate(gitGraphProvider);
  }

  Future<void> _reloadOpenTabs() async {
    final tabs = ref.read(openTabsProvider);
    final notifier = ref.read(openTabsProvider.notifier);
    for (final tab in tabs) {
      await notifier.reloadFile(tab.path);
    }
  }

  // ── Pull ─────────────────────────────────────────────────────────────────

  Future<void> _doPull() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final token = ref.read(githubTokenProvider);
    final client = ref.read(sandboxClientProvider);

    setState(() => _pulling = true);
    try {
      final status = await client.gitStatus(project.localPath);
      final branch =
          status.branch.isNotEmpty ? status.branch : project.branch;

      final (exitCode, output) =
          await client.gitPull(project.localPath, branch, token: token);

      await _refreshAll();

      final isConflict = exitCode != 0 &&
          (output.contains('CONFLICT') ||
              output.contains('Automatic merge failed'));

      if (isConflict) {
        // Reload tabs so editors show conflict markers.
        await _reloadOpenTabs();
        // The conflict banner in this panel (built from conflictedFilesProvider)
        // will become visible after the invalidation above.
        _toast('Pull caused merge conflicts — resolve them below.',
            error: true);
      } else if (exitCode == 0) {
        await _reloadOpenTabs();
        if (output.contains('Already up to date')) {
          _toast('Already up to date');
        } else {
          _toast('Pulled successfully');
        }
      } else {
        _toast('Pull failed: ${output.trim().split('\n').last}', error: true);
      }
    } catch (e) {
      _toast('Pull error: $e', error: true);
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  // ── Fetch ────────────────────────────────────────────────────────────────

  Future<void> _doFetch() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final token = ref.read(githubTokenProvider);
    final client = ref.read(sandboxClientProvider);

    setState(() => _fetching = true);
    try {
      final (exitCode, output) =
          await client.gitFetch(project.localPath, token: token);
      await _refreshAll();
      if (exitCode == 0) {
        _toast('Fetch complete');
      } else {
        _toast('Fetch failed: ${output.trim().split('\n').last}', error: true);
      }
    } catch (e) {
      _toast('Fetch error: $e', error: true);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  // ── Merge continue ───────────────────────────────────────────────────────

  Future<void> _doMergeContinue() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final client = ref.read(sandboxClientProvider);

    final (exitCode, output) =
        await client.gitMergeContinue(project.localPath);
    await _refreshAll();
    if (exitCode == 0) {
      _toast('Merge completed!');
    } else {
      _toast('Merge commit failed: ${output.trim().split('\n').last}',
          error: true);
    }
  }

  // ── Merge abort ──────────────────────────────────────────────────────────

  Future<void> _doMergeAbort() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    final client = ref.read(sandboxClientProvider);

    final (exitCode, output) =
        await client.gitMergeAbort(project.localPath);
    await _reloadOpenTabs();
    await _refreshAll();
    if (exitCode == 0) {
      _toast('Merge aborted');
    } else {
      _toast('Abort failed: ${output.trim().split('\n').last}',
          error: true);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final status = ref.watch(gitStatusProvider);
    final commitMsg = ref.watch(commitMessageProvider);
    final conflicted = ref.watch(conflictedFilesProvider);
    final mergeInProgress = ref.watch(mergeInProgressProvider);
    final behindCount = ref.watch(behindCountProvider);

    // Derived values (use 0 / false / empty as safe defaults while loading).
    final behindN = behindCount.valueOrNull ?? 0;
    final conflictedFiles = conflicted.valueOrNull ?? [];
    final isMerging = mergeInProgress.valueOrNull ?? false;

    final branch = status.valueOrNull?.branch ?? '';

    return Container(
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Codicons.gitBranch, size: 14, color: c.fgMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    branch.isNotEmpty ? branch : 'SOURCE CONTROL',
                    style: TextStyle(
                        color: c.fgMuted,
                        fontSize: 11,
                        letterSpacing: 1.2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // ↓N behind badge
                if (behindN > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0078D4).withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF0078D4).withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_downward,
                            size: 10, color: Color(0xFF0078D4)),
                        const SizedBox(width: 2),
                        Text(
                          '$behindN',
                          style: const TextStyle(
                              color: Color(0xFF0078D4), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // View PR list
                IconButton(
                  icon: Icon(Codicons.gitPullRequest, size: 16,
                      color: c.fgMuted),
                  tooltip: 'Pull Requests',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PrListScreen()),
                  ),
                ),
                // Create PR
                IconButton(
                  icon: Icon(Codicons.add, size: 16,
                      color: c.fgMuted),
                  tooltip: 'Raise Pull Request',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PrScreen()),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),

          // ── Git actions row (Pull / Fetch) ───────────────────────────────
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // Pull
                _ActionButton(
                  icon: _pulling
                      ? null
                      : Icons.arrow_downward,
                  loading: _pulling,
                  tooltip: 'Pull from origin',
                  color: c.fgMuted,
                  onPressed: _pulling || _fetching ? null : _doPull,
                ),
                // Fetch
                _ActionButton(
                  icon: _fetching ? null : Codicons.sync,
                  loading: _fetching,
                  tooltip: 'Fetch all remotes',
                  color: c.fgMuted,
                  onPressed: _pulling || _fetching ? null : _doFetch,
                ),
                const Spacer(),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),

          // ── Conflict banner ──────────────────────────────────────────────
          if (conflictedFiles.isNotEmpty)
            _ConflictBanner(
              conflictedFiles: conflictedFiles,
              onOpenFirst: () {
                final project = ref.read(activeProjectProvider);
                if (project == null) return;
                final relPath = conflictedFiles.first;
                final absPath = '${project.localPath}/$relPath';
                ref
                    .read(openTabsProvider.notifier)
                    .openFile(absPath);
              },
              onAbort: _doMergeAbort,
            ),

          // ── Complete merge banner (no conflicts but merge in progress) ──
          if (isMerging && conflictedFiles.isEmpty)
            _CompleteMergeBanner(onComplete: _doMergeContinue),

          // ── Commit message row ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:
                        TextEditingController(text: commitMsg),
                    onChanged: (v) => ref
                        .read(commitMessageProvider.notifier)
                        .state = v,
                    style: TextStyle(color: c.fg, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Commit message',
                      hintStyle: TextStyle(color: c.fgMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      filled: true,
                      fillColor: c.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: c.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: c.border),
                      ),
                    ),
                  ),
                ),
                // AI button
                Tooltip(
                  message: 'Generate with AI',
                  child: IconButton(
                    icon: const Icon(Codicons.sparkle, size: 16),
                    color: const Color(0xFF0078D4),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                    onPressed: () async {
                      final project =
                          ref.read(activeProjectProvider);
                      if (project == null) return;
                      final diff = await ref
                          .read(sandboxClientProvider)
                          .gitDiff(project.localPath);
                      final msg = await ref
                          .read(aiClientProvider)
                          .generateCommitMessage(diff);
                      ref
                          .read(commitMessageProvider.notifier)
                          .state = msg;
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Commit button ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              height: 30,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D4),
                  padding: EdgeInsets.zero,
                ),
                onPressed: commitMsg.isEmpty
                    ? null
                    : () async {
                        final project =
                            ref.read(activeProjectProvider);
                        if (project == null) return;
                        await ref
                            .read(sandboxClientProvider)
                            .gitCommit(project.localPath, commitMsg);
                        ref
                            .read(commitMessageProvider.notifier)
                            .state = '';
                        ref.invalidate(gitStatusProvider);
                        ref.invalidate(gitGraphProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Committed!')),
                          );
                        }
                      },
                child: const Text('Commit',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: c.border),

          // ── File status list ─────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: status.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: c.accent),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No git repo',
                  style: TextStyle(color: c.fgMuted, fontSize: 12),
                ),
              ),
              data: (s) => ListView(
                children: [
                  if (s.staged.isNotEmpty)
                    _StatusSection(
                        title: 'STAGED',
                        files: s.staged,
                        color: const Color(0xFF73C991)),
                  if (s.modified.isNotEmpty)
                    _StatusSection(
                        title: 'CHANGES',
                        files: s.modified,
                        color: const Color(0xFFE2C08D)),
                  if (s.untracked.isNotEmpty)
                    _StatusSection(
                        title: 'UNTRACKED',
                        files: s.untracked,
                        color: const Color(0xFF858585)),
                  if (s.staged.isEmpty &&
                      s.modified.isEmpty &&
                      s.untracked.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No changes',
                        style: TextStyle(
                            color: c.fgMuted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── GRAPH section ────────────────────────────────────────────────
          Divider(height: 1, color: c.border),
          // Section header.
          GestureDetector(
            onTap: () =>
                setState(() => _graphExpanded = !_graphExpanded),
            child: Container(
              height: 28,
              color: c.sidebar,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    _graphExpanded
                        ? Codicons.chevronDown
                        : Codicons.chevronRight,
                    size: 14,
                    color: c.fgMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'GRAPH',
                      style: TextStyle(
                        color: c.fgMuted,
                        fontSize: 10,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  // Refresh button.
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      icon:
                          Icon(Codicons.refresh, size: 13, color: c.fgMuted),
                      tooltip: 'Refresh graph',
                      padding: EdgeInsets.zero,
                      onPressed: () => ref.invalidate(gitGraphProvider),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_graphExpanded)
            const Expanded(
              flex: 3,
              child: GitGraphView(),
            ),
        ],
      ),
    );
  }
}

// ── Small icon button with optional spinner ───────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData? icon;
  final bool loading;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.loading,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 28,
        height: 28,
        child: loading
            ? Center(
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                ),
              )
            : IconButton(
                icon: Icon(icon, size: 16, color: color),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 28, minHeight: 28),
                onPressed: onPressed,
              ),
      ),
    );
  }
}

// ── Amber conflict banner ─────────────────────────────────────────────────────

class _ConflictBanner extends StatelessWidget {
  final List<String> conflictedFiles;
  final VoidCallback onOpenFirst;
  final VoidCallback onAbort;

  const _ConflictBanner({
    required this.conflictedFiles,
    required this.onOpenFirst,
    required this.onAbort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF3A2E00),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: Color(0xFFE2C08D)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${conflictedFiles.length} conflicted file${conflictedFiles.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: Color(0xFFE2C08D), fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // List up to 3 conflicted files.
          ...conflictedFiles.take(3).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 1),
                  child: Text(
                    f.split('/').last,
                    style: const TextStyle(
                        color: Color(0xFFE2C08D),
                        fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          if (conflictedFiles.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 1),
              child: Text(
                '+ ${conflictedFiles.length - 3} more',
                style: const TextStyle(
                    color: Color(0xFF858585), fontSize: 11),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              _BannerButton(
                label: 'Resolve in editor',
                onTap: onOpenFirst,
                primary: true,
              ),
              const SizedBox(width: 8),
              _BannerButton(
                label: 'Abort merge',
                onTap: onAbort,
                primary: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Green "Complete merge" banner ─────────────────────────────────────────────

class _CompleteMergeBanner extends StatelessWidget {
  final VoidCallback onComplete;

  const _CompleteMergeBanner({required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A2E0A),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 14, color: Color(0xFF73C991)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'All conflicts resolved',
              style: TextStyle(color: Color(0xFF73C991), fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _BannerButton(
            label: 'Complete merge',
            onTap: onComplete,
            primary: true,
          ),
        ],
      ),
    );
  }
}

// ── Small text button used inside banners ─────────────────────────────────────

class _BannerButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _BannerButton({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: primary
              ? const Color(0xFF0078D4).withAlpha(50)
              : Colors.transparent,
          border: Border.all(
            color: primary
                ? const Color(0xFF0078D4)
                : const Color(0xFF858585),
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary
                ? const Color(0xFF0078D4)
                : const Color(0xFF858585),
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ── Status section ────────────────────────────────────────────────────────────

class _StatusSection extends StatelessWidget {
  final String title;
  final List<String> files;
  final Color color;

  const _StatusSection({
    required this.title,
    required this.files,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Text(
            title,
            style: TextStyle(
              color: c.fgMuted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ),
        ...files.map(
          (f) => Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 2),
            child: Text(
              f.split('/').last,
              style: TextStyle(color: color, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
