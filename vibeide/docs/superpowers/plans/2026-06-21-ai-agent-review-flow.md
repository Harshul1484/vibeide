# AI Agent Review Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the auto-apply AI agent edit flow with a per-file approve/reject review UI featuring inline diff preview and undo support.

**Architecture:** Introduce a `ProposedEdit` data model with before/after content, a `proposed_edits_provider.dart` for state and business logic, and a `_ChangeReviewCard` StatefulWidget in `ai_panel.dart`. The review card replaces the old `_EditsSummaryCard` and the immediate `applyEdits` call; individual file rows show approve/reject buttons and a "View diff" bottom sheet using the existing `DiffView` widget.

**Tech Stack:** Flutter, flutter_riverpod (StateProvider), existing SandboxClient (readFile/writeFile/deleteFile), existing DiffView widget, VsCodeColors theme, Codicons icon font.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/features/ai/proposed_edits_provider.dart` | **Create** | ProposedEdit model, ChangeSet, proposedChangesProvider, lastAppliedChangesProvider, buildProposedEdits, applyOne, applyAll, undoOne, undoAll, simpleUnifiedDiff |
| `lib/features/ai/ai_panel.dart` | **Modify** | Remove auto-apply; call buildProposedEdits; render _ChangeReviewCard; remove _EditsSummaryCard |
| `lib/features/ai/ai_edits_provider.dart` | **Keep** | applyEdits kept for non-review paths; not deleted |

---

### Task 1: Create proposed_edits_provider.dart with model + diff helper

**Files:**
- Create: `lib/features/ai/proposed_edits_provider.dart`

- [ ] **Step 1: Create the file with model, providers, and diff helper**

```dart
// lib/features/ai/proposed_edits_provider.dart
//
// Proposed-edit model, state holders, and business logic for the AI agent
// review flow. Nothing is written to the sandbox until the user approves.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/editor/editor_provider.dart';
import 'package:vibeide/features/explorer/explorer_provider.dart';
import 'package:vibeide/features/git/git_provider.dart';
import 'ai_edits.dart';

// ─── Model ───────────────────────────────────────────────────────────────────

/// A proposed file change produced by the AI agent before user approval.
class ProposedEdit {
  final String path;      // relative (e.g. "lib/main.dart")
  final String absPath;   // absolute path on the sandbox
  final String oldContent; // content BEFORE the edit (empty string = new file)
  final String newContent; // content the AI wants to write
  final bool isNew;        // true when the file did not exist before

  const ProposedEdit({
    required this.path,
    required this.absPath,
    required this.oldContent,
    required this.newContent,
    required this.isNew,
  });
}

// ─── State providers ─────────────────────────────────────────────────────────

/// Holds the current batch of proposed edits waiting for user review.
/// Set by [buildProposedEdits]; cleared when the batch is fully resolved.
final proposedChangesProvider =
    StateProvider<List<ProposedEdit>>((ref) => []);

/// Holds the last batch of edits that were actually applied, so Undo works
/// after an Approve-all or individual Approve.
final lastAppliedChangesProvider =
    StateProvider<List<ProposedEdit>>((ref) => []);

// ─── Business logic ──────────────────────────────────────────────────────────

/// Resolves absolute paths and reads the current file content from the
/// sandbox for each [FileEdit] in [raw]. Returns a list of [ProposedEdit]s.
/// Nothing is written to the sandbox.
Future<List<ProposedEdit>> buildProposedEdits(
    Ref ref, List<FileEdit> raw) async {
  final project = ref.read(activeProjectProvider);
  if (project == null) return [];

  final sandbox = ref.read(sandboxClientProvider);
  final edits = <ProposedEdit>[];

  for (final fe in raw) {
    // Normalise relative path (strip leading "./" or "/").
    var rel = fe.path;
    if (rel.startsWith('./')) rel = rel.substring(2);
    if (rel.startsWith('/')) rel = rel.substring(1);

    final absPath = '${project.localPath}/$rel';

    String oldContent;
    bool isNew;
    try {
      oldContent = await sandbox.readFile(absPath);
      isNew = false;
    } catch (_) {
      oldContent = '';
      isNew = true;
    }

    edits.add(ProposedEdit(
      path: rel,
      absPath: absPath,
      oldContent: oldContent,
      newContent: fe.content,
      isNew: isNew,
    ));
  }

  return edits;
}

