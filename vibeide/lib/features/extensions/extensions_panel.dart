import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'extension_catalog.dart';
import 'extensions_provider.dart';

class ExtensionsPanel extends ConsumerStatefulWidget {
  const ExtensionsPanel({super.key});

  @override
  ConsumerState<ExtensionsPanel> createState() => _ExtensionsPanelState();
}

class _ExtensionsPanelState extends ConsumerState<ExtensionsPanel> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _installedOpen = true;
  bool _availableOpen = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DevTool> get _filtered {
    if (_query.isEmpty) return devToolCatalog;
    return devToolCatalog
        .where((t) =>
            t.name.toLowerCase().contains(_query) ||
            t.description.toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final sandboxReady = ref.watch(sandboxProvider) == SandboxState.ready;
    final installedIds =
        ref.watch(installedToolsProvider).valueOrNull ?? const <String>{};

    final installed =
        _filtered.where((t) => installedIds.contains(t.id)).toList();
    final available =
        _filtered.where((t) => !installedIds.contains(t.id)).toList();

    return Container(
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Container(
            height: 35,
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'EXTENSIONS',
                    style: TextStyle(
                      color: c.fgMuted,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Codicons.refresh, size: 15, color: c.fgMuted),
                  tooltip: 'Refresh',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => ref.invalidate(installedToolsProvider),
                ),
              ],
            ),
          ),
          // ── Search box (VS Code "Search Extensions in Marketplace") ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: c.fg, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search Extensions in Marketplace',
                  hintStyle: TextStyle(color: c.fgMuted, fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 7),
                  filled: true,
                  fillColor: c.bg,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: c.border),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.border),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: c.accent),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          if (!sandboxReady)
            Container(
              width: double.infinity,
              color: const Color(0xFF3A2D00),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Open a project to install extensions into the sandbox.',
                style: TextStyle(color: c.fgMuted, fontSize: 11),
              ),
            ),
          // ── Lists ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _SectionHeader(
                  label: 'INSTALLED',
                  count: installed.length,
                  open: _installedOpen,
                  onTap: () =>
                      setState(() => _installedOpen = !_installedOpen),
                ),
                if (_installedOpen)
                  ...installed.map((t) => _ExtensionTile(tool: t, installed: true)),
                _SectionHeader(
                  label: 'AVAILABLE',
                  count: available.length,
                  open: _availableOpen,
                  onTap: () =>
                      setState(() => _availableOpen = !_availableOpen),
                ),
                if (_availableOpen)
                  ...available.map((t) => _ExtensionTile(tool: t, installed: false)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible section header with a count badge — VS Code's
/// "INSTALLED 21" / "RECOMMENDED 8" style.
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool open;
  final VoidCallback onTap;
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(open ? Codicons.chevronDown : Codicons.chevronRight,
                size: 14, color: c.fgMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: c.fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            // Count badge (rounded pill)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(color: c.fg, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A VS Code marketplace-style extension row: square icon, name + meta on
/// top, 2-line description, publisher with a verified check, and an action.
class _ExtensionTile extends ConsumerStatefulWidget {
  final DevTool tool;
  final bool installed;
  const _ExtensionTile({required this.tool, required this.installed});

  @override
  ConsumerState<_ExtensionTile> createState() => _ExtensionTileState();
}

class _ExtensionTileState extends ConsumerState<_ExtensionTile> {
  bool _busy = false;
  String? _status;

  // Per-category accent for the square icon, mimicking distinct extension art.
  Color _iconColor(String category) {
    switch (category) {
      case 'Runtimes':
        return const Color(0xFF3FB950); // green
      case 'Formatters & Linters':
        return const Color(0xFFD29922); // amber
      default:
        return const Color(0xFF388BFD); // blue
    }
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'Runtimes':
        return Codicons.terminal;
      case 'Formatters & Linters':
        return Codicons.sparkle;
      default:
        return Codicons.library;
    }
  }

  Future<void> _run(Future<void> Function() op, String okMsg) async {
    setState(() {
      _busy = true;
      _status = 'Starting…';
    });
    try {
      await op();
      if (mounted) {
        ref.invalidate(installedToolsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(okMsg),
            backgroundColor: const Color(0xFF1F6F2E),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: const Color(0xFF7A1F1F),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() { _busy = false; _status = null; });
    }
  }

  void _install() {
    final svc = ref.read(extensionsServiceProvider);
    _run(
      () => svc.install(widget.tool, onLine: (l) {
        if (mounted && l.trim().isNotEmpty) {
          setState(() => _status = l.trim());
        }
      }),
      '${widget.tool.name} installed',
    );
  }

  void _uninstall() {
    final svc = ref.read(extensionsServiceProvider);
    _run(
      () => svc.uninstall(widget.tool, onLine: (l) {
        if (mounted && l.trim().isNotEmpty) {
          setState(() => _status = l.trim());
        }
      }),
      '${widget.tool.name} uninstalled',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final t = widget.tool;
    final sandboxReady = ref.watch(sandboxProvider) == SandboxState.ready;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Square icon (rounded corners). Real logo when available, with a
          // colored category glyph as the offline / load-failure fallback.
          Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _iconColor(t.category).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: t.iconUrl != null
                ? SvgPicture.network(
                    t.iconUrl!,
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => Icon(_iconFor(t.category),
                        size: 22, color: _iconColor(t.category)),
                  )
                : Icon(_iconFor(t.category),
                    size: 22, color: _iconColor(t.category)),
          ),
          const SizedBox(width: 10),
          // Right column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + (installed check or busy spinner)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.name,
                        style: TextStyle(
                          color: c.fg,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_busy)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: c.accent),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                // Description (2 lines like VS Code) OR live status while busy
                Text(
                  _busy && _status != null ? _status! : t.description,
                  style: TextStyle(
                    color: _busy ? c.accent : c.fgMuted,
                    fontSize: 11,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Publisher row + action
                Row(
                  children: [
                    Icon(Codicons.check, size: 11, color: c.accent),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        _publisher(t.via),
                        style: TextStyle(color: c.fgMuted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (sandboxReady && !_busy) _actionButton(c),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _publisher(InstallVia via) => switch (via) {
        InstallVia.apk => 'Alpine',
        InstallVia.npm => 'npm',
        InstallVia.pip => 'PyPI',
      };

  Widget _actionButton(VsCodeColors c) {
    if (widget.installed) {
      // "Uninstall" pill (gear-like secondary action)
      return _pill(
        label: 'Uninstall',
        filled: false,
        c: c,
        onTap: _uninstall,
      );
    }
    return _pill(
      label: 'Install',
      filled: true,
      c: c,
      onTap: _install,
    );
  }

  Widget _pill({
    required String label,
    required bool filled,
    required VsCodeColors c,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: filled ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: filled ? null : Border.all(color: c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? Colors.white : c.fg,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
