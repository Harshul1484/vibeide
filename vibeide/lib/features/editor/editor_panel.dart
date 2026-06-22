import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/projects/project.dart';
import 'package:vibeide/features/shell/shell_layout.dart';
import 'package:vibeide/features/extensions/extension_catalog.dart';
import 'package:vibeide/features/extensions/extensions_provider.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/terminal/terminal_panel.dart';
import 'package:vibeide/features/problems/problems_provider.dart';
import 'package:vibeide/features/preview/preview_provider.dart';
import 'package:vibeide/features/git/git_provider.dart';
import 'package:vibeide/features/git/conflict_resolver.dart';
import 'editor_provider.dart';

class EditorPanel extends ConsumerWidget {
  const EditorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final tabs = ref.watch(openTabsProvider);
    final activePath = ref.watch(activeTabPathProvider);

    if (tabs.isEmpty) {
      final welcomeClosed = ref.watch(welcomeClosedProvider);
      if (welcomeClosed) {
        return Container(color: c.bg);
      }
      return const _WelcomeTab();
    }

    final activeTab = tabs.firstWhere(
      (t) => t.path == activePath,
      orElse: () => tabs.first,
    );

    // Determine if there's an installed formatter/runtime/linter for the active file.
    final sandboxReady = ref.watch(sandboxProvider) == SandboxState.ready;
    final installedTools =
        sandboxReady ? ref.watch(installedToolsProvider).valueOrNull : null;

    DevTool? activeFormatter;
    DevTool? activeRuntime;
    DevTool? activeLinter;
    if (sandboxReady && installedTools != null) {
      activeFormatter = formatterFor(activeTab.path, installedTools);
      activeRuntime = runtimeFor(activeTab.path, installedTools);
      activeLinter = linterFor(activeTab.path, installedTools);
    }

    // Conflict state for the active file.
    final project = ref.watch(activeProjectProvider);
    final conflictedFiles =
        ref.watch(conflictedFilesProvider).valueOrNull ?? [];
    final isMerging =
        ref.watch(mergeInProgressProvider).valueOrNull ?? false;

    // Compute whether the active file has conflicts.
    // conflictedFiles contains paths relative to the project root.
    bool activeFileHasConflicts = false;
    String? activeRelPath;
    if (project != null && conflictedFiles.isNotEmpty) {
      final localPath = project.localPath;
      final absPath = activeTab.path;
      if (absPath.startsWith(localPath)) {
        activeRelPath = absPath.substring(localPath.length);
        // Strip leading slash(es).
        while (activeRelPath!.startsWith('/')) {
          activeRelPath = activeRelPath.substring(1);
        }
        activeFileHasConflicts =
            conflictedFiles.contains(activeRelPath);
      }
    }

    final conflictCount = activeFileHasConflicts
        ? countConflicts(activeTab.content)
        : 0;

