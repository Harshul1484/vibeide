import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/shell/shell_layout.dart';

// ── Command model ─────────────────────────────────────────────────────────────

class Command {
  final String id;
  final String label;
  final String? hint; // keybinding hint shown on the right
  final IconData icon;
  final void Function(WidgetRef ref, BuildContext context) run;

  const Command({
    required this.id,
    required this.label,
    this.hint,
    required this.icon,
    required this.run,
  });
}

// ── Command list ──────────────────────────────────────────────────────────────

List<Command> _buildCommands() => [
      Command(
        id: 'go-to-explorer',
        label: 'Go to File / Open File…',
        icon: Codicons.files,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.explorer,
      ),
      Command(
        id: 'search-in-files',
        label: 'Search in Files',
        icon: Codicons.search,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.search,
      ),
      Command(
        id: 'source-control',
        label: 'Source Control',
        icon: Codicons.sourceControl,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.git,
      ),
      Command(
        id: 'toggle-terminal',
        label: 'Toggle Terminal',
        hint: 'Ctrl+`',
        icon: Codicons.terminal,
        run: (ref, _) {
          final cur = ref.read(terminalOpenProvider);
          ref.read(terminalOpenProvider.notifier).state = !cur;
        },
      ),
      Command(
        id: 'ai-assistant',
        label: 'AI Assistant',
        icon: Codicons.sparkle,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.ai,
      ),
      Command(
        id: 'extensions',
        label: 'Extensions',
        icon: Codicons.library,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state =
                ActivityTab.extensions,
      ),
      Command(
        id: 'open-settings',
        label: 'Open Settings',
        icon: Codicons.settingsGear,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.settings,
      ),
      Command(
        id: 'format-document',
        label: 'Format Document',
        icon: Codicons.fileCode,
        run: (ref, context) {
          ref.read(activeTabProvider.notifier).state = ActivityTab.editor;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Use long-press → Format in the editor'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
      Command(
        id: 'git-pull',
        label: 'Git: Pull',
        icon: Codicons.cloudDownload,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.git,
      ),
      Command(
        id: 'git-commit',
        label: 'Git: Commit',
        icon: Codicons.gitCommit,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.git,
      ),
      Command(
        id: 'git-create-pr',
        label: 'Git: Create Pull Request',
        icon: Codicons.gitPullRequest,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.git,
      ),
      Command(
        id: 'run-active-file',
        label: 'Run Active File',
        icon: Codicons.play,
        run: (ref, _) =>
            ref.read(activeTabProvider.notifier).state = ActivityTab.editor,
      ),
    ];

// ── Public API ────────────────────────────────────────────────────────────────

Future<void> showCommandPalette(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _CommandPaletteDialog(ref: ref),
  );
}

// ── Dialog widget ─────────────────────────────────────────────────────────────

class _CommandPaletteDialog extends StatefulWidget {
  final WidgetRef ref;
  const _CommandPaletteDialog({required this.ref});

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _allCommands = _buildCommands();
  List<Command> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = _allCommands;
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final q = _controller.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allCommands
          : _allCommands
              .where((c) => c.label.toLowerCase().contains(q))
              .toList();
    });
  }

  void _run(Command cmd) {
    Navigator.of(context).pop();
    cmd.run(widget.ref, context);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final screenWidth = MediaQuery.of(context).size.width;
    final paletteWidth = screenWidth < 640 ? screenWidth - 32 : 600.0;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 48,
          left: 16,
          right: 16,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: paletteWidth,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF252526),
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search field
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: c.border, width: 1)),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: TextStyle(color: c.fg, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '> Type a command…',
                      hintStyle:
                          TextStyle(color: c.fgMuted, fontSize: 13),
                      prefixIcon: Icon(Codicons.search,
                          size: 14, color: c.fgMuted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                // Command list
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final cmd = _filtered[i];
                      return _CommandItem(
                        command: cmd,
                        colors: c,
                        onTap: () => _run(cmd),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Command list item ─────────────────────────────────────────────────────────

class _CommandItem extends StatelessWidget {
  final Command command;
  final VsCodeColors colors;
  final VoidCallback onTap;

  const _CommandItem({
    required this.command,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(command.icon, size: 14, color: c.fgMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                command.label,
                style: TextStyle(color: c.fg, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (command.hint != null)
              Text(
                command.hint!,
                style: TextStyle(
                    color: c.fgMuted, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
