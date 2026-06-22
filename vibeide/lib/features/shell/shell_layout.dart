import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/explorer/explorer_panel.dart';
import 'package:vibeide/features/editor/editor_panel.dart';
import 'package:vibeide/features/terminal/terminal_panel.dart';
import 'package:vibeide/features/ai/ai_panel.dart';
import 'package:vibeide/features/git/scm_panel.dart';
import 'package:vibeide/features/settings/settings_screen.dart';
import 'package:vibeide/features/extensions/extensions_panel.dart';
import 'package:vibeide/features/problems/problems_panel.dart';
import 'package:vibeide/features/problems/problems_provider.dart';
import 'package:vibeide/features/preview/preview_panel.dart';
import 'package:vibeide/features/preview/preview_provider.dart';
import 'package:vibeide/features/search/search_panel.dart';
import 'package:vibeide/features/command_palette/command_palette.dart';
import 'status_bar.dart';

// editor = the code editor; explorer/git/ai/extensions/settings open as the side panel.
enum ActivityTab { editor, explorer, search, git, ai, extensions, settings }

final activeTabProvider =
    StateProvider<ActivityTab>((ref) => ActivityTab.editor);
final terminalOpenProvider = StateProvider<bool>((ref) => false);

/// User-set height of the bottom (terminal/problems) panel, in logical pixels.
/// null = use the default (~40% of available height). Set by dragging the
/// panel's top edge; clamped to a sane range against the live layout.
final bottomPanelHeightProvider = StateProvider<double?>((ref) => null);

class ShellLayout extends ConsumerWidget {
  const ShellLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final activeTab = ref.watch(activeTabProvider);
    final terminalOpen = ref.watch(terminalOpenProvider);
    final problemsOpen = ref.watch(problemsOpenProvider);
    final previewOpen = ref.watch(previewOpenProvider);

    // Bottom panel is visible when either terminal or problems is open.
    final bottomOpen = terminalOpen || problemsOpen;

    // The wide breakpoint: tablets/landscape get the side-by-side layout,
    // phones get a single full-width panel switched via the activity bar.
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: c.bg,
      // Let the body resize when the keyboard appears so nothing overflows.
      resizeToAvoidBottomInset: true,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyP,
              control: true, shift: true): () =>
              showCommandPalette(context, ref),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          // Bottom panel takes ~40% of available height by default, but the
          // user can drag its top edge to resize. It's never more than
          // (available - 160) so the editor area + status bar always keep at
          // least 160px and the Column can't overflow.
          final maxPanel =
              (box.maxHeight - 160).clamp(80.0, box.maxHeight).toDouble();
          final userHeight = ref.watch(bottomPanelHeightProvider);
          final panelHeight = (userHeight ?? box.maxHeight * 0.4)
              .clamp(80.0, maxPanel)
              .toDouble();
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _ActivityBar(),
                    VerticalDivider(width: 1, color: c.border),
                    Expanded(
                      child: isWide
                          ? _WideLayout(
                              activeTab: activeTab,
                              previewOpen: previewOpen)
                          : _NarrowLayout(
                              activeTab: activeTab,
                              previewOpen: previewOpen),
                    ),
                  ],
                ),
              ),
              if (bottomOpen) ...[
                // Draggable resize handle on the panel's top edge.
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) {
                      final notifier =
                          ref.read(bottomPanelHeightProvider.notifier);
                      // Dragging up (negative dy) grows the panel.
                      final next = (panelHeight - d.delta.dy)
                          .clamp(80.0, maxPanel)
                          .toDouble();
                      notifier.state = next;
                    },
                    child: SizedBox(
                      height: 10,
                      child: Center(
                        child: Container(
                          height: 1,
                          color: c.border,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(top: 1.5),
                              decoration: BoxDecoration(
                                color: c.fgMuted.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: panelHeight,
                  child: _BottomPanel(
                    terminalOpen: terminalOpen,
                    problemsOpen: problemsOpen,
                  ),
                ),
              ],
              const StatusBar(),
            ],
          );
        }),
      ),
        ),
      ),
    );
  }
}

/// Which bottom-panel tab is active.
enum BottomTab { problems, output, terminal }

