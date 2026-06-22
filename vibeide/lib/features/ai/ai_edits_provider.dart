// Service that applies AI-generated [FileEdit]s to the sandbox and
// refreshes dependent providers (editor tabs, file tree, SCM status).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/editor/editor_provider.dart';
import 'package:vibeide/features/explorer/explorer_provider.dart';
import 'package:vibeide/features/git/git_provider.dart';
import 'ai_edits.dart';

/// Applies every [FileEdit] returned by the AI:
///
/// 1. Resolves the absolute path: `${project.localPath}/${edit.path}`.
/// 2. Writes the file to the sandbox via [SandboxClient.writeFile].
/// 3. Opens (or reloads) the file in the editor so the user sees the change.
/// 4. Invalidates [fileTreeProvider] and [gitStatusProvider] so the Explorer
///    and SCM panel refresh and show the modified files.
///
/// Accepts a [WidgetRef] (from ConsumerStatefulWidget) so it can be called
/// directly from the AI panel's `_send` handler.
Future<void> applyEdits(WidgetRef ref, List<FileEdit> edits) async {
  if (edits.isEmpty) return;

  final project = ref.read(activeProjectProvider);
  if (project == null) return;

  final sandboxClient = ref.read(sandboxClientProvider);
  final openTabs = ref.read(openTabsProvider.notifier);
  final currentTabs = ref.read(openTabsProvider);

  for (final edit in edits) {
    // Normalise the relative path: strip any leading "./" or "/".
    var rel = edit.path;
    if (rel.startsWith('./')) rel = rel.substring(2);
    if (rel.startsWith('/')) rel = rel.substring(1);

    final absPath = '${project.localPath}/$rel';

    // Write to sandbox.
    await sandboxClient.writeFile(absPath, edit.content);

    // Open or reload in the editor.
    final alreadyOpen = currentTabs.any((t) => t.path == absPath);
    if (alreadyOpen) {
      await openTabs.reloadFile(absPath);
    } else {
      await openTabs.openFile(absPath);
    }
  }

  // Refresh the file explorer and SCM status.
  ref.invalidate(fileTreeProvider);
  ref.invalidate(gitStatusProvider);
}
