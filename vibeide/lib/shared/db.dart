import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/projects/project_repo.dart';

// Override this in ProviderScope with a real initialized ProjectRepo
final projectRepoProvider = Provider<ProjectRepo>(
  (ref) => throw UnimplementedError('projectRepoProvider not overridden'),
);