final bottomActiveTabProvider =
    StateProvider<BottomTab>((ref) => BottomTab.terminal);

/// Bottom panel with a persistent VS Code-style tab bar:
/// PROBLEMS · OUTPUT · TERMINAL. The active tab is underlined.
class _BottomPanel extends ConsumerWidget {
  final bool terminalOpen;
  final bool problemsOpen;

  const _BottomPanel({
    required this.terminalOpen,
    required this.problemsOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final active = ref.watch(bottomActiveTabProvider);

    // When the Problems panel is explicitly opened, focus its tab.
    ref.listen<bool>(problemsOpenProvider, (_, next) {
      if (next) {
        ref.read(bottomActiveTabProvider.notifier).state = BottomTab.problems;
      }
    });

    return Column(
      children: [
        // Persistent tab bar
        Container(
          height: 30,
          color: const Color(0xFF1E1E1E),
          child: Row(
            children: [
              // Tabs scroll horizontally so they never overflow in landscape.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      _BottomTab(
                        label: 'PROBLEMS',
                        isActive: active == BottomTab.problems,
                        onTap: () => ref
                            .read(bottomActiveTabProvider.notifier)
                            .state = BottomTab.problems,
                        colors: c,
                      ),
                      _BottomTab(
                        label: 'OUTPUT',
                        isActive: active == BottomTab.output,
                        onTap: () => ref
                            .read(bottomActiveTabProvider.notifier)
                            .state = BottomTab.output,
                        colors: c,
                      ),
                      _BottomTab(
                        label: 'TERMINAL',
                        isActive: active == BottomTab.terminal,
                        onTap: () => ref
                            .read(bottomActiveTabProvider.notifier)
                            .state = BottomTab.terminal,
                        colors: c,
                      ),
                    ],
                  ),
                ),
              ),
              // Close the whole bottom panel
              IconButton(
                icon: Icon(Codicons.close, size: 14, color: c.fgMuted),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  ref.read(terminalOpenProvider.notifier).state = false;
                  ref.read(problemsOpenProvider.notifier).state = false;
                },
              ),
            ],
          ),
        ),
        // Keep the terminal alive across tab switches (so the PTY session and
        // running processes persist); just hide it when another tab is active.
        Expanded(
          child: IndexedStack(
            index: active.index,
            children: const [
              ProblemsPanel(),
              _OutputView(),
              TerminalPanel(),
            ],
          ),
        ),
      ],
    );
  }
}

/// OUTPUT tab — shows the most recent command output (run / format / lint).
final outputLogProvider = StateProvider<String>((ref) => '');

