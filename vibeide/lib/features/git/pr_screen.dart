import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/ai/ai_provider.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'git_provider.dart';
import 'diff_view.dart';

enum _Phase { compare, review, submitting }

class PrScreen extends ConsumerStatefulWidget {
  const PrScreen({super.key});

  @override
  ConsumerState<PrScreen> createState() => _PrScreenState();
}

class _PrScreenState extends ConsumerState<PrScreen>
    with SingleTickerProviderStateMixin {
  // Branch state
  String _baseBranch = 'main';
  String _headBranch = '';
  List<String> _branches = [];
  bool _loadingBranches = true;

  // Files changed
  List<String> _changedFiles = [];
  String? _selectedFile;
  String _selectedFileDiff = '';
  bool _loadingFileDiff = false;

  // View mode
  bool _split = false;

  // PR description
  String _title = '';
  String _body = '';
  bool _generatingDesc = false;
  String? _descError;

  // Overall loading / error
  bool _loading = false;
  String? _error;

  _Phase _phase = _Phase.compare;

  // Tab controller (Commits | Files changed)
  late final TabController _tabController;

  // Branch-creation helpers
  bool _creatingBranch = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  Future<void> _init() async {
    setState(() { _loadingBranches = true; _error = null; });
    try {
      final project = ref.read(activeProjectProvider);
      if (project == null) throw Exception('No project open');
      final client = ref.read(sandboxClientProvider);

      final results = await Future.wait([
        client.gitBranches(project.localPath),
        client.gitCurrentBranch(project.localPath),
      ]);

      final branches = results[0] as List<String>;
      final current = results[1] as String;

      // Ensure 'main' is in the list.
      if (!branches.contains('main')) {
        branches.insert(0, 'main');
      }

      setState(() {
        _branches = branches;
        _headBranch = current.isNotEmpty ? current : (branches.isNotEmpty ? branches.first : 'main');
        _baseBranch = 'main';
        _loadingBranches = false;
      });

      await _loadChangedFiles();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingBranches = false;
      });
    }
  }

  Future<void> _loadChangedFiles() async {
    if (_headBranch == _baseBranch) return;
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    try {
      final files = await ref
          .read(sandboxClientProvider)
          .gitChangedFiles(project.localPath, base: _baseBranch);
      setState(() {
        _changedFiles = files;
        _selectedFile = null;
        _selectedFileDiff = '';
      });
    } catch (_) {
      setState(() => _changedFiles = []);
    }
  }

  Future<void> _loadFileDiff(String file) async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    setState(() { _loadingFileDiff = true; _selectedFile = file; });
    try {
      final diff = await ref
          .read(sandboxClientProvider)
          .gitFileDiff(project.localPath, file, base: _baseBranch);
      setState(() {
        _selectedFileDiff = diff;
        _loadingFileDiff = false;
      });
    } catch (e) {
      setState(() {
        _selectedFileDiff = '';
        _loadingFileDiff = false;
      });
    }
  }

  Future<void> _generateDescription() async {
    if (_headBranch == _baseBranch) return;
    setState(() { _generatingDesc = true; _descError = null; });
    try {
      final project = ref.read(activeProjectProvider);
      if (project == null) throw Exception('No project open');
      final diff = await ref
          .read(sandboxClientProvider)
          .gitDiff(project.localPath, base: _baseBranch);
      final result = await ref.read(aiClientProvider).generatePrDescription(diff);
      setState(() {
        _title = result['title'] ?? 'Update code';
        _body = result['body'] ?? '';
        _generatingDesc = false;
      });
    } catch (e) {
      setState(() {
        _descError = e.toString();
        _title = 'Update code';
        _body = '## Summary\n- Changes made\n\n## Test plan\n- [ ] Tested manually';
        _generatingDesc = false;
      });
    }
  }

  // -------------------------------------------------------------------------
  // Branch creation flow
  // -------------------------------------------------------------------------

  Future<void> _createBranchFromChanges() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;

    // Suggest a branch name from commit message or timestamp.
    final commitMsg = ref.read(commitMessageProvider);
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final suggested = commitMsg.isNotEmpty
        ? 'vibe/${commitMsg.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '-').toLowerCase().substring(0, commitMsg.length.clamp(0, 40))}'
        : 'vibe/$ts';

    final nameCtrl = TextEditingController(text: suggested);
    if (!mounted) return;

    final branchName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Create branch', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFD4D4D4), fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'branch-name',
            hintStyle: TextStyle(color: Color(0xFF858585)),
            filled: true,
            fillColor: Color(0xFF1E1E1E),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (branchName == null || branchName.isEmpty) return;

    setState(() => _creatingBranch = true);
    try {
      final client = ref.read(sandboxClientProvider);
      final dir = project.localPath;

      // Commit any pending changes before switching branch.
      final status = await client.gitStatus(dir);
      final hasPending = status.staged.isNotEmpty ||
          status.modified.isNotEmpty ||
          status.untracked.isNotEmpty;
      if (hasPending) {
        final commitMsg2 = commitMsg.isNotEmpty ? commitMsg : 'WIP: auto-commit before branch creation';
        await client.gitCommit(dir, commitMsg2);
      }

      // Create and switch to the new branch.
      await client.gitCheckout(dir, branchName, create: true);

      setState(() {
        _headBranch = branchName;
        _creatingBranch = false;
      });

      if (!_branches.contains(branchName)) {
        setState(() => _branches = [..._branches, branchName]);
      }

      await _loadChangedFiles();
    } catch (e) {
      setState(() {
        _error = 'Failed to create branch: $e';
        _creatingBranch = false;
      });
    }
  }

  // -------------------------------------------------------------------------
  // Pull request submission
  // -------------------------------------------------------------------------

  Future<void> _createPr() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return;
    if (_headBranch == _baseBranch) return;

    final api = ref.read(githubApiProvider);
    if (api == null) {
      _showError('Connect GitHub in Settings first');
      return;
    }

    setState(() { _loading = true; _phase = _Phase.submitting; _error = null; });
    try {
      final token = ref.read(githubTokenProvider);
      final client = ref.read(sandboxClientProvider);

      // Push the head branch (with token for auth).
      await client.gitPush(project.localPath, _headBranch, token: token);

      final pr = await api.createPr(
        repoUrl: project.remoteUrl,
        title: _title.isNotEmpty ? _title : 'Update code',
        body: _body,
        head: _headBranch,
        base: _baseBranch,
      );

      final prUrl = pr['html_url'] as String? ?? '';

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF252526),
            duration: const Duration(seconds: 8),
            content: Row(
              children: [
                const Icon(Codicons.gitPullRequest, color: Color(0xFF3FB950), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PR created: $prUrl',
                    style: const TextStyle(color: Color(0xFFD4D4D4)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (prUrl.isNotEmpty)
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(prUrl), mode: LaunchMode.externalApplication),
                    child: const Text('Open', style: TextStyle(color: Color(0xFF0078D4))),
                  ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _phase = _Phase.review;
          _error = e.toString();
        });
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF5A1D1D),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final sameHead = _headBranch == _baseBranch || _headBranch.isEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Compare changes'),
        actions: [
          IconButton(
            icon: const Icon(Codicons.refresh),
            tooltip: 'Reload',
            onPressed: _init,
          ),
        ],
      ),
      body: _loadingBranches
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : Column(
              children: [
                // ── Error banner ─────────────────────────────────────────
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFF5A1D1D),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFF85149), fontSize: 12)),
                  ),

                // ── Compare bar ──────────────────────────────────────────
                Container(
                  color: const Color(0xFF252526),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Codicons.gitBranch, size: 16),
                          const SizedBox(width: 6),
                          const Text('base:', style: TextStyle(color: Color(0xFF858585), fontSize: 12)),
                          const SizedBox(width: 4),
                          _BranchPicker(
                            value: _baseBranch,
                            branches: _branches,
                            onChanged: (b) {
                              setState(() { _baseBranch = b; _changedFiles = []; _selectedFile = null; });
                              _loadChangedFiles();
                            },
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF858585)),
                          const SizedBox(width: 8),
                          const Text('compare:', style: TextStyle(color: Color(0xFF858585), fontSize: 12)),
                          const SizedBox(width: 4),
                          _BranchPicker(
                            value: _headBranch,
                            branches: _branches,
                            onChanged: (b) {
                              setState(() { _headBranch = b; _changedFiles = []; _selectedFile = null; });
                              _loadChangedFiles();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Status line
                      if (sameHead)
                        _StatusChip(
                          icon: Codicons.warning,
                          color: const Color(0xFFD79B0F),
                          bg: const Color(0xFF2D2000),
                          text: 'Pick a different branch — your changes need their own branch',
                          trailing: ElevatedButton.icon(
                            onPressed:
                                _creatingBranch ? null : _createBranchFromChanges,
                            icon: _creatingBranch
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Codicons.add, size: 16),
                            label: Text(_creatingBranch
                                ? 'Creating branch…'
                                : 'Create branch from changes'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0078D4),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              textStyle: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        )
                      else
                        _StatusChip(
                          icon: Codicons.check,
                          color: const Color(0xFF3FB950),
                          bg: const Color(0xFF0D2A18),
                          text: 'Ready to compare  •  ${_changedFiles.length} file${_changedFiles.length == 1 ? '' : 's'} changed',
                        ),
                    ],
                  ),
                ),

                // ── Tabs ─────────────────────────────────────────────────
                Container(
                  color: const Color(0xFF252526),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFFD4D4D4),
                    unselectedLabelColor: const Color(0xFF858585),
                    indicatorColor: const Color(0xFF0078D4),
                    labelStyle: const TextStyle(fontSize: 12),
                    tabs: [
                      const Tab(text: 'Commits'),
                      Tab(text: 'Files changed (${_changedFiles.length})'),
                    ],
                  ),
                ),

                // ── Tab content ───────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _CommitsTab(
                        baseBranch: _baseBranch,
                        headBranch: _headBranch,
                        same: sameHead,
                      ),
                      _FilesChangedTab(
                        changedFiles: _changedFiles,
                        selectedFile: _selectedFile,
                        selectedFileDiff: _selectedFileDiff,
                        loadingFileDiff: _loadingFileDiff,
                        split: _split,
                        same: sameHead,
                        onFileSelected: _loadFileDiff,
                        onToggleSplit: () => setState(() => _split = !_split),
                      ),
                    ],
                  ),
                ),

                // ── PR description + Create button ────────────────────────
                if (!sameHead) _PrFormPanel(
                  title: _title,
                  body: _body,
                  generating: _generatingDesc,
                  descError: _descError,
                  loading: _loading,
                  phase: _phase,
                  onTitleChanged: (v) => setState(() => _title = v),
                  onBodyChanged: (v) => setState(() => _body = v),
                  onRegenerate: _generateDescription,
                  onCreatePr: _createPr,
                  c: c,
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Branch picker
// ---------------------------------------------------------------------------

class _BranchPicker extends StatelessWidget {
  final String value;
  final List<String> branches;
  final ValueChanged<String> onChanged;
  const _BranchPicker({required this.value, required this.branches, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: const Color(0xFF3E3E42)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value.isNotEmpty ? value : 'select branch',
                style: const TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Codicons.chevronDown, size: 12, color: Color(0xFF858585)),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF252526),
      isScrollControlled: true,
      builder: (ctx) => _BranchSheet(
        branches: branches,
        selected: value,
        onSelected: (b) {
          Navigator.pop(ctx);
          onChanged(b);
        },
      ),
    );
  }
}

