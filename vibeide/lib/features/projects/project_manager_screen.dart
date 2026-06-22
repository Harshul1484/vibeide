import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'package:vibeide/features/auth/github_auth.dart';
import 'package:vibeide/features/shell/shell_layout.dart';
import 'package:vibeide/features/settings/settings_screen.dart';
import 'project.dart';
import 'project_provider.dart';
import 'home_providers.dart';

/// Full-screen wrapper so the (panel-style) SettingsScreen can be opened as a
/// standalone page from the home screen, with its own app bar + back button.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Row(children: [
          Icon(Codicons.settingsGear, color: c.accent, size: 18),
          const SizedBox(width: 8),
          const Text('Settings'),
        ]),
      ),
      body: const SettingsScreen(),
    );
  }
}

class ProjectManagerScreen extends ConsumerWidget {
  const ProjectManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final tab = ref.watch(homeTabProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Row(children: [
          Icon(Codicons.symbolFile, color: c.accent, size: 20),
          const SizedBox(width: 8),
          const Text('VibeIDE'),
        ]),
        actions: [
          IconButton(
            icon: Icon(Codicons.settingsGear, color: c.fg, size: 18),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _SettingsPage()),
            ),
          ),
        ],
        // Segmented Projects | GitHub selector under the title.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: _HomeTabBar(active: tab),
        ),
      ),
      body: tab == HomeTab.projects
          ? _ProjectBody()
          // The GitHub repo browser (was the Details pane) is now a first-class
          // tab. onBack=null since it's not a sliding overlay anymore.
          : const _DetailsPane(onBack: null),
    );
  }
}

/// Segmented control in the home app bar: Projects | GitHub.
class _HomeTabBar extends ConsumerWidget {
  final HomeTab active;
  const _HomeTabBar({required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    Widget seg(HomeTab tab, IconData icon, String label) {
      final isActive = active == tab;
      return Expanded(
        child: InkWell(
          onTap: () => ref.read(homeTabProvider.notifier).state = tab,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isActive ? c.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 15, color: isActive ? c.fg : c.fgMuted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? c.fg : c.fgMuted,
                    fontSize: 13,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF252526),
      child: Row(
        children: [
          seg(HomeTab.projects, Codicons.folder, 'Projects'),
          seg(HomeTab.github, Codicons.sourceControl, 'GitHub'),
        ],
      ),
    );
  }
}

// ─── Project list + toolbar ──────────────────────────────────────────────────

class _ProjectBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final projectsAsync = ref.watch(projectsProvider);

    return Column(
      children: [
        _Toolbar(),
        Expanded(
          child: projectsAsync.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: c.accent)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: $e',
                    style: TextStyle(color: c.fgMuted),
                    textAlign: TextAlign.center),
              ),
            ),
            data: (list) {
              final sorted = _sortedProjects(list, ref);
              return sorted.isEmpty
                  ? _EmptyState(
                      onClone: () => _showCloneDialog(context, ref))
                  : _ProjectListView(projects: sorted);
            },
          ),
        ),
      ],
    );
  }

  List<Project> _sortedProjects(List<Project> list, WidgetRef ref) {
    final mode = ref.watch(sortModeProvider);
    final asc = ref.watch(sortAscendingProvider);
    final sorted = [...list];
    sorted.sort((a, b) {
      int cmp;
      if (mode == ProjectSort.name) {
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else {
        cmp = a.lastOpened.compareTo(b.lastOpened);
      }
      return asc ? cmp : -cmp;
    });
    return sorted;
  }
}

// ─── Toolbar ─────────────────────────────────────────────────────────────────