class _OutputView extends ConsumerWidget {
  const _OutputView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final log = ref.watch(outputLogProvider);
    return Container(
      color: const Color(0xFF1E1E1E),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: SelectableText(
          log.isEmpty ? 'No output yet.' : log,
          style: TextStyle(
            color: log.isEmpty ? c.fgMuted : c.fg,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// VS Code-style bottom tab: text only, blue underline when active.
class _BottomTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VsCodeColors colors;

  const _BottomTab({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? c.accent : Colors.transparent,
              width: 1.5,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? c.fg : c.fgMuted,
            fontSize: 11,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Phone layout: one full-width panel at a time, chosen by the activity bar.
class _NarrowLayout extends StatelessWidget {
  final ActivityTab activeTab;
  final bool previewOpen;
  const _NarrowLayout({required this.activeTab, required this.previewOpen});

  @override
  Widget build(BuildContext context) {
    // When preview is open and editor tab is active, show PreviewPanel instead.
    if (previewOpen && activeTab == ActivityTab.editor) {
      return const PreviewPanel();
    }
    return switch (activeTab) {
      ActivityTab.editor => const EditorPanel(),
      ActivityTab.explorer => const ExplorerPanel(),
      ActivityTab.search => const SearchPanel(),
      ActivityTab.git => const ScmPanel(),
      ActivityTab.ai => const AiPanel(),
      ActivityTab.extensions => const ExtensionsPanel(),
      ActivityTab.settings => const SettingsScreen(),
    };
  }
}

/// Tablet/landscape layout: side panel + editor side by side, with a
/// draggable divider so the side panel can be resized (VS Code style).
class _WideLayout extends StatefulWidget {
  final ActivityTab activeTab;
  final bool previewOpen;
  const _WideLayout({required this.activeTab, required this.previewOpen});

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout> {
  double _panelWidth = 260;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    final sidePanel = switch (widget.activeTab) {
      ActivityTab.editor => const ExplorerPanel(),
      ActivityTab.explorer => const ExplorerPanel(),
      ActivityTab.search => const SearchPanel(),
      ActivityTab.git => const ScmPanel(),
      ActivityTab.ai => const AiPanel(),
      ActivityTab.extensions => const ExtensionsPanel(),
      ActivityTab.settings => const SettingsScreen(),
    };

    return LayoutBuilder(builder: (context, box) {
      // Keep the panel within sane bounds relative to the available width.
      final maxPanel = (box.maxWidth - 200).clamp(180.0, 600.0).toDouble();
      final width = _panelWidth.clamp(160.0, maxPanel).toDouble();

      // The main editor area: split vertically when preview is open.
      final editorArea = widget.previewOpen
          ? const Column(
              children: [
                Expanded(child: EditorPanel()),
                Divider(height: 1, color: Color(0xFF3E3E42)),
                Expanded(child: PreviewPanel()),
              ],
            )
          : const EditorPanel();

      return Row(
        children: [
          SizedBox(width: width, child: sidePanel),
          // Draggable splitter — a thin divider with a wider invisible hit area.
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) {
                setState(() {
                  _panelWidth =
                      (width + d.delta.dx).clamp(160.0, maxPanel).toDouble();
                });
              },
              child: Container(
                width: 8,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Container(width: 1, color: c.border),
              ),
            ),
          ),
          Expanded(child: editorArea),
        ],
      );
    });
  }
}

class _ActivityBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final active = ref.watch(activeTabProvider);
    final terminalOpen = ref.watch(terminalOpenProvider);

    Widget iconBtn(
        IconData icon, ActivityTab tab, String tooltip) {
      final isActive = active == tab;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () =>
              ref.read(activeTabProvider.notifier).state = tab,
          child: Container(
            width: 48,
            height: 48,
            color: isActive
                ? c.bg
                : Colors.transparent,
            child: Icon(icon,
                color: isActive ? c.fg : c.fgMuted, size: 20),
          ),
        ),
      );
    }

    final problemsOpen = ref.watch(problemsOpenProvider);

    return Container(
      width: 48,
      color: const Color(0xFF333333),
      child: Column(
        children: [
          const SizedBox(height: 4),
          iconBtn(Codicons.file, ActivityTab.editor, 'Editor'),
          iconBtn(Codicons.files, ActivityTab.explorer, 'Explorer'),
          iconBtn(Codicons.search, ActivityTab.search, 'Search'),
          iconBtn(Codicons.sourceControl, ActivityTab.git,
              'Source Control'),
          iconBtn(Codicons.robot, ActivityTab.ai, 'AI Assistant'),
          iconBtn(Codicons.library, ActivityTab.extensions, 'Extensions'),
          const Spacer(),
          Tooltip(
            message: 'Toggle Problems',
            child: InkWell(
              onTap: () => ref
                  .read(problemsOpenProvider.notifier)
                  .state = !problemsOpen,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(Codicons.warning,
                    color: problemsOpen ? c.fg : c.fgMuted,
                    size: 20),
              ),
            ),
          ),
          Tooltip(
            message: 'Toggle Terminal',
            child: InkWell(
              onTap: () => ref
                  .read(terminalOpenProvider.notifier)
                  .state = !terminalOpen,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(Codicons.terminal,
                    color: terminalOpen ? c.fg : c.fgMuted,
                    size: 20),
              ),
            ),
          ),
          Tooltip(
            message: 'Command Palette (Ctrl+Shift+P)',
            child: InkWell(
              onTap: () => showCommandPalette(context, ref),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(Codicons.sparkle,
                    color: c.fgMuted, size: 20),
              ),
            ),
          ),
          iconBtn(Codicons.settingsGear, ActivityTab.settings,
              'Settings'),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
