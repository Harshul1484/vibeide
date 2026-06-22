import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';

final fileTreeProvider = FutureProvider<FileNode>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) {
    return const FileNode(name: '', path: '/', isDir: true);
  }
  final client = ref.watch(sandboxClientProvider);
  return client.getTree(project.localPath);
});

final selectedFileProvider = StateProvider<String?>((ref) => null);