    return Container(
      color: c.bg,
      child: Column(
        children: [
          // Tab bar
          Container(
            height: 35,
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: tabs
                        .map((t) => _Tab(
                              tab: t,
                              isActive: t.path == activeTab.path,
                            ))
                        .toList(),
                  ),
                ),
                if (activeLinter != null)
                  _LintButton(activePath: activeTab.path),
                if (activeRuntime != null)
                  _RunButton(
                    activePath: activeTab.path,
                    runtime: activeRuntime,
                  ),
                if (activeFormatter != null)
                  _FormatButton(
                    activePath: activeTab.path,
                    formatter: activeFormatter,
                  ),
              ],
            ),
          ),
          // Breadcrumb
          Container(
            height: 22,
            color: const Color(0xFF1E1E1E),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                activeTab.path,
                style: TextStyle(color: c.fgMuted, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Conflict resolution banner
          if (activeFileHasConflicts && project != null)
            _ConflictBanner(
              conflictCount: conflictCount,
              activeTab: activeTab,
              relPath: activeRelPath ?? '',
              project: project,
              isMerging: isMerging,
              totalConflictedFiles: conflictedFiles.length,
            ),
          // Editor — long-press anywhere opens a VS Code-style context menu.
          Expanded(
            child: _EditorContextMenu(
              activePath: activeTab.path,
              formatter: activeFormatter,
              runtime: activeRuntime,
              linter: activeLinter,
              child: _Editor(tab: activeTab),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends ConsumerWidget {
  final OpenTab tab;
  final bool isActive;

  const _Tab({required this.tab, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final name = tab.path.split('/').last;

    return GestureDetector(
      onTap: () =>
          ref.read(activeTabPathProvider.notifier).state = tab.path,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF1E1E1E)
              : const Color(0xFF2D2D2D),
          border: isActive
              ? const Border(
                  top: BorderSide(color: Color(0xFF0078D4), width: 1))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                color: isActive ? c.fg : c.fgMuted,
                fontSize: 13,
              ),
            ),
            if (tab.isDirty) ...[
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () =>
                  ref.read(openTabsProvider.notifier).closeTab(tab.path),
              child: Icon(Codicons.close, size: 14, color: c.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  final OpenTab tab;

  const _Editor({required this.tab});

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late CodeLineEditingController _controller;
  String? _lastPath;

  @override
  void initState() {
    super.initState();
    _controller =
        CodeLineEditingController.fromText(widget.tab.content);
    _lastPath = widget.tab.path;
  }

  @override
  void didUpdateWidget(_Editor old) {
    super.didUpdateWidget(old);
    if (widget.tab.path != _lastPath) {
      _controller.dispose();
      _controller =
          CodeLineEditingController.fromText(widget.tab.content);
      _lastPath = widget.tab.path;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = _langFromPath(widget.tab.path);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS,
            control: true): () {
          ref
              .read(openTabsProvider.notifier)
              .saveAndMaybeFormat(widget.tab.path);
        },
      },
      child: CodeEditor(
        controller: _controller,
        // Line-number gutter, VS Code style.
        indicatorBuilder: (context, editingController, chunkController,
            notifier) {
          return Row(
            children: [
              DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                textStyle: const TextStyle(
                  color: Color(0xFF6E7681),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              DefaultCodeChunkIndicator(
                  width: 14, controller: chunkController, notifier: notifier),
            ],
          );
        },
        style: CodeEditorStyle(
          fontSize: 14,
          fontFamily: 'monospace',
          textColor: const Color(0xFFD4D4D4),
          backgroundColor: const Color(0xFF1E1E1E),
          codeTheme: CodeHighlightTheme(
            languages: {
              lang: CodeHighlightThemeMode(
                mode: builtinAllLanguages[lang] ??
                    builtinAllLanguages['plaintext']!,
              ),
            },
            theme: atomOneDarkTheme,
          ),
        ),
        onChanged: (value) {
          ref.read(openTabsProvider.notifier).updateContent(
                widget.tab.path,
                _controller.text,
              );
        },
      ),
    );
  }

  String _langFromPath(String path) {
    if (path.endsWith('.dart')) return 'dart';
    if (path.endsWith('.js')) return 'javascript';
    if (path.endsWith('.ts')) return 'typescript';
    if (path.endsWith('.py')) return 'python';
    if (path.endsWith('.go')) return 'go';
    if (path.endsWith('.kt')) return 'kotlin';
    if (path.endsWith('.md')) return 'markdown';
    if (path.endsWith('.json')) return 'json';
    if (path.endsWith('.yaml') || path.endsWith('.yml')) return 'yaml';
    if (path.endsWith('.sh')) return 'bash';
    if (path.endsWith('.html')) return 'xml';
    return 'plaintext';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ─── Conflict resolution banner ───────────────────────────────────────────────

class _ConflictBanner extends ConsumerWidget {
  final int conflictCount;
  final OpenTab activeTab;
  final String relPath;
  final Project project;
  final bool isMerging;
  final int totalConflictedFiles;

  const _ConflictBanner({
    required this.conflictCount,
    required this.activeTab,
    required this.relPath,
    required this.project,
    required this.isMerging,
    required this.totalConflictedFiles,
  });

  Future<void> _resolve(
      WidgetRef ref, BuildContext context, ConflictChoice choice) async {
    final resolved = resolveConflicts(activeTab.content, choice);
    final notifier = ref.read(openTabsProvider.notifier);
    final client = ref.read(sandboxClientProvider);
    final messenger = ScaffoldMessenger.of(context);

    // Update editor content and save.
    notifier.updateContent(activeTab.path, resolved);
    await notifier.saveFile(activeTab.path);

    // Mark the file as resolved in git.
    await client.gitAdd(project.localPath, [relPath]);

    // Invalidate providers so the banner updates.
    ref.invalidate(conflictedFilesProvider);
    ref.invalidate(gitStatusProvider);

    // Reload the tab so the editor shows the resolved content.
    await notifier.reloadFile(activeTab.path);

    // Check if all conflicts are resolved.
    final remaining =
        await ref.read(conflictedFilesProvider.future);
    final stillMerging =
        await ref.read(mergeInProgressProvider.future);

    if (remaining.isEmpty && stillMerging) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'All conflicts resolved — Complete merge in Source Control'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: const Color(0xFF2D1E00),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 14, color: Color(0xFFE2C08D)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$conflictCount merge conflict${conflictCount == 1 ? '' : 's'}',
              style: const TextStyle(
                  color: Color(0xFFE2C08D), fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _ConflictActionButton(
            label: 'Accept Current',
            onTap: () => _resolve(ref, context, ConflictChoice.current),
          ),
          const SizedBox(width: 6),
          _ConflictActionButton(
            label: 'Accept Incoming',
            onTap: () => _resolve(ref, context, ConflictChoice.incoming),
          ),
          const SizedBox(width: 6),
          _ConflictActionButton(
            label: 'Accept Both',
            onTap: () => _resolve(ref, context, ConflictChoice.both),
          ),
        ],
      ),
    );
  }
}

class _ConflictActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ConflictActionButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF555555)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: Color(0xFFD4D4D4), fontSize: 10),
        ),
      ),
    );
  }
}