class _Toolbar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final selectedId = ref.watch(selectedProjectIdProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final hasSelection = selectedId != null;
    final viewMode = ref.watch(viewModeProvider);
    final sortMode = ref.watch(sortModeProvider);
    final sortAsc = ref.watch(sortAscendingProvider);

    Project? selectedProject;
    if (hasSelection) {
      selectedProject = projectsAsync.valueOrNull
          ?.where((p) => p.id == selectedId)
          .firstOrNull;
    }

    return Container(
      height: 36,
      color: c.sidebar,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
        children: [
          _ToolbarButton(
            icon: Codicons.add,
            label: 'New',
            onPressed: () => _showCloneDialog(context, ref),
          ),
          _ToolbarDivider(c),
          _ToolbarButton(
            icon: Icons.drive_file_rename_outline,
            label: 'Rename',
            enabled: hasSelection && selectedProject != null,
            onPressed: hasSelection && selectedProject != null
                ? () => _showRenameDialog(context, ref, selectedProject!)
                : null,
          ),
          _ToolbarButton(
            icon: Codicons.trash,
            label: 'Delete',
            enabled: hasSelection && selectedProject != null,
            onPressed: hasSelection && selectedProject != null
                ? () => _confirmDelete(context, ref, selectedProject!)
                : null,
          ),
          _ToolbarDivider(c),
          // Sort button
          _ToolbarPopupButton(
            icon: Icons.sort,
            label: 'Sort',
            c: c,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'name',
                child: Row(children: [
                  if (sortMode == ProjectSort.name)
                    Icon(Codicons.check, size: 14, color: c.accent)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 6),
                  Text('Name', style: TextStyle(color: c.fg, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'date',
                child: Row(children: [
                  if (sortMode == ProjectSort.dateOpened)
                    Icon(Codicons.check, size: 14, color: c.accent)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 6),
                  Text('Date opened',
                      style: TextStyle(color: c.fg, fontSize: 13)),
                ]),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'asc',
                child: Row(children: [
                  if (sortAsc)
                    Icon(Codicons.check, size: 14, color: c.accent)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 6),
                  Text('Ascending',
                      style: TextStyle(color: c.fg, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'desc',
                child: Row(children: [
                  if (!sortAsc)
                    Icon(Codicons.check, size: 14, color: c.accent)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 6),
                  Text('Descending',
                      style: TextStyle(color: c.fg, fontSize: 13)),
                ]),
              ),
            ],
            onSelected: (val) {
              if (val == 'name') {
                ref.read(sortModeProvider.notifier).state = ProjectSort.name;
              } else if (val == 'date') {
                ref.read(sortModeProvider.notifier).state =
                    ProjectSort.dateOpened;
              } else if (val == 'asc') {
                ref.read(sortAscendingProvider.notifier).state = true;
              } else if (val == 'desc') {
                ref.read(sortAscendingProvider.notifier).state = false;
              }
            },
          ),
          // View button
          _ToolbarPopupButton(
            icon: Icons.grid_view,
            label: 'View',
            c: c,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'list',
                child: Row(children: [
                  if (viewMode == ProjectViewMode.list)
                    Icon(Codicons.check, size: 14, color: c.accent)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 6),
                  Text('List', style: TextStyle(color: c.fg, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'large',
                child: Row(children: [
                  if (viewMode == ProjectViewMode.largeIcons)
                    Icon(Codicons.check, size: 14, color: c.accent)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 6),
                  Text('Large icons',
                      style: TextStyle(color: c.fg, fontSize: 13)),
                ]),
              ),
            ],
            onSelected: (val) {
              if (val == 'list') {
                ref.read(viewModeProvider.notifier).state = ProjectViewMode.list;
              } else if (val == 'large') {
                ref.read(viewModeProvider.notifier).state =
                    ProjectViewMode.largeIcons;
              }
            },
          ),
        ],
        ),
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, Project project) {
    final ctrl = TextEditingController(text: project.name);
    final c = Theme.of(context).extension<VsCodeColors>()!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.sidebar,
        title: Text('Rename project', style: TextStyle(color: c.fg)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.fg),
          decoration: InputDecoration(
            hintText: 'Project name',
            hintStyle: TextStyle(color: c.fgMuted),
            enabledBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: c.border)),
            focusedBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: c.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: c.fgMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.accent),
            onPressed: () {
              final name = ctrl.text.trim();
              Navigator.pop(ctx);
              if (name.isNotEmpty) {
                ref.read(projectsProvider.notifier).rename(project.id, name);
                ref.read(selectedProjectIdProvider.notifier).state = null;
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Project project) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.sidebar,
        title: Text('Delete "${project.name}"?',
            style: TextStyle(color: c.fg)),
        content: Text(
          'This removes the project from VibeIDE. The local files are not deleted.',
          style: TextStyle(color: c.fgMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: c.fgMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCC3333)),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(projectsProvider.notifier).remove(project.id);
              ref.read(selectedProjectIdProvider.notifier).state = null;
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final isEnabled = enabled && onPressed != null;
    final color = isEnabled ? c.fg : c.fgMuted;
    return InkWell(
      onTap: isEnabled ? onPressed : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  final VsCodeColors c;
  const _ToolbarDivider(this.c);

  @override
  Widget build(BuildContext context) =>
      VerticalDivider(width: 12, indent: 6, endIndent: 6, color: c.border);
}

class _ToolbarPopupButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VsCodeColors c;
  final List<PopupMenuEntry<String>> Function(BuildContext) itemBuilder;
  final void Function(String) onSelected;

  const _ToolbarPopupButton({
    required this.icon,
    required this.label,
    required this.c,
    required this.itemBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: c.sidebar,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: c.fg),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: c.fg, fontFamily: 'monospace')),
            Icon(Codicons.chevronDown, size: 10, color: c.fgMuted),
          ],
        ),
      ),
    );
  }
}

