import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sandbox = ref.watch(sandboxProvider);
    final project = ref.watch(activeProjectProvider);

    return Container(
      height: 22,
      color: const Color(0xFF007ACC),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Codicons.gitBranch, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              project?.branch ?? 'main',
              style: const TextStyle(color: Colors.white, fontSize: 11),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const Spacer(),
          Icon(
            sandbox == SandboxState.ready
                ? Codicons.circleFilled
                : Codicons.circleOutline,
            color: sandbox == SandboxState.error
                ? const Color(0xFFFF6B6B)
                : Colors.white,
            size: 11,
          ),
          const SizedBox(width: 4),
          Text(
            sandbox == SandboxState.extracting ? 'extracting...' : 'vibecli',
            style: TextStyle(
              color: sandbox == SandboxState.error
                  ? const Color(0xFFFF6B6B)
                  : Colors.white,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
