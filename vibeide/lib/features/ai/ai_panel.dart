import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/editor/editor_provider.dart';
import 'package:vibeide/features/git/diff_view.dart';
import 'ai_client.dart';
import 'ai_provider.dart';
import 'ai_edits.dart';
import 'proposed_edits_provider.dart';

class _Message {
  final String role;
  final String content;
  /// Non-null on assistant messages produced in agent mode.
  /// Contains the proposed edits for the review card bound to this bubble.
  final List<ProposedEdit>? proposedEdits;

  const _Message(this.role, this.content, {this.proposedEdits});
}

class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key});

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  String _streaming = '';
  bool _thinking = false;
  bool _agentMode = false;

  // ──────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final budget = ref.watch(tokenBudgetProvider);
    final config = ref.watch(aiConfigProvider);
    final dailyLimit = config.dailyTokenLimit;
    final used = budget.valueOrNull ?? 0;

    return Container(
      color: c.sidebar,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Codicons.robot, size: 14, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  'AI ASSISTANT',
                  style: TextStyle(
                      color: c.fgMuted,
                      fontSize: 11,
                      letterSpacing: 1.2),
                ),
                const Spacer(),
                // Agent-mode toggle
                Tooltip(
                  message: _agentMode
                      ? 'Agent mode ON — AI edits files'
                      : 'Agent mode OFF — chat only',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setState(() => _agentMode = !_agentMode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _agentMode
                            ? c.accent.withAlpha(40)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _agentMode ? c.accent : c.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Codicons.sparkle,
                              size: 11,
                              color:
                                  _agentMode ? c.accent : c.fgMuted),
                          const SizedBox(width: 3),
                          Text(
                            'Agent',
                            style: TextStyle(
                              color:
                                  _agentMode ? c.accent : c.fgMuted,
                              fontSize: 10,
                              fontWeight: _agentMode
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Token-budget counter
                Flexible(
                  child: Text(
                    '${(used / 1000).toStringAsFixed(1)}k / '
                    '${(dailyLimit / 1000).toInt()}k',
                    style: TextStyle(color: c.fgMuted, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          // ── Token budget bar ────────────────────────────────
          LinearProgressIndicator(
            value: dailyLimit > 0 ? used / dailyLimit : 0,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            minHeight: 2,
          ),
          // ── Message list ────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount:
                  _messages.length + (_streaming.isNotEmpty ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _messages.length) {
                  // Live streaming bubble — show prose only (edits not
                  // parsed mid-stream to avoid partial-block artefacts).
                  return _Bubble(
                    role: 'assistant',
                    content: _streaming,
                    streaming: true,
                  );
                }
                final msg = _messages[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bubble(
                      role: msg.role,
                      content: msg.content,
                    ),
                    if (msg.proposedEdits != null &&
                        msg.proposedEdits!.isNotEmpty)
                      _ChangeReviewCard(edits: msg.proposedEdits!),
                  ],
                );
              },
            ),
          ),
          // ── Daily limit banner ──────────────────────────────
          if (!ref.read(tokenBudgetProvider.notifier).canSend(500))
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF5A1D1D),
              child: Text(
                'Daily token limit reached. Resets tomorrow.',
                style: TextStyle(color: c.fg, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          // ── Input row ───────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
              color: c.bg,
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    style: TextStyle(color: c.fg, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _agentMode
                          ? 'Describe the change to make...'
                          : 'Ask AI to write or edit code...',
                      hintStyle:
                          TextStyle(color: c.fgMuted, fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: _thinking
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accent,
                          ),
                        )
                      : IconButton(
                          icon: Icon(Codicons.send,
                              size: 16, color: c.accent),
                          padding: EdgeInsets.zero,
                          onPressed: _send,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Send
  // ──────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _thinking) return;

    final budget = ref.read(tokenBudgetProvider.notifier);
    if (!budget.canSend(AiClient.estimateTokens(text))) return;

    _ctrl.clear();
    setState(() {
      _messages.add(_Message('user', text));
      _thinking = true;
      _streaming = '';
    });

    // Build the history — if agent mode is on, inject the system prompt
    // and a compact project-context message first.
    final List<Map<String, String>> history;
    if (_agentMode) {
      final contextMsg = await _buildAgentContext();
      history = [
        {'role': 'user', 'content': kAgentSystemPrompt},
        {'role': 'assistant', 'content': 'Understood. I am in agent mode and will output VIBE_EDIT blocks when I need to create or modify files.'},
        if (contextMsg.isNotEmpty)
          {'role': 'user', 'content': contextMsg},
        if (contextMsg.isNotEmpty)
          {'role': 'assistant', 'content': 'Got it. I have the project context.'},
        ..._messages
            .map((m) => {'role': m.role, 'content': m.content}),
      ];
    } else {
      history = _messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
    }

    final client = ref.read(aiClientProvider);
    var tokens = AiClient.estimateTokens(text);

    try {
      await for (final chunk in client.chat(history)) {
        if (!mounted) return;
        setState(() => _streaming += chunk);
        tokens += AiClient.estimateTokens(chunk);
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _streaming = 'Error: ${e.toString()}');
      }
    }

    await budget.record(tokens);

    if (!mounted) return;

    // ── Parse edits; build proposed list; show review card ──────
    if (_agentMode) {
      final rawEdits = parseEdits(_streaming);
      final prose = stripEdits(_streaming);

      List<ProposedEdit> proposed = [];
      if (rawEdits.isNotEmpty) {
        try {
          proposed = await buildProposedEdits(ref, rawEdits);
          ref.read(proposedChangesProvider.notifier).state = proposed;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to read files: $e'),
              backgroundColor: const Color(0xFF5A1D1D),
            ));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _messages.add(_Message('assistant', prose,
            proposedEdits: proposed.isEmpty ? null : proposed));
        _streaming = '';
        _thinking = false;
      });
    } else {
      setState(() {
        _messages.add(_Message('assistant', _streaming));
        _streaming = '';
        _thinking = false;
      });
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Agent context builder
  // ──────────────────────────────────────────────────────────────

  /// Builds a lean project-context string for the AI:
  ///   • up to 100 file paths from the project tree
  ///   • the content of the currently-active file (if any)
  Future<String> _buildAgentContext() async {
    final project = ref.read(activeProjectProvider);
    if (project == null) return '';

    final sb = StringBuffer();
    final sandboxClient = ref.read(sandboxClientProvider);

    // File tree (paths only, capped at 100 entries).
    try {
      final tree = await sandboxClient.getTree(project.localPath);
      final paths = collectFilePaths(tree, maxPaths: 100);
      if (paths.isNotEmpty) {
        sb.writeln('Project files (paths relative to repo root):');
        for (final p in paths) {
          sb.writeln('  $p');
        }
        sb.writeln();
      }
    } catch (_) {
      // Tree unavailable — skip silently.
    }

    // Active file content.
    final activePath = ref.read(activeTabPathProvider);
    if (activePath != null && activePath.isNotEmpty) {
      try {
        final content = await sandboxClient.readFile(activePath);
        // Trim the path to make it relative to localPath if possible.
        final rel = activePath.startsWith(project.localPath)
            ? activePath.substring(project.localPath.length + 1)
            : activePath;
        sb.writeln('The user is currently viewing $rel:');
        sb.writeln('```');
        sb.writeln(content);
        sb.writeln('```');
      } catch (_) {
        // File unreadable — skip silently.
      }
    }

    return sb.toString();
  }

  // ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Widgets
// ──────────────────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final String role, content;
  final bool streaming;

  const _Bubble({
    required this.role,
    required this.content,
    this.streaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final isUser = role == 'user';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser ? c.accent.withAlpha(30) : c.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? 'You' : 'AI',
            style: TextStyle(
              color: c.accent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            streaming ? '$content▌' : content,
            style: TextStyle(color: c.fg, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Review card — per-file approve / reject + undo
// ──────────────────────────────────────────────────────────────────────────────

enum _RowState { pending, applied, rejected }

class _ChangeReviewCard extends ConsumerStatefulWidget {
  final List<ProposedEdit> edits;
  const _ChangeReviewCard({required this.edits});

  @override
  ConsumerState<_ChangeReviewCard> createState() => _ChangeReviewCardState();
}

class _ChangeReviewCardState extends ConsumerState<_ChangeReviewCard> {
  late final Map<String, _RowState> _rowState;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rowState = {for (final e in widget.edits) e.absPath: _RowState.pending};
  }

  // ── Helpers ────────────────────────────────────────────────────

  List<ProposedEdit> get _pending =>
      widget.edits
          .where((e) => _rowState[e.absPath] == _RowState.pending)
          .toList();

  List<ProposedEdit> get _applied =>
      widget.edits
          .where((e) => _rowState[e.absPath] == _RowState.applied)
          .toList();

  Future<void> _approve(ProposedEdit e) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await applyOne(ref, e);
      if (mounted) setState(() => _rowState[e.absPath] = _RowState.applied);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Apply failed: $err'),
          backgroundColor: const Color(0xFF5A1D1D),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(ProposedEdit e) async {
    setState(() => _rowState[e.absPath] = _RowState.rejected);
  }

  Future<void> _approveAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final toApply = _pending;
      await applyAll(ref, toApply);
      if (mounted) {
        setState(() {
          for (final e in toApply) {
            _rowState[e.absPath] = _RowState.applied;
          }
        });
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Apply all failed: $err'),
          backgroundColor: const Color(0xFF5A1D1D),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectAll() async {
    setState(() {
      for (final e in _pending) {
        _rowState[e.absPath] = _RowState.rejected;
      }
    });
  }

  Future<void> _undo(ProposedEdit e) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await undoOne(ref, e);
      if (mounted) setState(() => _rowState[e.absPath] = _RowState.pending);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Undo failed: $err'),
          backgroundColor: const Color(0xFF5A1D1D),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final toUndo = _applied;
      await undoAll(ref, toUndo);
      if (mounted) {
        setState(() {
          for (final e in toUndo) {
            _rowState[e.absPath] = _RowState.pending;
          }
        });
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Undo all failed: $err'),
          backgroundColor: const Color(0xFF5A1D1D),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _viewDiff(BuildContext context, ProposedEdit e) {
    final diff = simpleUnifiedDiff(e.oldContent, e.newContent, e.path);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3E3E42),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title row
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Codicons.fileCode,
                      size: 13, color: Color(0xFF858585)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e.path,
                      style: const TextStyle(
                        color: Color(0xFFD4D4D4),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (e.isNew)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B3329),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                            color: Color(0xFF3FB950), fontSize: 9),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF3E3E42)),
            Expanded(child: DiffView(unifiedDiff: diff)),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final hasPending = _pending.isNotEmpty;
    final hasApplied = _applied.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF252526),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                Icon(Codicons.sparkle, size: 12, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  'Proposed changes '
                  '(${widget.edits.length} '
                  'file${widget.edits.length == 1 ? '' : 's'})',
                  style: TextStyle(
                    color: c.fg,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF0078D4)),
                  ),
                if (!_busy && hasPending) ...[
                  const SizedBox(width: 6),
                  _HeaderBtn(
                    label: 'Approve all',
                    icon: Codicons.check,
                    color: const Color(0xFF4CAF50),
                    onTap: _approveAll,
                  ),
                  const SizedBox(width: 4),
                  _HeaderBtn(
                    label: 'Reject all',
                    icon: Codicons.close,
                    color: const Color(0xFFF85149),
                    onTap: _rejectAll,
                  ),
                ],
                if (!_busy && !hasPending && hasApplied) ...[
                  const SizedBox(width: 6),
                  _HeaderBtn(
                    label: 'Undo all',
                    icon: Codicons.refresh,
                    color: c.fgMuted,
                    onTap: _undoAll,
                  ),
                ],
              ],
            ),
          ),
          // ── File rows ─────────────────────────────────────────
          ...widget.edits.map(
            (e) => _FileRow(
              edit: e,
              state: _rowState[e.absPath] ?? _RowState.pending,
              busy: _busy,
              onApprove: () => _approve(e),
              onReject: () => _reject(e),
              onUndo: () => _undo(e),
              onViewDiff: () => _viewDiff(context, e),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HeaderBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color.withAlpha(120)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final ProposedEdit edit;
  final _RowState state;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onUndo;
  final VoidCallback onViewDiff;

  const _FileRow({
    required this.edit,
    required this.state,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onUndo,
    required this.onViewDiff,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    Color rowBg;
    Color pathColor;
    switch (state) {
      case _RowState.applied:
        rowBg = const Color(0xFF1A2E1A);
        pathColor = const Color(0xFF3FB950);
      case _RowState.rejected:
        rowBg = const Color(0xFF2A1A1A);
        pathColor = c.fgMuted;
      case _RowState.pending:
        rowBg = Colors.transparent;
        pathColor = c.fg;
    }

    return Container(
      color: rowBg,
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          // File icon
          Icon(
            Codicons.forFile(edit.path),
            size: 13,
            color: state == _RowState.applied
                ? const Color(0xFF3FB950)
                : c.fgMuted,
          ),
          const SizedBox(width: 6),
          // Badge: NEW or M
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: edit.isNew
                  ? const Color(0xFF1B3329)
                  : const Color(0xFF1F2D3A),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              edit.isNew ? 'NEW' : 'M',
              style: TextStyle(
                color: edit.isNew
                    ? const Color(0xFF3FB950)
                    : const Color(0xFF79C0FF),
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Path (expands, ellipsis on overflow)
          Expanded(
            child: Text(
              edit.path,
              style: TextStyle(color: pathColor, fontSize: 11),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          // State indicator or action buttons
          if (state == _RowState.rejected)
            Text(
              'rejected',
              style: TextStyle(
                  color: c.fgMuted,
                  fontSize: 9,
                  fontStyle: FontStyle.italic),
            )
          else if (state == _RowState.applied)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Codicons.check,
                    size: 12, color: Color(0xFF4CAF50)),
                const SizedBox(width: 4),
                if (!busy)
                  _IconBtn(
                    icon: Codicons.refresh,
                    tooltip: 'Undo',
                    color: const Color(0xFF858585),
                    onTap: onUndo,
                  ),
              ],
            )
          else ...[
            // Pending: view diff + approve + reject
            _IconBtn(
              icon: Codicons.fileCode,
              tooltip: 'View diff',
              color: const Color(0xFF858585),
              onTap: onViewDiff,
            ),
            const SizedBox(width: 2),
            if (!busy) ...[
              _IconBtn(
                icon: Codicons.check,
                tooltip: 'Approve',
                color: const Color(0xFF4CAF50),
                onTap: onApprove,
              ),
              const SizedBox(width: 2),
              _IconBtn(
                icon: Codicons.close,
                tooltip: 'Reject',
                color: const Color(0xFFF85149),
                onTap: onReject,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }
}