// ─── Project list ─────────────────────────────────────────────────────────────

class _ProjectListView extends ConsumerWidget {
  final List<Project> projects;
  const _ProjectListView({required this.projects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final viewMode = ref.watch(viewModeProvider);

    if (viewMode == ProjectViewMode.largeIcons) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: projects.length,
        itemBuilder: (context, i) =>
            _ProjectGridTile(project: projects[i]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: projects.length,
      separatorBuilder: (_, __) => Divider(color: c.border, height: 1),
      itemBuilder: (context, i) => _ProjectTile(project: projects[i]),
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  final Project project;
  const _ProjectTile({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final selectedId = ref.watch(selectedProjectIdProvider);
    final isSelected = selectedId == project.id;

    return Container(
      color: isSelected ? c.accent.withValues(alpha: 0.2) : Colors.transparent,
      child: ListTile(
        leading: Icon(
          isSelected ? Codicons.folderOpened : Codicons.folder,
          color: c.accent,
          size: 24,
        ),
        title: Text(project.name, style: TextStyle(color: c.fg)),
        subtitle: Text(
          '${project.remoteUrl}  ⎇ ${project.branch}',
          style: TextStyle(color: c.fgMuted, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _ago(project.lastOpened),
          style: TextStyle(color: c.fgMuted, fontSize: 11),
        ),
        onTap: () {
          if (isSelected) {
            // Second tap on selected → open the project
            _openProject(context, ref, project);
          } else {
            ref.read(selectedProjectIdProvider.notifier).state = project.id;
          }
        },
        onLongPress: () => _showContextMenu(context, ref),
      ),
    );
  }

  void _openProject(BuildContext context, WidgetRef ref, Project project) async {
    ref.read(activeProjectProvider.notifier).state = project;
    await ref.read(projectsProvider.notifier).open(project.id);
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShellLayout()),
      );
    }
    ref.read(sandboxProvider.notifier).boot();
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    // Select the project when long-pressing
    ref.read(selectedProjectIdProvider.notifier).state = project.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.sidebar,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline, color: c.fgMuted),
              title: Text('Rename', style: TextStyle(color: c.fg)),
              onTap: () {
                Navigator.pop(context);
                _showRenameInSheet(context, ref, project, c);
              },
            ),
            ListTile(
              leading: Icon(Codicons.trash, color: c.fgMuted),
              title: Text('Remove project', style: TextStyle(color: c.fg)),
              onTap: () {
                Navigator.pop(context);
                ref.read(projectsProvider.notifier).remove(project.id);
                ref.read(selectedProjectIdProvider.notifier).state = null;
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameInSheet(
      BuildContext context, WidgetRef ref, Project project, VsCodeColors c) {
    final ctrl = TextEditingController(text: project.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.sidebar,
        title: Text('Rename project', style: TextStyle(color: c.fg)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.fg),
          decoration: InputDecoration(
            hintText: 'Project name',
            hintStyle: TextStyle(color: c.fgMuted),
            enabledBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: c.border)),
            focusedBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: c.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: c.fgMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.accent),
            onPressed: () {
              final name = ctrl.text.trim();
              Navigator.pop(ctx);
              if (name.isNotEmpty) {
                ref.read(projectsProvider.notifier).rename(project.id, name);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    if (d.inMinutes > 0) return '${d.inMinutes}m ago';
    return 'just now';
  }
}

class _ProjectGridTile extends ConsumerWidget {
  final Project project;
  const _ProjectGridTile({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final selectedId = ref.watch(selectedProjectIdProvider);
    final isSelected = selectedId == project.id;

    return GestureDetector(
      onTap: () {
        if (isSelected) {
          ref.read(activeProjectProvider.notifier).state = project;
          ref.read(projectsProvider.notifier).open(project.id);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ShellLayout()),
          );
          ref.read(sandboxProvider.notifier).boot();
        } else {
          ref.read(selectedProjectIdProvider.notifier).state = project.id;
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? c.accent.withValues(alpha: 0.2) : Colors.transparent,
          border: isSelected
              ? Border.all(color: c.accent, width: 1)
              : Border.all(color: Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Codicons.folder, color: c.accent, size: 48),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                project.name,
                style: TextStyle(color: c.fg, fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Details pane ─────────────────────────────────────────────────────────────

class _DetailsPane extends ConsumerWidget {
  final VoidCallback? onBack;
  const _DetailsPane({this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final authAsync = ref.watch(authProvider);

    return Container(
      color: c.sidebar,
      child: Column(
        children: [
          // Header
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                if (onBack != null) ...[
                  IconButton(
                    icon: Icon(Codicons.chevronRight, color: c.fgMuted,
                        size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                    onPressed: onBack,
                    tooltip: 'Close details',
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(Codicons.sourceControl, color: c.accent, size: 16),
                const SizedBox(width: 6),
                Text(
                  'GitHub',
                  style: TextStyle(
                      color: c.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                authAsync.when(
                  data: (token) => token != null
                      ? IconButton(
                          icon: Icon(Codicons.refresh,
                              color: c.fgMuted, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                          onPressed: () {
                            ref.invalidate(ownersProvider);
                          },
                          tooltip: 'Refresh',
                        )
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Builder(builder: (context) {
              // While a device-flow sign-in is in progress, show the user code
              // (so the user can type it into github.com/login/device) instead
              // of a bare spinner.
              final device = ref.watch(deviceAuthProvider);
              if (device.deviceCode != null) {
                return _DeviceCodeView(code: device.deviceCode!);
              }
              if (device.error != null) {
                return _AuthErrorView(error: device.error!);
              }

              return authAsync.when(
                loading: () =>
                    Center(child: CircularProgressIndicator(color: c.accent)),
                error: (e, _) => Center(
                  child: Text('Auth error: $e',
                      style: TextStyle(color: c.fgMuted, fontSize: 12)),
                ),
                data: (token) {
                  if (token == null) {
                    return _NotConnectedView();
                  }
                  return _ConnectedView();
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _NotConnectedView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Codicons.account, size: 48, color: c.fgMuted),
            const SizedBox(height: 16),
            Text(
              'Connect GitHub to browse your repos',
              style: TextStyle(color: c.fgMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0078D4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Codicons.account, size: 16),
              label: const Text('Connect GitHub',
                  style: TextStyle(fontSize: 13)),
              onPressed: () =>
                  ref.read(authProvider.notifier).signIn(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the device-flow user code prominently so the user can type it into
/// github.com/login/device, with a spinner while we poll for approval.
class _DeviceCodeView extends ConsumerWidget {
  final DeviceCodeResponse code;
  const _DeviceCodeView({required this.code});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter this code at github.com/login/device:',
            style: TextStyle(color: c.fgMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Big tappable code (tap to copy)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code.userCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied')),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.accent, width: 2),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  code.userCode,
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Tap the code to copy',
              style: TextStyle(color: c.fgMuted, fontSize: 10),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Codicons.link, size: 16),
              label: const Text('Open GitHub page',
                  style: TextStyle(fontSize: 13)),
              onPressed: () =>
                  GitHubDeviceAuth().openVerificationUrl(code.verificationUri),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: c.accent),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Waiting for approval...',
                  style: TextStyle(color: c.fgMuted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                ref.read(authProvider.notifier).cancelSignIn(),
            child: Text('Cancel', style: TextStyle(color: c.fgMuted)),
          ),
        ],
      ),
    );
  }
}

class _AuthErrorView extends ConsumerWidget {
  final String error;
  const _AuthErrorView({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error,
                style: const TextStyle(
                    color: Color(0xFFFF6B6B), fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0078D4)),
              onPressed: () =>
                  ref.read(authProvider.notifier).signIn(),
              child: const Text('Try again'),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(authProvider.notifier).cancelSignIn(),
              child: Text('Cancel', style: TextStyle(color: c.fgMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final ownersAsync = ref.watch(ownersProvider);

    return ownersAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: c.accent)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load: $e',
              style: TextStyle(color: c.fgMuted, fontSize: 12),
              textAlign: TextAlign.center),
        ),
      ),
      data: (owners) {
        if (owners.isEmpty) {
          return Center(
            child: Text('No GitHub accounts found',
                style: TextStyle(color: c.fgMuted, fontSize: 13)),
          );
        }

        // Resolve the selected owner (default to the first = user account).
        final selectedLogin = ref.watch(selectedOwnerLoginProvider);
        final selected = owners.firstWhere(
          (o) => o.login == selectedLogin,
          orElse: () => owners.first,
        );

        // Two columns: narrow avatar bar on the left, repos on the right.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OwnerIconBar(owners: owners, selected: selected),
            VerticalDivider(width: 1, color: c.border),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected owner name header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        Icon(
                          selected.isUser
                              ? Codicons.account
                              : Icons.group_outlined,
                          color: c.fgMuted,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            selected.login,
                            style: TextStyle(
                                color: c.fg,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _OwnerRepoList(owner: selected),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Narrow vertical bar of circular owner avatars (account + orgs), VS Code
/// activity-bar / Slack workspace-switcher style. Tapping selects the owner.
class _OwnerIconBar extends ConsumerWidget {
  final List<GitHubOwner> owners;
  final GitHubOwner selected;
  const _OwnerIconBar({required this.owners, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    return Container(
      width: 56,
      color: const Color(0xFF2D2D2D),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: owners.length,
        itemBuilder: (context, i) {
          final owner = owners[i];
          final isSelected = owner.login == selected.login;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Tooltip(
              message: owner.login,
              child: GestureDetector(
                onTap: () => ref
                    .read(selectedOwnerLoginProvider.notifier)
                    .state = owner.login,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Selection indicator bar on the left edge
                    if (isSelected)
                      Container(
                        width: 3,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    Center(
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.sidebar,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? c.accent : Colors.transparent,
                            width: 2,
                          ),
                          image: owner.avatarUrl.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(owner.avatarUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: owner.avatarUrl.isEmpty
                            ? Icon(
                                owner.isUser
                                    ? Codicons.account
                                    : Icons.group_outlined,
                                color: c.fgMuted,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OwnerRepoList extends ConsumerWidget {
  final GitHubOwner owner;
  const _OwnerRepoList({required this.owner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final reposAsync = ref.watch(reposProvider(owner.login));
    final projectsAsync = ref.watch(projectsProvider);
    final clonedUrls = projectsAsync.valueOrNull
            ?.map((p) => _normalizeUrl(p.remoteUrl))
            .toSet() ??
        {};

    return reposAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: c.accent)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Error: $e',
            style: TextStyle(color: c.fgMuted, fontSize: 11)),
      ),
      data: (repos) {
        if (repos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text('No repositories',
                style: TextStyle(color: c.fgMuted, fontSize: 12)),
          );
        }

        final cloned = repos
            .where((r) => clonedUrls.contains(_normalizeUrl(r.cloneUrl)))
            .toList();
        final notCloned = repos
            .where((r) => !clonedUrls.contains(_normalizeUrl(r.cloneUrl)))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cloned.isNotEmpty) ...[
              _SectionHeader('CLONED', c),
              ...cloned.map((r) => _RepoTile(
                    repo: r,
                    isCloned: true,
                    clonedProject: projectsAsync.valueOrNull?.firstWhere(
                      (p) =>
                          _normalizeUrl(p.remoteUrl) ==
                          _normalizeUrl(r.cloneUrl),
                    ),
                  )),
            ],
            if (notCloned.isNotEmpty) ...[
              _SectionHeader('NOT CLONED', c),
              ...notCloned.map((r) => _RepoTile(
                    repo: r,
                    isCloned: false,
                    clonedProject: null,
                  )),
            ],
          ],
        );
      },
    );
  }

  static String _normalizeUrl(String url) {
    var u = url.trim().toLowerCase();
    if (u.endsWith('.git')) u = u.substring(0, u.length - 4);
    return u;
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final VsCodeColors c;
  const _SectionHeader(this.label, this.c);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: c.fgMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RepoTile extends ConsumerWidget {
  final GitHubRepo repo;
  final bool isCloned;
  final Project? clonedProject;
  const _RepoTile({
    required this.repo,
    required this.isCloned,
    required this.clonedProject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        isCloned ? Codicons.folderOpened : Codicons.cloudDownload,
        color: isCloned ? c.accent : c.fgMuted,
        size: 16,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              repo.name,
              style: TextStyle(color: c.fg, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (repo.isPrivate) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock_outline, size: 11, color: c.fgMuted),
          ],
        ],
      ),
      subtitle: repo.description != null && repo.description!.isNotEmpty
          ? Text(
              repo.description!,
              style: TextStyle(color: c.fgMuted, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () => _onTap(context, ref),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    if (isCloned && clonedProject != null) {
      // Open the existing project
      ref.read(activeProjectProvider.notifier).state = clonedProject;
      ref.read(projectsProvider.notifier).open(clonedProject!.id);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShellLayout()),
      );
      ref.read(sandboxProvider.notifier).boot();
    } else {
      // Start a clone
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final project = Project(
        id: id,
        name: repo.name,
        remoteUrl: repo.cloneUrl,
        branch: repo.defaultBranch,
        localPath: '/root/projects/$id',
        lastOpened: DateTime.now(),
      );
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CloneProgressDialog(project: project),
      );
    }
  }
}

// ─── Clone dialog (unchanged) ─────────────────────────────────────────────────

/// Boots the sandbox (if needed) then runs `git clone`, streaming progress.
/// Only saves the project + navigates into it once the clone succeeds.
class _CloneProgressDialog extends ConsumerStatefulWidget {
  final Project project;
  const _CloneProgressDialog({required this.project});

  @override
  ConsumerState<_CloneProgressDialog> createState() =>
      _CloneProgressDialogState();
}

// Playful, Claude-style "thinking" verbs shown while the sandbox boots and
// the repo clones. One is picked at random and rotated every few seconds.
const _thinkingPhrases = <String>[
  'Pondering',
  'Conjuring',
  'Untangling threads',
  'Summoning the sandbox',
  'Warming up the engines',
  'Herding bytes',
  'Spelunking the repo',
  'Brewing',
  'Tinkering',
  'Wrangling files',
  'Assembling',
  'Noodling',
  'Percolating',
  'Materializing',
  'Crunching',
  'Whittling',
];

class _CloneProgressDialogState extends ConsumerState<_CloneProgressDialog> {
  String _status = 'Pondering';
  String? _error;
  // 0..1 progress; null = indeterminate (boot / apk / connecting stages).
  double? _progress;
  bool _done = false;
  Timer? _phraseTimer;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _startPhraseRotation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _phraseTimer?.cancel();
    super.dispose();
  }

  void _startPhraseRotation() {
    _status = _thinkingPhrases[_rng.nextInt(_thinkingPhrases.length)];
    _phraseTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _status = _thinkingPhrases[_rng.nextInt(_thinkingPhrases.length)];
      });
    });
  }

  Future<void> _run() async {
    final sandbox = ref.read(sandboxProvider.notifier);
    final client = ref.read(sandboxClientProvider);

    try {
      if (ref.read(sandboxProvider) != SandboxState.ready) {
        setState(() => _progress = null);
        await sandbox.boot();
        if (ref.read(sandboxProvider) != SandboxState.ready) {
          throw Exception(
              sandbox.lastError ??
                  'Sandbox failed to start. Check the device supports proot.');
        }
      }

      setState(() => _progress = null);
      await client.ensureGit();

      final token = ref.read(githubTokenProvider);
      await for (final line in client.gitClone(
        widget.project.remoteUrl,
        widget.project.localPath,
        token: token,
      )) {
        if (!mounted) return;
        _parseProgress(line.trim());
      }

      await ref.read(projectsProvider.notifier).add(widget.project);
      ref.read(activeProjectProvider.notifier).state = widget.project;

      if (!mounted) return;
      // Brief, honest success beat so a fast clone reads as "done" rather than
      // flashing past. Fill the bar to 100% + show a check, then open the IDE.
      _phraseTimer?.cancel();
      setState(() {
        _progress = 1.0;
        _status = 'Done';
        _done = true;
      });
      await Future.delayed(const Duration(milliseconds: 650));

      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShellLayout()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// Parse the percentage out of git's progress lines to drive the bar.
  /// The status label stays a rotating "thinking" phrase — we don't surface
  /// the raw git stage text. e.g. "Receiving objects:  62% (124/200)" -> 0.62
  void _parseProgress(String line) {
    final pctMatch = RegExp(r'(\d+)%').firstMatch(line);
    if (pctMatch != null) {
      setState(() => _progress = int.parse(pctMatch.group(1)!) / 100.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    return AlertDialog(
      backgroundColor: c.sidebar,
      title: Text(
        _error != null ? 'Clone failed' : 'Cloning ${widget.project.name}',
        style: TextStyle(color: c.fg, fontSize: 15),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error == null) ...[
                // Stage + percentage row
                Row(
                  children: [
                    if (_done) ...[
                      const Icon(Codicons.check,
                          size: 14, color: Color(0xFF3FB950)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        _done ? 'Done' : '$_status…',
                        style: TextStyle(
                            color: _done
                                ? const Color(0xFF3FB950)
                                : c.fgMuted,
                            fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_progress != null)
                      Text(
                        '${(_progress! * 100).round()}%',
                        style: TextStyle(
                            color: c.fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // Segmented tick-style progress bar.
                _SegmentedProgressBar(
                    value: _progress,
                    color: _done ? const Color(0xFF3FB950) : c.accent,
                    trackColor: c.border),
              ] else
                Text(
                  _error!,
                  style: const TextStyle(
                      color: Color(0xFFFF6B6B), fontSize: 12),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: c.fgMuted)),
          ),
      ],
    );
  }
}

/// A segmented "tick" progress bar — discrete vertical bars where the filled
/// fraction is [color] and the rest is [trackColor]. When [value] is null it
/// shows a slow indeterminate sweep.
class _SegmentedProgressBar extends StatefulWidget {
  final double? value;
  final Color color;
  final Color trackColor;
  const _SegmentedProgressBar({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  @override
  State<_SegmentedProgressBar> createState() =>
      _SegmentedProgressBarState();
}

class _SegmentedProgressBarState extends State<_SegmentedProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const int n = 28;

  @override
  Widget build(BuildContext context) {
    Widget bar(int filledCount, {Set<int>? pulse}) {
      return Row(
        children: List.generate(n, (i) {
          final filled = i < filledCount;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                height: 18,
                decoration: BoxDecoration(
                  color: (pulse?.contains(i) ?? false)
                      ? widget.color
                      : (filled ? widget.color : widget.trackColor),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          );
        }),
      );
    }

    // Determinate: fill segments proportional to value.
    if (widget.value != null) {
      final filled = (widget.value!.clamp(0.0, 1.0) * n).round();
      return bar(filled);
    }

    // Indeterminate: a small group of lit segments sweeps across.
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final head = (_ctrl.value * n).floor();
        final pulse = {
          head % n,
          (head + 1) % n,
          (head + 2) % n,
        };
        return bar(0, pulse: pulse);
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onClone;
  const _EmptyState({required this.onClone});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Codicons.folder, size: 72, color: c.fgMuted),
          const SizedBox(height: 16),
          Text('No projects yet',
              style: TextStyle(color: c.fgMuted, fontSize: 16)),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0078D4),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: const Icon(Codicons.cloudDownload, size: 18),
              label: const Text(
                'Clone from GitHub',
                style: TextStyle(fontSize: 14),
              ),
              onPressed: onClone,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top-level helper (needed by _Toolbar and _ProjectBody) ──────────────────

void _showCloneDialog(BuildContext context, WidgetRef ref) {
  final urlCtrl = TextEditingController();
  final c = Theme.of(context).extension<VsCodeColors>()!;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.sidebar,
      title: Text('Clone Repository', style: TextStyle(color: c.fg)),
      content: TextField(
        controller: urlCtrl,
        autofocus: true,
        style: TextStyle(color: c.fg),
        decoration: InputDecoration(
          hintText: 'https://github.com/user/repo',
          hintStyle: TextStyle(color: c.fgMuted),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: c.border),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: TextStyle(color: c.fgMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: c.accent),
          onPressed: () {
            final url = urlCtrl.text.trim();
            Navigator.pop(ctx);
            if (url.isNotEmpty) {
              _startClone(context, ref, url);
            }
          },
          child: const Text('Clone'),
        ),
      ],
    ),
  );
}

void _startClone(BuildContext context, WidgetRef ref, String url) {
  final segments = url.split('/');
  final repoName = segments.last
      .replaceAll('.git', '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '-');
  final id = DateTime.now().millisecondsSinceEpoch.toString();
  final localPath = '/root/projects/$id';

  final project = Project(
    id: id,
    name: repoName,
    remoteUrl: url,
    branch: 'main',
    localPath: localPath,
    lastOpened: DateTime.now(),
  );

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CloneProgressDialog(project: project),
  );
}
