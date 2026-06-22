import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'package:vibeide/features/auth/github_auth.dart';

// ── Sort / View / UI State ──────────────────────────────────────────────────

enum ProjectSort { name, dateOpened }

final sortModeProvider =
    StateProvider<ProjectSort>((ref) => ProjectSort.dateOpened);

final sortAscendingProvider = StateProvider<bool>((ref) => false);

enum ProjectViewMode { list, largeIcons }

final viewModeProvider =
    StateProvider<ProjectViewMode>((ref) => ProjectViewMode.list);

final detailsPaneOpenProvider = StateProvider<bool>((ref) => false);

final selectedProjectIdProvider = StateProvider<String?>((ref) => null);

/// Home screen top-level tab: local Projects vs. GitHub repo browser.
enum HomeTab { projects, github }

final homeTabProvider = StateProvider<HomeTab>((ref) => HomeTab.projects);

/// Which owner (account/org) is selected in the Details pane's left icon bar.
/// null = show the first owner (the user account) by default.
final selectedOwnerLoginProvider = StateProvider<String?>((ref) => null);

// ── GitHub data providers ───────────────────────────────────────────────────

final ownersProvider = FutureProvider<List<GitHubOwner>>((ref) async {
  final api = ref.watch(githubApiProvider);
  if (api == null) return [];
  return api.getOwners();
});

final reposProvider =
    FutureProvider.family<List<GitHubRepo>, String>((ref, ownerLogin) async {
  final api = ref.watch(githubApiProvider);
  if (api == null) return [];
  final owners = await ref.watch(ownersProvider.future);
  final owner = owners.firstWhere((o) => o.login == ownerLogin);
  return api.getRepos(owner);
});
