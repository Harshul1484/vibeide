import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'extension_catalog.dart';

class ExtensionsService {
  final SandboxClient _client;

  ExtensionsService(this._client);

  /// Returns true if the tool's check command exits 0 (i.e. is on PATH).
  Future<bool> isInstalled(DevTool t) async {
    final (_, output) = await _client.execToCompletion(
      '/bin/sh',
      ['-lc', '${t.checkCmd} >/dev/null 2>&1 && echo Y || echo N'],
    );
    return output.contains('Y');
  }

  /// Installs the tool into the Alpine sandbox, with retry logic for apk.
  Future<void> install(
    DevTool t, {
    void Function(String line)? onLine,
  }) async {
    String installCmd;

    switch (t.via) {
      case InstallVia.apk:
        installCmd = 'apk add --no-cache ${t.package}';
        break;
      case InstallVia.npm:
        // Ensure npm is available first
        final (_, npmCheckOut) = await _client.execToCompletion(
          '/bin/sh',
          ['-lc', 'command -v npm >/dev/null 2>&1 && echo Y || echo N'],
        );
        if (!npmCheckOut.contains('Y') && npmCheckOut.contains('N')) {
          onLine?.call('Installing Node.js (required for npm)...');
          await _apkInstall('nodejs npm', onLine: onLine);
        }
        installCmd = 'npm install -g ${t.package}';
        break;
      case InstallVia.pip:
        // Ensure pip3 is available first
        final (_, pipCheckOut) = await _client.execToCompletion(
          '/bin/sh',
          ['-lc', 'command -v pip3 >/dev/null 2>&1 && echo Y || echo N'],
        );
        if (!pipCheckOut.contains('Y') && pipCheckOut.contains('N')) {
          onLine?.call('Installing Python 3 (required for pip)...');
          await _apkInstall('python3 py3-pip', onLine: onLine);
        }
        installCmd = 'pip3 install --break-system-packages ${t.package}';
        break;
    }

    if (t.via == InstallVia.apk) {
      await _apkInstall(t.package, onLine: onLine);
    } else {
      final (exitCode, output) = await _client.execToCompletion(
        '/bin/sh',
        ['-lc', installCmd],
        onLine: (line) {
          debugPrint('[install:${t.id}] $line');
          onLine?.call(line);
        },
      );
      if (exitCode != 0) {
        throw Exception('Failed to install ${t.name}:\n$output');
      }
    }
  }

  /// Internal helper: runs `apk add --no-cache <packages>` with up to 3
  /// retries on transient CDN failures (mirrors ensureGit pattern).
  Future<void> _apkInstall(
    String packages, {
    void Function(String line)? onLine,
  }) async {
    String lastOutput = '';
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (attempt > 1) {
        onLine?.call('Network hiccup, retrying ($attempt/3)...');
        await Future.delayed(const Duration(seconds: 2));
      }
      final (code, output) = await _client.execToCompletion(
        '/bin/sh',
        ['-lc', 'apk add --no-cache $packages'],
        onLine: (line) {
          debugPrint('[apk] $line');
          onLine?.call(line);
        },
      );
      lastOutput = output;
      debugPrint('[apk] attempt $attempt exit=$code');
      if (code == 0) return;
    }
    throw Exception('apk add $packages failed after 3 attempts:\n$lastOutput');
  }

  /// Uninstalls the tool from the Alpine sandbox.
  Future<void> uninstall(
    DevTool t, {
    void Function(String line)? onLine,
  }) async {
    final String uninstallCmd;
    switch (t.via) {
      case InstallVia.apk:
        uninstallCmd = 'apk del ${t.package}';
        break;
      case InstallVia.npm:
        uninstallCmd = 'npm uninstall -g ${t.package}';
        break;
      case InstallVia.pip:
        uninstallCmd = 'pip3 uninstall -y --break-system-packages ${t.package}';
        break;
    }

    final (exitCode, output) = await _client.execToCompletion(
      '/bin/sh',
      ['-lc', uninstallCmd],
      onLine: (line) {
        debugPrint('[uninstall:${t.id}] $line');
        onLine?.call(line);
      },
    );
    if (exitCode != 0) {
      throw Exception('Failed to uninstall ${t.name}:\n$output');
    }
  }
}

final extensionsServiceProvider = Provider<ExtensionsService>(
  (ref) => ExtensionsService(ref.watch(sandboxClientProvider)),
);

/// Returns the set of installed tool IDs. Re-evaluates whenever the sandbox
/// state changes; returns empty set when sandbox is not ready.
final installedToolsProvider = FutureProvider<Set<String>>((ref) async {
  final sandboxState = ref.watch(sandboxProvider);
  if (sandboxState != SandboxState.ready) return {};

  final service = ref.watch(extensionsServiceProvider);
  final results = await Future.wait(
    devToolCatalog.map((tool) async {
      try {
        final installed = await service.isInstalled(tool);
        return installed ? tool.id : null;
      } catch (_) {
        return null;
      }
    }),
  );
  return results.whereType<String>().toSet();
});
