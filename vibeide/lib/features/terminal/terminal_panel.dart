import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/projects/project_provider.dart';

/// When non-null, the terminal will execute this command string and reset to null.
final pendingTerminalCommandProvider = StateProvider<String?>((ref) => null);

class TerminalPanel extends ConsumerStatefulWidget {
  const TerminalPanel({super.key});

  @override
  ConsumerState<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends ConsumerState<TerminalPanel> {
  InAppWebViewController? _webCtrl;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    // Watch for a pending run command injected by the Run button.
    ref.listen<String?>(pendingTerminalCommandProvider, (_, next) {
      if (next != null && _webCtrl != null) {
        // Escape backslashes then double-quotes for safe JS string injection.
        final escaped = next
            .replaceAll(r'\', r'\\')
            .replaceAll('"', r'\"');
        _webCtrl!.evaluateJavascript(
          source: 'if (window.runCmd) window.runCmd("$escaped");',
        );
        ref.read(pendingTerminalCommandProvider.notifier).state = null;
      }
    });

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Terminal tab bar
          Container(
            height: 30,
            color: const Color(0xFF2D2D2D),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Codicons.terminal, size: 14, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  'TERMINAL',
                  style: TextStyle(
                    color: c.fg,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Codicons.refresh, size: 14, color: c.fgMuted),
                  tooltip: 'Reconnect',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 24, minHeight: 24),
                  onPressed: () {
                    _webCtrl?.reload();
                  },
                ),
              ],
            ),
          ),
          // xterm.js WebView
          Expanded(
            child: InAppWebView(
              initialFile: 'assets/terminal/index.html',
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                useWideViewPort: false,
                loadWithOverviewMode: false,
                supportZoom: false,
                builtInZoomControls: false,
                displayZoomControls: false,
                // Allow the file:// page to open ws://127.0.0.1 (cleartext).
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                // Don't serve a stale cached terminal page across app updates.
                clearCache: true,
                cacheMode: CacheMode.LOAD_NO_CACHE,
              ),
              onWebViewCreated: (ctrl) => _webCtrl = ctrl,
              onLoadStop: (ctrl, url) async {
                // cd into the open project's dir + set a readable prompt.
                final project = ref.read(activeProjectProvider);
                final dir = project?.localPath ?? '/root';
                final name = project?.name ?? 'project';
                await ctrl.evaluateJavascript(source: '''
                  if (window.flutterFit) window.flutterFit();
                  if (window.runCd) window.runCd("$dir", "$name");
                ''');
              },
            ),
          ),
        ],
      ),
    );
  }
}
