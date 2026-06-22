import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/db.dart';
import 'project.dart';

class ProjectsNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    final repo = ref.read(projectRepoProvider);
    return repo.listAll();
  }

  Future<void> add(Project p) async {
    await ref.read(projectRepoProvider).insert(p);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(projectRepoProvider).delete(id);
    ref.invalidateSelf();
  }

  Future<void> open(String id) async {
    await ref.read(projectRepoProvider).touchLastOpened(id);
    ref.invalidateSelf();
  }

  Future<void> updateBranch(String id, String branch) async {
    await ref.read(projectRepoProvider).updateBranch(id, branch);
    ref.invalidateSelf();
  }

  Future<void> rename(String id, String name) async {
    await ref.read(projectRepoProvider).updateName(id, name);
    ref.invalidateSelf();
  }
}

final projectsProvider =
    AsyncNotifierProvider<ProjectsNotifier, List<Project>>(
        ProjectsNotifier.new);

final activeProjectProvider = StateProvider<Project?>((ref) => null);
