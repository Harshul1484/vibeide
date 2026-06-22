// proposed_edits_provider.dart
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
  final String path;       // relative (e.g. "lib/main.dart")
  final String absPath;    // absolute path on the sandbox
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
    WidgetRef ref, List<FileEdit> raw) async {
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

  // Context prefix (up to 3 common lines before the change).
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

  // Context suffix (up to 3 common lines after the change).
  for (var i = oldLines.length - suffixLen;
      i < oldLines.length - suffixLen + ctxAfter;
      i++) {
    sb.writeln(' ${oldLines[i]}');
  }

  return sb.toString();
}