// ─── Format button ───────────────────────────────────────────────────────────

class _FormatButton extends ConsumerStatefulWidget {
  final String activePath;
  final DevTool formatter;

  const _FormatButton({
    required this.activePath,
    required this.formatter,
  });

  @override
  ConsumerState<_FormatButton> createState() => _FormatButtonState();
}

class _FormatButtonState extends ConsumerState<_FormatButton> {
  bool _formatting = false;

  Future<void> _format() async {
    if (_formatting) return;
    setState(() => _formatting = true);

    try {
      final notifier = ref.read(openTabsProvider.notifier);
      final client = ref.read(sandboxClientProvider);

      // 1. Save current content to disk
      await notifier.saveFile(widget.activePath);

      // 2. Run the formatter in the sandbox
      final cmd = widget.formatter.formatCmd!
          .replaceAll('{file}', widget.activePath);
      final (exitCode, output) = await client.execToCompletion(
        '/bin/sh',
        ['-lc', cmd],
      );

      if (exitCode != 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Format failed: ${output.trim().split('\n').last}'),
              backgroundColor: Colors.red.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // 3. Reload the formatted file into the editor tab
      await notifier.reloadFile(widget.activePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Formatted with ${widget.formatter.name}'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Format error: $e'),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _formatting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Tooltip(
      message: 'Format Document (${widget.formatter.name})',
      child: InkWell(
        onTap: _formatting ? null : _format,
        child: SizedBox(
          width: 36,
          height: 35,
          child: _formatting
              ? Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: c.accent,
                    ),
                  ),
                )
              : Icon(Codicons.sparkle, size: 14, color: c.accent),
        ),
      ),
    );
  }
}

// ─── Run button ──────────────────────────────────────────────────────────────

class _RunButton extends ConsumerStatefulWidget {
  final String activePath;
  final DevTool runtime;

  const _RunButton({required this.activePath, required this.runtime});

  @override
  ConsumerState<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends ConsumerState<_RunButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      // 1. Save the file first.
      await ref
          .read(openTabsProvider.notifier)
          .saveFile(widget.activePath);
      // 2. Open the terminal.
      ref.read(terminalOpenProvider.notifier).state = true;
      // 3. Inject the run command into the terminal PTY.
      final cmd = widget.runtime.runCmd!
          .replaceAll('{file}', widget.activePath);
      ref.read(pendingTerminalCommandProvider.notifier).state = cmd;
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Run File (${widget.runtime.name})',
      child: InkWell(
        onTap: _running ? null : _run,
        child: SizedBox(
          width: 36,
          height: 35,
          child: _running
              ? Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.green.shade400,
                    ),
                  ),
                )
              : Icon(Codicons.play,
                  size: 16, color: Colors.green.shade400),
        ),
      ),
    );
  }
}