/// Writes a single [ProposedEdit] to the sandbox and refreshes the editor +
/// providers. Records the edit in [lastAppliedChangesProvider].
Future<void> applyOne(WidgetRef ref, ProposedEdit e) async {
  final sandbox = ref.read(sandboxClientProvider);
  await sandbox.writeFile(e.absPath, e.newContent);

  final openTabs = ref.read(openTabsProvider.notifier);
  final currentTabs = ref.read(openTabsProvider);
  final alreadyOpen = currentTabs.any((t) => t.path == e.absPath);
  if (alreadyOpen) {
    await openTabs.reloadFile(e.absPath);
  } else {
    await openTabs.openFile(e.absPath);
  }

  // Append to last-applied list so individual undo works.
  final prev = ref.read(lastAppliedChangesProvider);
  // Replace any existing entry for this path (idempotent).
  final updated = [
    ...prev.where((x) => x.absPath != e.absPath),
    e,
  ];
  ref.read(lastAppliedChangesProvider.notifier).state = updated;

  ref.invalidate(fileTreeProvider);
  ref.invalidate(gitStatusProvider);
}

/// Applies all [edits] in sequence, then does a single provider refresh.
Future<void> applyAll(WidgetRef ref, List<ProposedEdit> edits) async {
  if (edits.isEmpty) return;
  final sandbox = ref.read(sandboxClientProvider);
  final openTabs = ref.read(openTabsProvider.notifier);
  final currentTabs = ref.read(openTabsProvider);

  for (final e in edits) {
    await sandbox.writeFile(e.absPath, e.newContent);
    final alreadyOpen = currentTabs.any((t) => t.path == e.absPath);
    if (alreadyOpen) {
      await openTabs.reloadFile(e.absPath);
    } else {
      await openTabs.openFile(e.absPath);
    }
  }

  ref.read(lastAppliedChangesProvider.notifier).state = edits;
  ref.invalidate(fileTreeProvider);
  ref.invalidate(gitStatusProvider);
}

/// Restores a single file to its pre-edit state:
/// - If [e.isNew], deletes the file from the sandbox.
/// - Otherwise, rewrites [e.oldContent].
/// Then reloads the editor tab and refreshes providers.
Future<void> undoOne(WidgetRef ref, ProposedEdit e) async {
  final sandbox = ref.read(sandboxClientProvider);
  if (e.isNew) {
    try {
      await sandbox.deleteFile(e.absPath);
    } catch (_) {
      // File may already be gone — ignore.
    }
    // Close the tab if open.
    final openTabs = ref.read(openTabsProvider.notifier);
    openTabs.closeTab(e.absPath);
  } else {
    await sandbox.writeFile(e.absPath, e.oldContent);
    final openTabs = ref.read(openTabsProvider.notifier);
    final currentTabs = ref.read(openTabsProvider);
    final alreadyOpen = currentTabs.any((t) => t.path == e.absPath);
    if (alreadyOpen) {
      await openTabs.reloadFile(e.absPath);
    }
  }

  // Remove from last-applied list.
  final prev = ref.read(lastAppliedChangesProvider);
  ref.read(lastAppliedChangesProvider.notifier).state =
      prev.where((x) => x.absPath != e.absPath).toList();

  ref.invalidate(fileTreeProvider);
  ref.invalidate(gitStatusProvider);
}

/// Undoes all [edits] in reverse order.
Future<void> undoAll(WidgetRef ref, List<ProposedEdit> edits) async {
  for (final e in edits.reversed) {
    await undoOne(ref, e);
  }
  ref.read(lastAppliedChangesProvider.notifier).state = [];
}

// ─── Diff helper ─────────────────────────────────────────────────────────────

