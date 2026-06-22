import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'diff_view.dart';
import 'pr_management_provider.dart';

class PrDetailScreen extends ConsumerStatefulWidget {
  final String repoUrl;
  final int number;
  final String initialTitle;

  const PrDetailScreen({
    super.key,
    required this.repoUrl,
    required this.number,
    required this.initialTitle,
  });

  @override
  ConsumerState<PrDetailScreen> createState() => _PrDetailScreenState();
}

class _PrDetailScreenState extends ConsumerState<PrDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  // The file whose diff patch is shown
  int? _selectedFileIndex;
  bool _merging = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── helpers ─────────────────────────────────────────────────────────────────

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          error ? Colors.red.shade800 : Colors.green.shade800,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _doMerge(
      String method, Map<String, dynamic> detail) async {
    final api = ref.read(githubApiProvider);
    if (api == null) {
      _toast('Not signed in to GitHub', error: true);
      return;
    }
    setState(() => _merging = true);
    try {
      await api.mergePullRequest(widget.repoUrl, widget.number,
          method: method);
      _toast('PR #${widget.number} merged');
      ref.invalidate(pullRequestsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('Merge failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  Future<void> _showMergeDialog(Map<String, dynamic> detail) async {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text(
          'Merge pull request',
          style:
              TextStyle(color: Color(0xFFD4D4D4), fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MergeOption(
              label: 'Merge commit',
              subtitle: 'All commits will be added to the base branch.',
              value: 'merge',
              c: c,
            ),
            const SizedBox(height: 8),
            _MergeOption(
              label: 'Squash and merge',
              subtitle: 'Squash commits into one before merging.',
              value: 'squash',
              c: c,
            ),
            const SizedBox(height: 8),
            _MergeOption(
              label: 'Rebase and merge',
              subtitle: 'Rebase commits onto the base branch.',
              value: 'rebase',
              c: c,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF858585))),
          ),
        ],
      ),
    );
    if (method != null) {
      await _doMerge(method, detail);
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    final detailAsync = ref.watch(
        prDetailProvider((repoUrl: widget.repoUrl, number: widget.number)));
    final filesAsync = ref.watch(
        prFilesProvider((repoUrl: widget.repoUrl, number: widget.number)));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          '#${widget.number}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          // Open in browser
          detailAsync.when(
            data: (d) {
              final htmlUrl = d['html_url'] as String? ?? '';
              return IconButton(
                icon: const Icon(Codicons.link),
                tooltip: 'Open in browser',
                onPressed: htmlUrl.isNotEmpty
                    ? () => launchUrl(Uri.parse(htmlUrl),
                        mode: LaunchMode.externalApplication)
                    : null,
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: c.accent)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load PR: $e',
              style:
                  const TextStyle(color: Color(0xFFF85149), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (detail) => _DetailBody(
          detail: detail,
          filesAsync: filesAsync,
          repoUrl: widget.repoUrl,
          number: widget.number,
          selectedFileIndex: _selectedFileIndex,
          merging: _merging,
          tabController: _tabController,
          c: c,
          onFileSelected: (i) => setState(() => _selectedFileIndex = i),
          onMerge: () => _showMergeDialog(detail),
          ref: ref,
        ),
      ),
    );
  }
}

// ── Detail body ───────────────────────────────────────────────────────────────

class _DetailBody extends StatelessWidget {
  final Map<String, dynamic> detail;
  final AsyncValue<List<Map<String, dynamic>>> filesAsync;
  final String repoUrl;
  final int number;
  final int? selectedFileIndex;
  final bool merging;
  final TabController tabController;
  final VsCodeColors c;
  final ValueChanged<int> onFileSelected;
  final VoidCallback onMerge;
  final WidgetRef ref;

