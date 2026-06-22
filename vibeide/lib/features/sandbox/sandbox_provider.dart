import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'proot_channel.dart';
import 'sandbox_client.dart';

enum SandboxState { idle, extracting, booting, ready, error }

class SandboxNotifier extends Notifier<SandboxState> {
  final _proot = ProotChannel();
  late final SandboxClient client;

  /// Last boot failure detail, surfaced to the UI.
  String? lastError;

  @override
  SandboxState build() {
    client = SandboxClient();
    return SandboxState.idle;
  }

  Future<void> boot() async {
    lastError = null;
    state = SandboxState.extracting;
    try {
      if (!await _proot.isExtracted()) {
        debugPrint('[boot] extracting Alpine...');
        await _proot.extractAlpine();
      }
      state = SandboxState.booting;
      debugPrint('[boot] starting sandbox (proot)...');
      await _proot.startSandbox();
      debugPrint('[boot] proot started, waiting for vibecli on :7700...');
      final ready = await client.waitForReady();
      debugPrint('[boot] waitForReady=$ready');
      state = ready ? SandboxState.ready : SandboxState.error;
      if (!ready) {
        lastError = 'vibecli did not respond on :7700 within timeout';
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('[boot] FAILED: $e');
      state = SandboxState.error;
    }
  }

  Future<void> stop() async {
    await _proot.stopSandbox();
    state = SandboxState.idle;
  }

  /// Whether the Alpine rootfs has already been extracted to private storage.
  Future<bool> isExtracted() => _proot.isExtracted();

  /// Extract the Alpine sandbox without booting it (used by first-run setup so
  /// the first clone isn't slowed by a ~10s extraction).
  Future<void> extractOnly() async {
    if (await _proot.isExtracted()) return;
    state = SandboxState.extracting;
    try {
      await _proot.extractAlpine();
      state = SandboxState.idle;
    } catch (e) {
      lastError = e.toString();
      state = SandboxState.error;
      rethrow;
    }
  }
}

final sandboxProvider =
    NotifierProvider<SandboxNotifier, SandboxState>(SandboxNotifier.new);

final sandboxClientProvider = Provider<SandboxClient>(
  (ref) => ref.watch(sandboxProvider.notifier).client,
);