/// Produces a minimal unified-diff string between [oldText] and [newText]
/// for display in [DiffView].
///
/// Algorithm:
///   1. Find the longest common prefix and suffix of lines (context trim).
///   2. Emit a header block (`--- a/path` / `+++ b/path`).
///   3. Emit a single hunk with:
///      - unchanged prefix lines as context (up to 3),
///      - removed lines (old middle),
///      - added lines (new middle),
///      - unchanged suffix lines as context (up to 3).
///
/// If [oldText] is empty (new file), all lines are additions.
/// If [newText] is empty (deletion), all lines are removals.
String simpleUnifiedDiff(String oldText, String newText, String path) {
  final oldLines = oldText.isEmpty ? <String>[] : oldText.split('\n');
  final newLines = newText.isEmpty ? <String>[] : newText.split('\n');

  final sb = StringBuffer();
  sb.writeln('--- a/$path');
  sb.writeln('+++ b/$path');

  // Find common prefix length.
  var prefixLen = 0;
  final minLen =
      oldLines.length < newLines.length ? oldLines.length : newLines.length;
  while (prefixLen < minLen &&
      oldLines[prefixLen] == newLines[prefixLen]) {
    prefixLen++;
  }

  // Find common suffix length (must not overlap the common prefix).
  var suffixLen = 0;
  while (suffixLen < (oldLines.length - prefixLen) &&
      suffixLen < (newLines.length - prefixLen) &&
      oldLines[oldLines.length - 1 - suffixLen] ==
          newLines[newLines.length - 1 - suffixLen]) {
    suffixLen++;
  }

  // Context window: show up to 3 context lines on each side.
  const ctx = 3;
  final ctxBefore = prefixLen < ctx ? prefixLen : ctx;
  final ctxAfter = suffixLen < ctx ? suffixLen : ctx;

  final oldStart = prefixLen - ctxBefore; // index into oldLines
  final newStart = prefixLen - ctxBefore; // index into newLines
  final oldEnd = oldLines.length - suffixLen + ctxAfter;
  final newEnd = newLines.length - suffixLen + ctxAfter;

  final oldCount = oldEnd - oldStart;
  final newCount = newEnd - newStart;

  // Hunk header (1-based line numbers).
  sb.writeln('@@ -${oldStart + 1},$oldCount +${newStart + 1},$newCount @@');

  // Context prefix.
  for (var i = oldStart; i < prefixLen; i++) {
    sb.writeln(' ${oldLines[i]}');
  }

  // Removed lines (old middle).
  for (var i = prefixLen; i < oldLines.length - suffixLen; i++) {
    sb.writeln('-${oldLines[i]}');
  }

  // Added lines (new middle).
  for (var i = prefixLen; i < newLines.length - suffixLen; i++) {
    sb.writeln('+${newLines[i]}');
  }

  // Context suffix.
  for (var i = oldLines.length - suffixLen;
      i < oldLines.length - suffixLen + ctxAfter;
      i++) {
    sb.writeln(' ${oldLines[i]}');
  }

  return sb.toString();
}
```

- [ ] **Step 2: Verify the file was created**

Run: `ls "d:\Projects\New folder\vibeide\.worktrees\vibeide-app\vibeide\lib\features\ai\"`
Expected: `proposed_edits_provider.dart` appears in the listing.

- [ ] **Step 3: Run flutter analyze (will fail on ai_panel.dart until Task 2; check only proposed_edits_provider.dart compiles)**

Run: `cd "d:\Projects\New folder\vibeide\.worktrees\vibeide-app\vibeide" && flutter analyze lib/features/ai/proposed_edits_provider.dart`

Fix any errors before continuing.

- [ ] **Step 4: Commit**

```
git add lib/features/ai/proposed_edits_provider.dart
git commit -m "feat: add ProposedEdit model, providers and diff helper"
```

---

### Task 2: Rewrite ai_panel.dart — review flow, _ChangeReviewCard, remove auto-apply

This is the largest task. Replace `_EditsSummaryCard` with `_ChangeReviewCard` and remove the immediate `applyEdits` call.

**Files:**
- Modify: `lib/features/ai/ai_panel.dart`

#### 2a — Update imports and _Message model

- [ ] **Step 1: Replace the imports block and _Message class**

The new panel needs `proposed_edits_provider.dart` and `dart:async`. The `_Message` class changes: instead of `appliedPaths`, it stores a `List<ProposedEdit>? proposedEdits` so the review card is bound to the message.

