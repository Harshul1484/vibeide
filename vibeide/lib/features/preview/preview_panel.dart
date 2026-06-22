import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'preview_provider.dart';

class PreviewPanel extends ConsumerStatefulWidget {
  const PreviewPanel({super.key});

  @override
  ConsumerState<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends ConsumerState<PreviewPanel> {
  InAppWebViewController? _webCtrl;
  bool _starting = false;

  Future<void> _startServer() async {
    setState(() => _starting = true);
    try {
      await ref.read(livePreviewProvider.notifier).start();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopServer() async {
    await ref.read(livePreviewProvider.notifier).stop();
    ref.read(previewOpenProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final preview = ref.watch(livePreviewProvider);
    final url = ref.watch(previewUrlProvider);

    return Container(
      color: c.bg,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            height: 35,
            color: const Color(0xFF2D2D2D),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.public, size: 14, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  'PREVIEW',
                  style: TextStyle(
                    color: c.fg,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
                if (preview.running) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      url,
                      style: TextStyle(color: c.fgMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ] else
                  const Spacer(),
                if (preview.running) ...[
                  // Reload
                  Tooltip(
                    message: 'Reload preview',
                    child: InkWell(
                      onTap: () => _webCtrl?.reload(),
                      child: SizedBox(
                        width: 28,
                        height: 35,
                        child: Icon(Codicons.refresh,
                            size: 14, color: c.fgMuted),
                      ),
                    ),
                  ),
                  // Open in external browser
                  Tooltip(
                    message: 'Open in browser',
                    child: InkWell(
                      onTap: () async {
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: SizedBox(
                        width: 28,
                        height: 35,
                        child:
                            Icon(Codicons.link, size: 14, color: c.fgMuted),
                      ),
                    ),
                  ),
                ],
                // Close / Stop
                Tooltip(
                  message: preview.running ? 'Stop server & close' : 'Close',
                  child: InkWell(
                    onTap: _stopServer,
                    child: SizedBox(
                      width: 28,
                      height: 35,
                      child:
                          Icon(Codicons.close, size: 14, color: c.fgMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────────
          Expanded(
            child: _buildBody(c, preview, url),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(VsCodeColors c, PreviewState preview, String url) {
    // Error state
    if (preview.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Codicons.error, size: 32, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(
                preview.error!,
                style: TextStyle(color: Colors.red.shade300, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _starting ? null : _startServer,
                icon: _starting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: c.accent,
                        ),
                      )
                    : const Icon(Icons.public, size: 14, color: Colors.white),
                label: Text(_starting ? 'Starting...' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Not running — show Start button
    if (!preview.running) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 48, color: c.fgMuted),
            const SizedBox(height: 16),
            Text(
              'Live Server',
              style: TextStyle(
                  color: c.fg, fontSize: 18, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 8),
            Text(
              'Serve the project on http://127.0.0.1:${preview.port}/',
              style: TextStyle(color: c.fgMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _starting ? null : _startServer,
              icon: _starting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow, size: 16),
              label: Text(_starting ? 'Starting…' : 'Go Live'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ),
      );
    }

    // Running — show WebView
    return InAppWebView(
      initialUrlRequest:
          URLRequest(url: WebUri('http://127.0.0.1:${preview.port}/')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        clearCache: true,
        cacheMode: CacheMode.LOAD_NO_CACHE,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        builtInZoomControls: true,
        displayZoomControls: false,
      ),
      onWebViewCreated: (ctrl) => _webCtrl = ctrl,
    );
  }
}
