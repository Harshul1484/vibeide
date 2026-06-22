import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';

const _kLiveServerPort = 5500;

class PreviewState {
  final bool running;
  final int port;
  final String? error;

  const PreviewState({
    required this.running,
    required this.port,
    this.error,
  });

  PreviewState copyWith({
    bool? running,
    int? port,
    String? error,
    bool clearError = false,
  }) {
    return PreviewState(
      running: running ?? this.running,
      port: port ?? this.port,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LivePreviewNotifier extends Notifier<PreviewState> {
  @override
  PreviewState build() {
    return const PreviewState(running: false, port: _kLiveServerPort);
  }

  Future<void> start() async {
    final sandboxState = ref.read(sandboxProvider);
    if (sandboxState != SandboxState.ready) {
      state = state.copyWith(
        error: 'Sandbox is not ready. Please wait for it to boot.',
      );
      return;
    }

    final project = ref.read(activeProjectProvider);
    if (project == null) {
      state = state.copyWith(error: 'No active project. Open a project first.');
      return;
    }

    // Clear previous error
    state = state.copyWith(clearError: true);

    final client = ref.read(sandboxClientProvider);
    final projectPath = project.localPath;

    // Check if python3 is available
    final (checkCode, checkOut) = await client.execToCompletion(
      '/bin/sh',
      ['-lc', 'command -v python3 2>/dev/null || echo ""'],
    );

    final hasPython3 = checkCode == 0 && checkOut.trim().isNotEmpty;

    // Kill any existing server on the port
    await client.execToCompletion(
      '/bin/sh',
      [
        '-lc',
        'pkill -f "http.server $_kLiveServerPort" 2>/dev/null; '
            'pkill -f "httpd.*$_kLiveServerPort" 2>/dev/null; '
            'true',
      ],
    );

    // Small delay to ensure processes are killed
    await Future.delayed(const Duration(milliseconds: 300));

    if (hasPython3) {
      // Start python3 http.server detached via nohup subshell
      final (exitCode, output) = await client.execToCompletion(
        '/bin/sh',
        [
          '-lc',
          'cd "$projectPath" && '
              '(python3 -m http.server $_kLiveServerPort '
              '>/tmp/liveserver.log 2>&1 &) ; '
              'sleep 1 ; echo started',
        ],
      );

      if (exitCode != 0) {
        state = state.copyWith(
          error: 'Failed to start Live Server: ${output.trim()}',
        );
        return;
      }
    } else {
      // Fallback: busybox httpd (daemonizes by default)
      final (exitCode, output) = await client.execToCompletion(
        '/bin/sh',
        [
          '-lc',
          'busybox httpd -p $_kLiveServerPort -h "$projectPath" 2>/tmp/liveserver.log ; '
              'echo started',
        ],
      );

      if (exitCode != 0) {
        state = state.copyWith(
          error: 'Failed to start Live Server (busybox httpd): ${output.trim()}\n'
              'Tip: Install Python 3 from Extensions for a more reliable server.',
        );
        return;
      }
    }

    state = state.copyWith(running: true, port: _kLiveServerPort, clearError: true);
  }

  Future<void> stop() async {
    final client = ref.read(sandboxClientProvider);
    await client.execToCompletion(
      '/bin/sh',
      [
        '-lc',
        'pkill -f "http.server $_kLiveServerPort" 2>/dev/null; '
            'pkill -f "httpd" 2>/dev/null; '
            'true',
      ],
    );
    state = state.copyWith(running: false, clearError: true);
  }
}

final livePreviewProvider =
    NotifierProvider<LivePreviewNotifier, PreviewState>(
        LivePreviewNotifier.new);

/// Convenience: the full URL to serve from.
final previewUrlProvider = Provider<String>((ref) {
  final port = ref.watch(livePreviewProvider).port;
  return 'http://127.0.0.1:$port/';
});

/// Whether the preview panel is currently shown in the editor area.
final previewOpenProvider = StateProvider<bool>((ref) => false);