class _BranchSheet extends StatefulWidget {
  final List<String> branches;
  final String selected;
  final ValueChanged<String> onSelected;
  const _BranchSheet({required this.branches, required this.selected, required this.onSelected});

  @override
  State<_BranchSheet> createState() => _BranchSheetState();
}

class _BranchSheetState extends State<_BranchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.branches
        : widget.branches.where((b) => b.toLowerCase().contains(_query.toLowerCase())).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Find a branch…',
                hintStyle: TextStyle(color: Color(0xFF858585)),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Codicons.search, size: 14, color: Color(0xFF858585)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final b = filtered[i];
                final isSelected = b == widget.selected;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Codicons.gitBranch,
                    size: 14,
                    color: isSelected ? const Color(0xFF3FB950) : const Color(0xFF858585),
                  ),
                  title: Text(
                    b,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF3FB950) : const Color(0xFFD4D4D4),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected ? const Icon(Codicons.check, size: 14, color: Color(0xFF3FB950)) : null,
                  onTap: () => widget.onSelected(b),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String text;
  final Widget? trailing;
  const _StatusChip({
    required this.icon,
    required this.color,
    required this.bg,
    required this.text,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + message
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: color, fontSize: 12.5, height: 1.3),
                ),
              ),
            ],
          ),
          // Full-width action below the message (no cramped side-by-side)
          if (trailing != null) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: trailing!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Commits tab (simple log)