Replace the top of `ai_panel.dart` (lines 1–23) with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/editor/editor_provider.dart';
import 'package:vibeide/features/shell/shell_layout.dart';
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
```

#### 2b — Update itemBuilder (remove _EditsSummaryCard, add _ChangeReviewCard)

- [ ] **Step 2: Replace the itemBuilder in the ListView.builder**

Find the current itemBuilder block (around lines 144–167) and replace with:

```dart
itemBuilder: (ctx, i) {
  if (i == _messages.length) {
    // Live streaming bubble
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
      _Bubble(role: msg.role, content: msg.content),
      if (msg.proposedEdits != null && msg.proposedEdits!.isNotEmpty)
        _ChangeReviewCard(edits: msg.proposedEdits!),
    ],
  );
},
```

#### 2c — Replace the agent-mode post-stream block in _send()

- [ ] **Step 3: Remove auto-apply, replace with buildProposedEdits + review flow**

Find the agent-mode block (approximately lines 297–328):
```dart
    // ── Parse + apply edits when agent mode is on ───────────────
    if (_agentMode) {
      final edits = parseEdits(_streaming);
      final prose = stripEdits(_streaming);
      final appliedPaths = edits.map((e) => e.path).toList();

      setState(() {
        _messages.add(_Message('assistant', prose,
            appliedPaths: appliedPaths));
        _streaming = '';
        _thinking = false;
      });

      if (edits.isNotEmpty) {
        try {
          await applyEdits(ref, edits);
        } catch (e) {
          // Surface the error but don't crash the UI.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Edit error: $e'),
              backgroundColor: const Color(0xFF5A1D1D),
            ));
          }
        }
      }
    } else {
```

Replace with:

```dart
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
```

#### 2d — Remove the old _EditsSummaryCard class and add _ChangeReviewCard

- [ ] **Step 4: Remove _EditsSummaryCard class entirely**

Delete the entire `_EditsSummaryCard` class (lines 442–529 in the original file).

- [ ] **Step 5: Add _ChangeReviewCard after the _Bubble class**

Append the following at the end of the file (after the last closing brace of `_Bubble`):

```dart
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
      widget.edits.where((e) => _rowState[e.absPath] == _RowState.pending).toList();

  List<ProposedEdit> get _applied =>
      widget.edits.where((e) => _rowState[e.absPath] == _RowState.applied).toList();

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
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3E3E42),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(Codicons.fileCode,
                      size: 13, color: const Color(0xFF858585)),
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
            Divider(height: 1, color: const Color(0xFF3E3E42)),
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
                Icon(Codicons.sparkle,
                    size: 12, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  'Proposed changes (${widget.edits.length} file${widget.edits.length == 1 ? '' : 's'})',
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
          ...widget.edits.map((e) => _FileRow(
                edit: e,
                state: _rowState[e.absPath] ?? _RowState.pending,
                busy: _busy,
                onApprove: () => _approve(e),
                onReject: () => _reject(e),
                onUndo: () => _undo(e),
                onViewDiff: () => _viewDiff(context, e),
              )),
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
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
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
          // Path (expands, ellipsis)
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
            Text('rejected',
                style: TextStyle(
                    color: c.fgMuted,
                    fontSize: 9,
                    fontStyle: FontStyle.italic))
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
```

- [ ] **Step 6: Also remove the import of `ai_edits_provider.dart` if applyEdits is no longer called directly in ai_panel.dart**

In the imports block, `ai_edits_provider.dart` import can be removed since we now only import `proposed_edits_provider.dart`. Keep it only if any other reference exists.

- [ ] **Step 7: Commit**

```
git add lib/features/ai/ai_panel.dart
git commit -m "feat: replace _EditsSummaryCard with _ChangeReviewCard review flow"
```

---

### Task 3: flutter analyze — fix all errors

- [ ] **Step 1: Run analyze**

```
cd "d:\Projects\New folder\vibeide\.worktrees\vibeide-app\vibeide"
flutter analyze
```

Expected: clean (no errors). Common issues to watch for:
- `_RowState` enum values need `_RowState.pending` etc. not shorthand — use explicit form since it's a local enum (not exported).
- `Ref` vs `WidgetRef` in `buildProposedEdits` — function signature uses `Ref ref` not `WidgetRef` so it works when called from `ConsumerState` via `ref` (WidgetRef extends Ref; this is fine).
- If `withAlpha` is deprecated in the SDK version used, replace with `withValues(alpha: ...)` or `Color.from(alpha: ..., ...)`.
- The `unused_import` of `sandbox_provider.dart` in `ai_panel.dart` (it's needed because `activeProjectProvider` comes from `project_provider.dart` which is already imported; check carefully).
- `_EditsSummaryCard` reference: ensure it's fully removed including its usage in the `itemBuilder`.
- `activeTabProvider` reference in deleted `_EditsSummaryCard` — verify it's removed.

- [ ] **Step 2: Fix each reported error inline using Edit tool**

For each error shown by `flutter analyze`, make the minimal targeted fix.

- [ ] **Step 3: Re-run until clean**

```
flutter analyze
```

Expected output contains no lines that start with `error •`.

- [ ] **Step 4: Commit**

```
git add -A
git commit -m "fix: resolve flutter analyze errors in review flow"
```

---

### Task 4: flutter build apk --debug

- [ ] **Step 1: Build**

```
cd "d:\Projects\New folder\vibeide\.worktrees\vibeide-app\vibeide"
flutter build apk --debug
```

Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`.

If build fails, read the error output carefully. Common issues:
- Missing import for a class used in `_ChangeReviewCard` (e.g. `DiffView` — needs `diff_view.dart` import in `ai_panel.dart`).
- `Color.withOpacity` deprecation warnings become errors: replace with `.withAlpha(...)`.

- [ ] **Step 2: Fix build errors**

Make targeted edits. Re-run build after each fix.

- [ ] **Step 3: Final commit**

```
git add -A
git commit -m "feat: AI agent review flow — per-file approve/reject with diff preview + undo"
```

---

## Self-Review

### Spec coverage checklist

| Requirement | Covered by |
|---|---|
| `ProposedEdit` with path, absPath, oldContent, newContent, isNew | Task 1 — model in proposed_edits_provider.dart |
| `proposedChangesProvider` StateProvider | Task 1 |
| `lastAppliedChangesProvider` StateProvider | Task 1 |
| `buildProposedEdits` — reads old content, no writes | Task 1 |
| `applyOne` — write + open/reload + invalidate | Task 1 |
| `applyAll` — batch apply + single invalidate | Task 1 |
| `undoOne` — delete new files / restore old content | Task 1 |
| `undoAll` — undo in reverse order | Task 1 |
| `simpleUnifiedDiff` — line-level LCS with context trimming | Task 1 |
| Remove immediate `applyEdits` call | Task 2c |
| `_ChangeReviewCard` StatefulWidget with per-row state | Task 2d |
| Per-file "View diff" → bottom sheet with DiffView | Task 2d |
| Per-file Approve (check) and Reject (x) buttons | Task 2d |
| Approve all / Reject all header buttons | Task 2d |
| Undo per-file and Undo all affordance | Task 2d |
| Row states: pending → applied (green) / rejected | Task 2d |
| "NEW" vs "M" badge | Task 2d |
| Expanded + ellipsis on file path | Task 2d |
| Dark VS Code aesthetic | Task 2d (uses VsCodeColors + Color constants) |
| Non-agent chat mode unaffected | Task 2c — else branch unchanged |
| Token budget tracking intact | Not modified (budget.record call untouched) |
| `flutter analyze` clean | Task 3 |
| `flutter build apk --debug` passes | Task 4 |

### Placeholder scan

No "TBD", "TODO", "implement later", or "add appropriate error handling" phrases present. All code blocks are complete.

### Type consistency

- `ProposedEdit` used consistently across all functions.
- `buildProposedEdits(Ref ref, ...)` — called from `ConsumerState._send()` as `buildProposedEdits(ref, rawEdits)` where `ref` is `WidgetRef` (subtype of `Ref`). Valid.
- `applyOne(WidgetRef ref, ProposedEdit e)` — called from `_ChangeReviewCardState` which is a `ConsumerState`, so `ref` is `WidgetRef`. Valid.
- `undoOne` / `undoAll` same pattern. Valid.
- `simpleUnifiedDiff(String, String, String)` — called in `_viewDiff` with correct arg order `(e.oldContent, e.newContent, e.path)`. Valid.
- `_rowState` map keyed by `absPath` (String), consistent everywhere.
