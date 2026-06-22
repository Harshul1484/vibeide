import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';

/// Lists open PRs for the active project's remote repo.
final pullRequestsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(githubApiProvider);
  final project = ref.watch(activeProjectProvider);

  if (api == null || project == null || project.remoteUrl.isEmpty) {
    return [];
  }

  return api.listPullRequests(project.remoteUrl);
});

/// Fetches detail for a single PR (additions, deletions, mergeable, body …).
final prDetailProvider = FutureProvider.family<Map<String, dynamic>,
    ({String repoUrl, int number})>((ref, args) async {
  final api = ref.watch(githubApiProvider);
  if (api == null) throw Exception('Not signed in to GitHub');
  return api.getPullRequest(args.repoUrl, args.number);
});

/// Fetches the file list (with patches) for a single PR.
final prFilesProvider = FutureProvider.family<List<Map<String, dynamic>>,
    ({String repoUrl, int number})>((ref, args) async {
  final api = ref.watch(githubApiProvider);
  if (api == null) throw Exception('Not signed in to GitHub');
  return api.getPullRequestFiles(args.repoUrl, args.number);
});

/// Fetches the combined CI status for a ref (branch / SHA).
final prCiStatusProvider = FutureProvider.family<Map<String, dynamic>,
    ({String repoUrl, String ref})>((ref, args) async {
  final api = ref.watch(githubApiProvider);
  if (api == null) return {'state': 'unknown'};
  return api.getCombinedStatus(args.repoUrl, args.ref);
});