// ─── Lint button ─────────────────────────────────────────────────────────────

class _LintButton extends ConsumerWidget {
  final String activePath;

  const _LintButton({required this.activePath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Tooltip(
      message: 'Run Lint / Show Problems',
      child: InkWell(
        onTap: () async {
          await ref
              .read(problemsNotifierProvider.notifier)
              .runLint(activePath);
          ref.read(problemsOpenProvider.notifier).state = true;
        },
        child: SizedBox(
          width: 36,
          height: 35,
          child: Icon(Codicons.warning, size: 14, color: c.fgMuted),
        ),
      ),
    );
  }
}

// ─── Go Live button ──────────────────────────────────────────────────────────

/// Wraps the editor body and shows a VS Code-style context menu on long-press,
/// with Live Server, Format/Run, and Cut/Copy/Paste actions.
class _EditorContextMenu extends ConsumerWidget {
  final String activePath;
  final DevTool? formatter;
  final DevTool? runtime;
  final DevTool? linter;
  final Widget child;

  const _EditorContextMenu({
    required this.activePath,
    required this.formatter,
    required this.runtime,
    required this.linter,
    required this.child,
  });

  bool get _isHtml =>
      activePath.toLowerCase().endsWith('.html') ||
      activePath.toLowerCase().endsWith('.htm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onLongPressStart: (details) =>
          _showMenu(context, ref, details.globalPosition),
      child: child,
    );
  }

  Future<void> _showMenu(
      BuildContext context, WidgetRef ref, Offset pos) async {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final previewRunning = ref.read(livePreviewProvider).running;

    PopupMenuItem<String> item(String value, String label,
        {String? shortcut, bool enabled = true}) {
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        height: 38,
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: enabled ? c.fg : c.fgMuted, fontSize: 13)),
            ),
            if (shortcut != null)
              Text(shortcut,
                  style: TextStyle(color: c.fgMuted, fontSize: 11)),
          ],
        ),
      );
    }

    final selected = await showMenu<String>(
      context: context,
      color: c.sidebar,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(pos.dx, pos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (formatter != null)
          item('format', 'Format Document', shortcut: '⇧⌥F'),
        if (runtime != null) item('run', 'Run File'),
        if (linter != null) item('lint', 'Lint File'),
        if (formatter != null || runtime != null || linter != null)
          const PopupMenuDivider(),
        item('cut', 'Cut', shortcut: 'Ctrl+X'),
        item('copy', 'Copy', shortcut: 'Ctrl+C'),
        item('paste', 'Paste', shortcut: 'Ctrl+V'),
        const PopupMenuDivider(),
        item('selectAll', 'Select All', shortcut: 'Ctrl+A'),
        const PopupMenuDivider(),
        if (_isHtml || previewRunning)
          item('live',
              previewRunning ? 'Open with Live Server' : 'Open with Live Server'),
        if (previewRunning) item('stopLive', 'Stop Live Server'),
      ],
    );

    if (selected == null || !context.mounted) return;
    await _handle(context, ref, selected);
  }

  Future<void> _handle(
      BuildContext context, WidgetRef ref, String action) async {
    final tabs = ref.read(openTabsProvider.notifier);
    final client = ref.read(sandboxClientProvider);
    // Capture the messenger up front so we never use context across an await.
    final messenger = ScaffoldMessenger.of(context);
    void toast(String m) => messenger.showSnackBar(
          SnackBar(content: Text(m), duration: const Duration(seconds: 2)),
        );

    switch (action) {
      case 'format':
        if (formatter != null) {
          await tabs.saveFile(activePath);
          await client.execToCompletion('/bin/sh',
              ['-lc', formatter!.formatCmd!.replaceAll('{file}', activePath)]);
          await tabs.reloadFile(activePath);
          toast('Formatted with ${formatter!.name}');
        }
        break;
      case 'run':
        if (runtime != null) {
          await tabs.saveFile(activePath);
          ref.read(terminalOpenProvider.notifier).state = true;
          ref.read(pendingTerminalCommandProvider.notifier).state =
              runtime!.runCmd!.replaceAll('{file}', activePath);
        }
        break;
      case 'lint':
        ref.read(problemsOpenProvider.notifier).state = true;
        ref.read(problemsNotifierProvider.notifier).runLint(activePath);
        break;
      case 'copy':
      case 'cut':
        await Clipboard.setData(ClipboardData(text: _activeContent(ref)));
        toast('Copied');
        break;
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null) {
          tabs.updateContent(activePath, _activeContent(ref) + data!.text!);
          toast('Pasted at end');
        }
        break;
      case 'selectAll':
        toast('Use the editor selection handles to select all');
        break;
      case 'live':
        await ref.read(livePreviewProvider.notifier).start();
        ref.read(previewOpenProvider.notifier).state = true;
        break;
      case 'stopLive':
        await ref.read(livePreviewProvider.notifier).stop();
        ref.read(previewOpenProvider.notifier).state = false;
        break;
    }
  }

  String _activeContent(WidgetRef ref) {
    final tabs = ref.read(openTabsProvider);
    return tabs
        .firstWhere((t) => t.path == activePath, orElse: () => tabs.first)
        .content;
  }
}

