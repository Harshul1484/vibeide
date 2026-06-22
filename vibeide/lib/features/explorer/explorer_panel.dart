import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'explorer_provider.dart';
import '../editor/editor_provider.dart';
import '../shell/shell_layout.dart';

class ExplorerPanel extends ConsumerWidget {
  const ExplorerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final tree = ref.watch(fileTreeProvider);

    return Container(
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'EXPLORER',
                style: TextStyle(
                  color: c.fgMuted,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: c.border),
          // Tree
          Expanded(
            child: tree.when(
              loading: () => Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: c.accent),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No project open',
                  style: TextStyle(color: c.fgMuted, fontSize: 12),
                ),
              ),
              data: (node) => ListView(
                children: node.children
                    .map((n) => _FileNodeTile(node: n, depth: 0))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileNodeTile extends ConsumerStatefulWidget {
  final FileNode node;
  final int depth;

  const _FileNodeTile({required this.node, required this.depth});

  @override
  ConsumerState<_FileNodeTile> createState() => _FileNodeTileState();
}

class _FileNodeTileState extends ConsumerState<_FileNodeTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final selected = ref.watch(selectedFileProvider) == widget.node.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () {
            if (widget.node.isDir) {
              setState(() => _expanded = !_expanded);
            } else {
              ref.read(selectedFileProvider.notifier).state =
                  widget.node.path;
              ref.read(openTabsProvider.notifier).openFile(widget.node.path);
              // Switch to the editor so the opened file is shown immediately
              // (on phones the explorer and editor are separate full-screen
              // panels, so we must flip the active tab).
              ref.read(activeTabProvider.notifier).state =
                  ActivityTab.editor;
            }
          },
          onLongPress: () => _showContextMenu(context),
          child: Container(
            color: selected
                ? c.accent.withAlpha(60)
                : Colors.transparent,
            padding: EdgeInsets.only(
              left: 8.0 + widget.depth * 12,
              top: 3,
              bottom: 3,
            ),
            child: Row(
              children: [
                Icon(
                  widget.node.isDir
                      ? (_expanded
                          ? Codicons.folderOpened
                          : Codicons.folder)
                      : Codicons.forFile(widget.node.name),
                  size: 16,
                  color: widget.node.isDir
                      ? const Color(0xFFDCB67A)
                      : c.fgMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.node.name,
                    style: TextStyle(color: c.fg, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded && widget.node.isDir)
          ...widget.node.children.map(
            (n) => _FileNodeTile(node: n, depth: widget.depth + 1),
          ),
      ],
    );
  }

  void _showContextMenu(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.sidebar,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.node.isDir)
              ListTile(
                leading: Icon(Codicons.trash, color: c.fgMuted),
                title: Text('Delete', style: TextStyle(color: c.fg)),
                onTap: () async {
                  Navigator.pop(context);
                  await ref
                      .read(sandboxClientProvider)
                      .deleteFile(widget.node.path);
                  ref.invalidate(fileTreeProvider);
                },
              ),
          ],
        ),
      ),
    );
  }
}
