import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'git_graph.dart';

final gitStatusProvider = FutureProvider<GitStatus>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) {
    return const GitStatus(
        branch: '', staged: [], modified: [], untracked: []);
  }
  final client = ref.watch(sandboxClientProvider);
  return client.gitStatus(project.localPath);
});

final commitMessageProvider = StateProvider<String>((ref) => '');

/// Provides the list of files currently in a merge conflict state.
final conflictedFilesProvider = FutureProvider<List<String>>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return [];
  final client = ref.watch(sandboxClientProvider);
  return client.gitConflictedFiles(project.localPath);
});

/// Provides the number of commits the local branch is behind its remote.
final behindCountProvider = FutureProvider<int>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return 0;
  final client = ref.watch(sandboxClientProvider);
  final status = await ref.watch(gitStatusProvider.future);
  final branch = status.branch.isEmpty ? project.branch : status.branch;
  if (branch.isEmpty) return 0;
  return client.gitBehindCount(project.localPath, branch);
});

/// True if a merge is currently in progress in the active project's repo.
final mergeInProgressProvider = FutureProvider<bool>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return false;
  final client = ref.watch(sandboxClientProvider);
  return client.gitMergeInProgress(project.localPath);
});

/// Provides the parsed commit graph (newest-first) for the active project.
///
/// Runs:
///   git log --all --pretty=format:'%H%x1f%h%x1f%P%x1f%an%x1f%D%x1f%s' -n 200
///
/// Each line is split on the ASCII unit-separator (0x1F) into 6 fields:
///   full hash | short hash | parent hashes | author | ref decorations | subject
///
/// Re-fetches whenever [gitStatusProvider] changes so the graph stays in sync
/// after commits / pulls / merges.
final gitGraphProvider = FutureProvider<List<GitCommit>>((ref) async {
  // Establish a dependency so the graph refreshes after git ops.
  ref.watch(gitStatusProvider);

  final project = ref.watch(activeProjectProvider);
  if (project == null) return [];

  final sandbox = ref.watch(sandboxProvider);
  if (sandbox != SandboxState.ready) return [];

  final client = ref.watch(sandboxClientProvider);
  final dir = project.localPath.replaceAll("'", "'\\''" );

  const sep = '\x1f'; // ASCII unit-separator used as field delimiter
  final fmt =
      ['%H', '%h', '%P', '%an', '%D', '%s'].join(sep); // field layout
  final cmd =
      "git -C '$dir' log --all --pretty=format:'$fmt' -n 200 2>/dev/null";

  final (exitCode, output) =
      await client.execToCompletion('/bin/sh', ['-lc', cmd]);

  if (exitCode != 0 || output.trim().isEmpty) return [];

  final commits = <GitCommit>[];
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // Strip the leading single-quote that the shell format adds when using
    // single-quoted format strings (it shouldn't appear, but be defensive).
    final cleaned =
        trimmed.startsWith("'") ? trimmed.substring(1) : trimmed;
    final parts = cleaned.split(sep);
    if (parts.length < 6) continue; // malformed — skip

    final hash = parts[0].trim();
    if (hash.isEmpty) continue;

    final shortHash = parts[1].trim();
    final parentsRaw = parts[2].trim();
    final author = parts[3].trim();
    final refsRaw = parts[4].trim();
    // Subject is everything from field 5 onward (it may contain sep chars
    // if the message itself does, though that's very rare).
    final message = parts.sublist(5).join(sep).trim();

    final parents = parentsRaw.isEmpty
        ? <String>[]
        : parentsRaw
            .split(' ')
            .map((h) => h.trim())
            .where((h) => h.isNotEmpty)
            .toList();

    final refs = refsRaw.isEmpty
        ? <String>[]
        : refsRaw
            .split(',')
            .map((r) => r.trim())
            .where((r) => r.isNotEmpty)
            .toList();

    commits.add(GitCommit(
      hash: hash,
      shortHash: shortHash,
      author: author,
      message: message,
      parents: parents,
      refs: refs,
    ));
  }

  return commits;
});
