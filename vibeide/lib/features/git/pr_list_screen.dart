import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'pr_management_provider.dart';
import 'pr_screen.dart';
import 'pr_detail_screen.dart';

class PrListScreen extends ConsumerWidget {
  const PrListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final prs = ref.watch(pullRequestsProvider);
    final api = ref.watch(githubApiProvider);
    final project = ref.watch(activeProjectProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Pull Requests'),
        actions: [
          // Refresh
          IconButton(
            icon: const Icon(Codicons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(pullRequestsProvider),
          ),
          // New PR
          IconButton(
            icon: const Icon(Codicons.add),
            tooltip: 'Create Pull Request',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(context, ref, c, prs, api, project),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    VsCodeColors c,
    AsyncValue<List<Map<String, dynamic>>> prs,
    dynamic api,
    dynamic project,
  ) {
    // Not signed in
    if (api == null) {
      return _EmptyState(
        icon: Codicons.account,
        message: 'Connect GitHub in Settings to view pull requests.',
        c: c,
      );
    }

    // No project
    if (project == null || (project.remoteUrl as String).isEmpty) {
      return _EmptyState(
        icon: Codicons.gitBranch,
        message: 'Open a project with a GitHub remote to view pull requests.',
        c: c,
      );
    }

    return prs.when(
      loading: () => Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
      ),
      error: (e, _) => _EmptyState(
        icon: Codicons.error,
        message: 'Error loading pull requests:\n${e.toString()}',
        c: c,
        iconColor: const Color(0xFFF85149),
      ),
      data: (list) {
        if (list.isEmpty) {
          return _EmptyState(
            icon: Codicons.gitPullRequest,
            message: 'No open pull requests.',
            c: c,
            action: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrScreen()),
              ),
              icon: const Icon(Codicons.add, size: 14),
              label: const Text('Create Pull Request'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0078D4),
              ),
            ),
          );
        }

        final repoUrl = project.remoteUrl as String;

        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
          itemBuilder: (ctx, i) {
            final pr = list[i];
            final number = pr['number'] as int? ?? 0;
            final title = pr['title'] as String? ?? '';
            final user = (pr['user'] as Map<String, dynamic>?)?['login']
                    as String? ??
                '';
            final head =
                (pr['head'] as Map<String, dynamic>?)?['ref'] as String? ?? '';
            final base =
                (pr['base'] as Map<String, dynamic>?)?['ref'] as String? ?? '';
            final isDraft = pr['draft'] as bool? ?? false;

            return _PrRow(
              number: number,
              title: title,
              user: user,
              head: head,
              base: base,
              isDraft: isDraft,
              c: c,
              onTap: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => PrDetailScreen(
                    repoUrl: repoUrl,
                    number: number,
                    initialTitle: title,
                  ),
                ),
              ).then((_) => ref.invalidate(pullRequestsProvider)),
            );
          },
        );
      },
    );
  }
}

// ── PR row ────────────────────────────────────────────────────────────────────

class _PrRow extends StatelessWidget {
  final int number;
  final String title;
  final String user;
  final String head;
  final String base;
  final bool isDraft;
  final VsCodeColors c;
  final VoidCallback onTap;

  const _PrRow({
    required this.number,
    required this.title,
    required this.user,
    required this.head,
    required this.base,
    required this.isDraft,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PR icon
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Codicons.gitPullRequest,
                size: 16,
                color: isDraft
                    ? const Color(0xFF858585)
                    : const Color(0xFF3FB950),
              ),
            ),
            const SizedBox(width: 10),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row with number and draft badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#$number  $title',
                          style: TextStyle(
                            color: c.fg,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isDraft) ...[
                        const SizedBox(width: 6),
                        _DraftBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Subtitle: head → base · by @user
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          head,
                          style: const TextStyle(
                            color: Color(0xFF79C0FF),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        ' → ',
                        style: TextStyle(
                          color: c.fgMuted,
                          fontSize: 11,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          base,
                          style: const TextStyle(
                            color: Color(0xFF79C0FF),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isNotEmpty) ...[
                        Text(
                          ' · by ',
                          style: TextStyle(color: c.fgMuted, fontSize: 11),
                        ),
                        Flexible(
                          child: Text(
                            '@$user',
                            style: TextStyle(
                                color: c.fgMuted, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Codicons.chevronRight, size: 14, color: c.fgMuted),
          ],
        ),
      ),
    );
  }
}

class _DraftBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF30363D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3E3E42)),
      ),
      child: const Text(
        'Draft',
        style: TextStyle(color: Color(0xFF858585), fontSize: 10),
      ),
    );
  }
}

// ── Empty / error state ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VsCodeColors c;
  final Color? iconColor;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.c,
    this.iconColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: iconColor ?? c.fgMuted),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(color: c.fgMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