  const _DetailBody({
    required this.detail,
    required this.filesAsync,
    required this.repoUrl,
    required this.number,
    required this.selectedFileIndex,
    required this.merging,
    required this.tabController,
    required this.c,
    required this.onFileSelected,
    required this.onMerge,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final title = detail['title'] as String? ?? '';
    final body = detail['body'] as String? ?? '';
    final state = detail['state'] as String? ?? 'open';
    final user = (detail['user'] as Map<String, dynamic>?)?['login']
            as String? ??
        '';
    final head =
        (detail['head'] as Map<String, dynamic>?)?['ref'] as String? ?? '';
    final base =
        (detail['base'] as Map<String, dynamic>?)?['ref'] as String? ?? '';
    final headSha =
        (detail['head'] as Map<String, dynamic>?)?['sha'] as String? ?? '';
    final additions = detail['additions'] as int? ?? 0;
    final deletions = detail['deletions'] as int? ?? 0;
    final changedFiles = detail['changed_files'] as int? ?? 0;
    final mergeable = detail['mergeable'] as bool?;
    final mergeableState = detail['mergeable_state'] as String? ?? 'unknown';
    final htmlUrl = detail['html_url'] as String? ?? '';

    // CI status
    final ciAsync = ref.watch(
        prCiStatusProvider((repoUrl: repoUrl, ref: headSha)));

    return Column(
      children: [
        // ── Header card ─────────────────────────────────────────────────────
        Container(
          color: const Color(0xFF252526),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                title,
                style: TextStyle(
                  color: c.fg,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
              const SizedBox(height: 6),
              // head → base · @user · state
              Row(
                children: [
                  Icon(Codicons.gitBranch,
                      size: 12, color: c.fgMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      head,
                      style: const TextStyle(
                        color: Color(0xFF79C0FF),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(' → ',
                      style:
                          TextStyle(color: c.fgMuted, fontSize: 11)),
                  Flexible(
                    child: Text(
                      base,
                      style: const TextStyle(
                        color: Color(0xFF79C0FF),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (user.isNotEmpty) ...[
                    Text(' · @$user',
                        style: TextStyle(
                            color: c.fgMuted, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(width: 8),
                  _StateChip(state: state),
                ],
              ),
              const SizedBox(height: 8),
              // Stats row
              Row(
                children: [
                  Text(
                    '+$additions',
                    style: const TextStyle(
                        color: Color(0xFF3FB950), fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '-$deletions',
                    style: const TextStyle(
                        color: Color(0xFFF85149), fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$changedFiles file${changedFiles == 1 ? '' : 's'}',
                    style:
                        TextStyle(color: c.fgMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Mergeable + CI row
              Row(
                children: [
                  _MergeableChip(
                      mergeable: mergeable,
                      mergeableState: mergeableState),
                  const SizedBox(width: 10),
                  ciAsync.when(
                    data: (ci) =>
                        _CiChip(state: ci['state'] as String? ?? 'unknown'),
                    loading: () => const _CiChip(state: 'pending'),
                    error: (_, __) =>
                        const _CiChip(state: 'unknown'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ── Tabs ─────────────────────────────────────────────────────────────
        Container(
          color: const Color(0xFF252526),
          child: TabBar(
            controller: tabController,
            labelColor: c.fg,
            unselectedLabelColor: c.fgMuted,
            indicatorColor: c.accent,
            labelStyle:
                const TextStyle(fontSize: 12),
            tabs: [
              const Tab(text: 'Description'),
              Tab(
                child: filesAsync.when(
                  data: (f) => Text('Files changed (${f.length})'),
                  loading: () => const Text('Files changed'),
                  error: (_, __) => const Text('Files changed'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              // ── Description tab ────────────────────────────────────────────
              body.isEmpty
                  ? Center(
                      child: Text(
                        'No description',
                        style:
                            TextStyle(color: c.fgMuted, fontSize: 13),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        body,
                        style: TextStyle(color: c.fg, fontSize: 13, height: 1.5),
                      ),
                    ),
              // ── Files changed tab ──────────────────────────────────────────
              filesAsync.when(
                loading: () => Center(
                    child:
                        CircularProgressIndicator(color: c.accent)),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(
                          color: Color(0xFFF85149),
                          fontSize: 13)),
                ),
                data: (files) => _FilesPanel(
                  files: files,
                  selectedIndex: selectedFileIndex,
                  c: c,
                  onFileSelected: onFileSelected,
                ),
              ),
            ],
          ),
        ),
        // ── Actions footer ────────────────────────────────────────────────────
        Divider(height: 1, color: c.border),
        Container(
          color: const Color(0xFF252526),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              // Merge button
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mergeable == true
                          ? const Color(0xFF1A7F37)
                          : const Color(0xFF2D2D2D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: (mergeable == true && !merging)
                        ? onMerge
                        : null,
                    icon: merging
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Codicons.gitPullRequest, size: 16),
                    label: Text(
                      merging
                          ? 'Merging…'
                          : mergeable == false
                              ? 'Cannot merge'
                              : 'Merge pull request',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Open in browser
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.fgMuted,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onPressed: htmlUrl.isNotEmpty
                    ? () => launchUrl(Uri.parse(htmlUrl),
                        mode: LaunchMode.externalApplication)
                    : null,
                icon: const Icon(Codicons.link, size: 14),
                label: const Text('Open', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Files panel ───────────────────────────────────────────────────────────────

class _FilesPanel extends StatelessWidget {
  final List<Map<String, dynamic>> files;
  final int? selectedIndex;
  final VsCodeColors c;
  final ValueChanged<int> onFileSelected;

  const _FilesPanel({
    required this.files,
    required this.selectedIndex,
    required this.c,
    required this.onFileSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Center(
        child: Text('No files changed',
            style: TextStyle(color: c.fgMuted, fontSize: 13)),
      );
    }

    if (selectedIndex == null) {
      // Show list of files
      return ListView.separated(
        itemCount: files.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
        itemBuilder: (ctx, i) {
          final f = files[i];
          final filename = f['filename'] as String? ?? '';
          final status = f['status'] as String? ?? '';
          final additions = f['additions'] as int? ?? 0;
          final deletions = f['deletions'] as int? ?? 0;

          return InkWell(
            onTap: () => onFileSelected(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Codicons.forFile(filename),
                      size: 14, color: c.fgMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filename.split('/').last,
                          style: TextStyle(color: c.fg, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          filename,
                          style: TextStyle(
                              color: c.fgMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusLabel(status: status),
                  const SizedBox(width: 8),
                  Text(
                    '+$additions',
                    style: const TextStyle(
                        color: Color(0xFF3FB950), fontSize: 11),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '-$deletions',
                    style: const TextStyle(
                        color: Color(0xFFF85149), fontSize: 11),
                  ),
                  const SizedBox(width: 4),
                  Icon(Codicons.chevronRight, size: 12, color: c.fgMuted),
                ],
              ),
            ),
          );
        },
      );
    } else {
      // Show diff for selected file
      final f = files[selectedIndex!];
      final patch = f['patch'] as String? ?? '';
      final filename = f['filename'] as String? ?? '';
      final additions = f['additions'] as int? ?? 0;
      final deletions = f['deletions'] as int? ?? 0;

      return Column(
        children: [
          // Back + file header
          Container(
            color: const Color(0xFF252526),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Codicons.chevronRight,
                      size: 14, color: c.fgMuted),
                  tooltip: 'Back to file list',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  onPressed: () => onFileSelected(-1),
                ),
                Expanded(
                  child: Text(
                    filename,
                    style: TextStyle(
                        color: c.fg,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '+$additions  -$deletions',
                  style: const TextStyle(
                      color: Color(0xFF858585), fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: patch.isEmpty
                ? Center(
                    child: Text(
                      'No patch available for this file',
                      style:
                          TextStyle(color: c.fgMuted, fontSize: 13),
                    ),
                  )
                : DiffView(unifiedDiff: patch, split: false),
          ),
        ],
      );
    }
  }
}

// ── Chips ─────────────────────────────────────────────────────────────────────

class _StateChip extends StatelessWidget {
  final String state;
  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final isOpen = state == 'open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isOpen
            ? const Color(0xFF1A7F37).withAlpha(60)
            : const Color(0xFF6E40C9).withAlpha(60),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOpen
              ? const Color(0xFF3FB950)
              : const Color(0xFF8957E5),
        ),
      ),
      child: Text(
        isOpen ? 'Open' : 'Closed',
        style: TextStyle(
          color: isOpen
              ? const Color(0xFF3FB950)
              : const Color(0xFF8957E5),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MergeableChip extends StatelessWidget {
  final bool? mergeable;
  final String mergeableState;
  const _MergeableChip(
      {required this.mergeable, required this.mergeableState});

  @override
  Widget build(BuildContext context) {
    if (mergeable == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timelapse, size: 12, color: Color(0xFFD79B0F)),
          SizedBox(width: 4),
          Text('Checking merge status…',
              style: TextStyle(
                  color: Color(0xFFD79B0F), fontSize: 11)),
        ],
      );
    }
    if (mergeable == true) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Codicons.check, size: 12, color: Color(0xFF3FB950)),
          SizedBox(width: 4),
          Text('Able to merge',
              style: TextStyle(
                  color: Color(0xFF3FB950), fontSize: 11)),
        ],
      );
    }
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Codicons.warning, size: 12, color: Color(0xFFD79B0F)),
        SizedBox(width: 4),
        Text('Conflicts',
            style:
                TextStyle(color: Color(0xFFD79B0F), fontSize: 11)),
      ],
    );
  }
}

class _CiChip extends StatelessWidget {
  final String state;
  const _CiChip({required this.state});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label;

    switch (state) {
      case 'success':
        icon = Codicons.check;
        color = const Color(0xFF3FB950);
        label = 'CI passed';
      case 'failure':
      case 'error':
        icon = Codicons.error;
        color = const Color(0xFFF85149);
        label = 'CI failed';
      case 'pending':
        icon = Codicons.circleFilled;
        color = const Color(0xFFD79B0F);
        label = 'CI pending';
      default:
        icon = Codicons.circleFilled;
        color = const Color(0xFF858585);
        label = 'No CI';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final String status;
  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'added':
        color = const Color(0xFF3FB950);
      case 'removed':
        color = const Color(0xFFF85149);
      case 'renamed':
        color = const Color(0xFF79C0FF);
      case 'modified':
      default:
        color = const Color(0xFFD79B0F);
    }
    return Text(
      status,
      style: TextStyle(color: color, fontSize: 10),
    );
  }
}

// ── Merge method option ───────────────────────────────────────────────────────

class _MergeOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final VsCodeColors c;

  const _MergeOption({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF3E3E42)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                  color: Color(0xFF858585), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