// ---------------------------------------------------------------------------

class _CommitsTab extends ConsumerStatefulWidget {
  final String baseBranch;
  final String headBranch;
  final bool same;
  const _CommitsTab({required this.baseBranch, required this.headBranch, required this.same});

  @override
  ConsumerState<_CommitsTab> createState() => _CommitsTabState();
}

class _CommitsTabState extends ConsumerState<_CommitsTab> {
  String _log = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (!widget.same) _loadLog();
  }

  @override
  void didUpdateWidget(_CommitsTab old) {
    super.didUpdateWidget(old);
    if (old.baseBranch != widget.baseBranch ||
        old.headBranch != widget.headBranch ||
        old.same != widget.same) {
      if (!widget.same) _loadLog();
    }
  }

  Future<void> _loadLog() async {
    setState(() => _loading = true);
    try {
      final project = ref.read(activeProjectProvider);
      if (project == null) throw Exception('No project');
      final (_, out) = await ref.read(sandboxClientProvider).execToCompletion(
        '/bin/sh',
        ['-lc', "git -C '${project.localPath}' log '${widget.baseBranch}..${widget.headBranch}' --oneline --no-merges"],
      );
      setState(() { _log = out.trim(); _loading = false; });
    } catch (e) {
      setState(() { _log = 'Error: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.same) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Choose different branches to see commits.',
              style: TextStyle(color: Color(0xFF858585), fontSize: 13),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_log.isEmpty) {
      return const Center(child: Text('No commits', style: TextStyle(color: Color(0xFF858585))));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _log.split('\n').map((line) {
        final parts = line.split(' ');
        final sha = parts.isNotEmpty ? parts.first : '';
        final msg = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sha, style: const TextStyle(color: Color(0xFF79C0FF), fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(width: 10),
              Expanded(child: Text(msg, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12))),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Files Changed tab
// ---------------------------------------------------------------------------

class _FilesChangedTab extends StatelessWidget {
  final List<String> changedFiles;
  final String? selectedFile;
  final String selectedFileDiff;
  final bool loadingFileDiff;
  final bool split;
  final bool same;
  final ValueChanged<String> onFileSelected;
  final VoidCallback onToggleSplit;

  const _FilesChangedTab({
    required this.changedFiles,
    required this.selectedFile,
    required this.selectedFileDiff,
    required this.loadingFileDiff,
    required this.split,
    required this.same,
    required this.onFileSelected,
    required this.onToggleSplit,
  });

  @override
  Widget build(BuildContext context) {
    if (same) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Choose different branches to see files changed.',
            style: TextStyle(color: Color(0xFF858585), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        // File list header + split/unified toggle
        Container(
          color: const Color(0xFF252526),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text(
                '${changedFiles.length} file${changedFiles.length == 1 ? '' : 's'} changed',
                style: const TextStyle(color: Color(0xFF858585), fontSize: 11),
              ),
              const Spacer(),
              _ToggleButton(label: 'Unified', active: !split, onTap: split ? onToggleSplit : null),
              const SizedBox(width: 4),
              _ToggleButton(label: 'Split', active: split, onTap: split ? null : onToggleSplit),
            ],
          ),
        ),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File list sidebar
              SizedBox(
                width: 200,
                child: Container(
                  color: const Color(0xFF1E1E1E),
                  child: changedFiles.isEmpty
                      ? const Center(
                          child: Text('No changes', style: TextStyle(color: Color(0xFF858585), fontSize: 12)),
                        )
                      : ListView.builder(
                          itemCount: changedFiles.length,
                          itemBuilder: (ctx, i) {
                            final f = changedFiles[i];
                            final isSelected = f == selectedFile;
                            return InkWell(
                              onTap: () => onFileSelected(f),
                              child: Container(
                                color: isSelected ? const Color(0xFF094771) : null,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                child: Row(
                                  children: [
                                    Icon(Codicons.forFile(f), size: 14, color: const Color(0xFF858585)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        f.split('/').last,
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : const Color(0xFFD4D4D4),
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),

              const VerticalDivider(width: 1, color: Color(0xFF3E3E42)),

              // Diff view
              Expanded(
                child: selectedFile == null
                    ? const Center(
                        child: Text('Select a file to see its diff', style: TextStyle(color: Color(0xFF858585), fontSize: 13)),
                      )
                    : loadingFileDiff
                        ? const Center(child: CircularProgressIndicator())
                        : DiffView(unifiedDiff: selectedFileDiff, split: split),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _ToggleButton({required this.label, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0078D4) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF3E3E42)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF858585),
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PR form panel (description + create button)
// ---------------------------------------------------------------------------

class _PrFormPanel extends StatefulWidget {
  final String title;
  final String body;
  final bool generating;
  final String? descError;
  final bool loading;
  final _Phase phase;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final VoidCallback onRegenerate;
  final VoidCallback onCreatePr;
  final VsCodeColors c;

  const _PrFormPanel({
    required this.title,
    required this.body,
    required this.generating,
    required this.descError,
    required this.loading,
    required this.phase,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onRegenerate,
    required this.onCreatePr,
    required this.c,
  });

  @override
  State<_PrFormPanel> createState() => _PrFormPanelState();
}

class _PrFormPanelState extends State<_PrFormPanel> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.title);
    _bodyCtrl = TextEditingController(text: widget.body);
  }

  @override
  void didUpdateWidget(_PrFormPanel old) {
    super.didUpdateWidget(old);
    if (old.title != widget.title) {
      _titleCtrl.text = widget.title;
    }
    if (old.body != widget.body) {
      _bodyCtrl.text = widget.body;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isSubmitting = widget.phase == _Phase.submitting || widget.loading;

    return Container(
      color: const Color(0xFF252526),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Pull Request', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (widget.descError != null)
                const Text('AI unavailable — using template', style: TextStyle(color: Color(0xFF858585), fontSize: 11)),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: TextButton.icon(
                  onPressed: widget.generating ? null : widget.onRegenerate,
                  icon: widget.generating
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                      : const Icon(Codicons.sparkle, size: 12),
                  label: const Text('AI Description', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0078D4),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            onChanged: widget.onTitleChanged,
            style: TextStyle(color: c.fg, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Pull Request title',
              hintStyle: TextStyle(color: c.fgMuted),
              filled: true,
              fillColor: c.bg,
              isDense: true,
              border: OutlineInputBorder(borderSide: BorderSide(color: c.border)),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyCtrl,
            onChanged: widget.onBodyChanged,
            maxLines: 4,
            style: TextStyle(color: c.fg, fontSize: 12),
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: 'Leave a description…',
              hintStyle: TextStyle(color: c.fgMuted),
              filled: true,
              fillColor: c.bg,
              isDense: true,
              border: OutlineInputBorder(borderSide: BorderSide(color: c.border)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A7F37),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: isSubmitting ? null : widget.onCreatePr,
              icon: isSubmitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Codicons.gitPullRequest, size: 16),
              label: Text(
                isSubmitting ? 'Creating…' : 'Create Pull Request',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