// ─── Welcome tab (shown when no file is open) ────────────────────────────────

/// VS Code-style Welcome page: a "Welcome" tab header, Start actions, and a
/// Recent projects list. Shown in the editor area whenever no tabs are open.
class _WelcomeTab extends ConsumerWidget {
  const _WelcomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final active = ref.watch(activeProjectProvider);
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];

    return Container(
      color: c.bg,
      child: Column(
        children: [
          // Faux tab bar with a single "Welcome" tab
          Container(
            height: 35,
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    border: Border(
                        top: BorderSide(color: Color(0xFF0078D4), width: 1)),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Codicons.symbolFile, size: 14, color: c.accent),
                      const SizedBox(width: 6),
                      Text('Welcome',
                          style: TextStyle(color: c.fg, fontSize: 13)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => ref
                            .read(welcomeClosedProvider.notifier)
                            .state = true,
                        child: Icon(Codicons.close,
                            size: 14, color: c.fgMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Codicons.symbolFile, size: 28, color: c.accent),
                      const SizedBox(width: 10),
                      Text('VibeIDE',
                          style: TextStyle(
                              color: c.fg,
                              fontSize: 26,
                              fontWeight: FontWeight.w300)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active != null
                        ? 'Editing ${active.name}'
                        : 'Mobile IDE for git, node & python',
                    style: TextStyle(color: c.fgMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 32),

                  // ── Start ──
                  Text('Start',
                      style: TextStyle(
                          color: c.fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: 12),
                  _StartAction(
                    icon: Codicons.files,
                    label: 'Open Explorer',
                    onTap: () => ref
                        .read(activeTabProvider.notifier)
                        .state = ActivityTab.explorer,
                  ),
                  _StartAction(
                    icon: Codicons.terminal,
                    label: 'Open Terminal',
                    onTap: () => ref
                        .read(terminalOpenProvider.notifier)
                        .state = true,
                  ),
                  _StartAction(
                    icon: Codicons.sourceControl,
                    label: 'Source Control',
                    onTap: () => ref
                        .read(activeTabProvider.notifier)
                        .state = ActivityTab.git,
                  ),
                  _StartAction(
                    icon: Codicons.robot,
                    label: 'Ask AI Assistant',
                    onTap: () => ref
                        .read(activeTabProvider.notifier)
                        .state = ActivityTab.ai,
                  ),

                  const SizedBox(height: 32),

                  // ── Recent ──
                  Text('Recent',
                      style: TextStyle(
                          color: c.fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: 12),
                  if (projects.isEmpty)
                    Text('No recent projects',
                        style: TextStyle(color: c.fgMuted, fontSize: 13))
                  else
                    ...projects.take(8).map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                      color: c.accent, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  p.remoteUrl,
                                  style: TextStyle(
                                      color: c.fgMuted, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _StartAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c.accent),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: c.accent, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
