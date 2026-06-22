import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/editor/editor_provider.dart';
import 'problems_provider.dart';

class ProblemsPanel extends ConsumerWidget {
  const ProblemsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final state = ref.watch(problemsNotifierProvider);
    final activePath = ref.watch(activeTabPathProvider);

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Container(
            height: 30,
            color: const Color(0xFF2D2D2D),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Codicons.warning, size: 14, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  'PROBLEMS',
                  style: TextStyle(
                    color: c.fg,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
                if (!state.isLoading && state.noLinterMessage == null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '(${state.problems.length})',
                      style:
                          TextStyle(color: c.fgMuted, fontSize: 11),
                    ),
                  ),
                const Spacer(),
                if (state.isLoading)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: c.accent,
                    ),
                  )
                else
                  IconButton(
                    icon: Icon(Codicons.refresh,
                        size: 14, color: c.fgMuted),
                    tooltip: 'Re-run Lint',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 24, minHeight: 24),
                    onPressed: activePath == null
                        ? null
                        : () => ref
                            .read(problemsNotifierProvider.notifier)
                            .runLint(activePath),
                  ),
                IconButton(
                  icon:
                      Icon(Codicons.close, size: 14, color: c.fgMuted),
                  tooltip: 'Close Problems',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () =>
                      ref.read(problemsOpenProvider.notifier).state =
                          false,
                ),
              ],
            ),
          ),
          // Body
          Expanded(
            child: _ProblemsBody(state: state, colors: c),
          ),
        ],
      ),
    );
  }
}

class _ProblemsBody extends ConsumerWidget {
  final ProblemsState state;
  final VsCodeColors colors;

  const _ProblemsBody({required this.state, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;

    if (state.isLoading) {
      return Center(
        child: Text('Linting…',
            style: TextStyle(color: c.fgMuted, fontSize: 13)),
      );
    }

    if (state.noLinterMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          state.noLinterMessage!,
          style: TextStyle(color: c.fgMuted, fontSize: 13),
        ),
      );
    }

    if (state.problems.isEmpty) {
      return Center(
        child: Text('No problems detected.',
            style: TextStyle(color: c.fgMuted, fontSize: 13)),
      );
    }

    return ListView.builder(
      itemCount: state.problems.length,
      itemBuilder: (context, i) {
        final p = state.problems[i];
        return _ProblemRow(problem: p, colors: c);
      },
    );
  }
}

class _ProblemRow extends ConsumerWidget {
  final Problem problem;
  final VsCodeColors colors;

  const _ProblemRow({required this.problem, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = colors;

    IconData icon;
    Color iconColor;
    switch (problem.severity) {
      case 'error':
        icon = Codicons.error;
        iconColor = const Color(0xFFF48771);
        break;
      case 'warning':
        icon = Codicons.warning;
        iconColor = const Color(0xFFCCA700);
        break;
      default:
        icon = Codicons.chevronRight;
        iconColor = c.fgMuted;
    }

    final locationText = problem.line != null
        ? (problem.col != null
            ? '${problem.line}:${problem.col}'
            : '${problem.line}')
        : '';

    return InkWell(
      onTap: () {
        // TODO: jump to line in editor when editor supports line navigation.
        final activePath = ref.read(activeTabPathProvider);
        if (activePath == null && problem.file.isNotEmpty) {
          ref.read(activeTabPathProvider.notifier).state = problem.file;
        }
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                problem.message,
                style: TextStyle(color: c.fg, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            if (locationText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                locationText,
                style: TextStyle(color: c.fgMuted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
