import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/extensions/extension_catalog.dart';
import 'package:vibeide/features/extensions/extensions_provider.dart';

/// A single lint diagnostic.
class Problem {
  final String file;
  final int? line;
  final int? col;
  final String severity; // 'error' | 'warning' | 'info'
  final String message;

  const Problem({
    required this.file,
    this.line,
    this.col,
    required this.severity,
    required this.message,
  });
}

/// State for the problems panel.
class ProblemsState {
  final List<Problem> problems;
  final bool isLoading;
  final String? noLinterMessage;

  const ProblemsState({
    this.problems = const [],
    this.isLoading = false,
    this.noLinterMessage,
  });

  ProblemsState copyWith({
    List<Problem>? problems,
    bool? isLoading,
    String? noLinterMessage,
  }) =>
      ProblemsState(
        problems: problems ?? this.problems,
        isLoading: isLoading ?? this.isLoading,
        noLinterMessage: noLinterMessage,
      );
}

class ProblemsNotifier extends Notifier<ProblemsState> {
  @override
  ProblemsState build() => const ProblemsState();

  /// Run the linter for [path] and populate the problems list.
  Future<void> runLint(String path) async {
    state = state.copyWith(isLoading: true, noLinterMessage: null);

    final sandboxState = ref.read(sandboxProvider);
    if (sandboxState != SandboxState.ready) {
      state = const ProblemsState(
        noLinterMessage: 'Sandbox not ready.',
      );
      return;
    }

    final installedIds =
        ref.read(installedToolsProvider).valueOrNull ?? const {};
    final linter = linterFor(path, installedIds);

    if (linter == null) {
      final ext = fileExt(path);
      state = ProblemsState(
        noLinterMessage: ext.isEmpty
            ? 'No linter installed for this file type. Install one from Extensions.'
            : 'No linter installed for $ext files. Install one from Extensions.',
      );
      return;
    }

    final cmd = linter.lintCmd!.replaceAll('{file}', path);
    final (_, output) =
        await ref.read(sandboxClientProvider).execToCompletion(
              '/bin/sh',
              ['-lc', cmd],
            );

    state = ProblemsState(
      problems: _parseOutput(output, path),
    );
  }

  /// Tolerant parser: tries to extract file:line:col: message patterns.
  /// Falls back to treating each non-empty line as an info message.
  List<Problem> _parseOutput(String output, String defaultFile) {
    final problems = <Problem>[];
    // Matches optional file prefix, then line:col or just line, then message.
    // e.g. "/path/file.py:10:4: E302 ..."
    //      "10:4  error  ..."
    //      "file.js:5:1: error  ..."
    final lineRe = RegExp(
      r'^(?:([^:]+):)?(\d+)(?::(\d+))?(?::\s*|\s+)(.+)$',
    );

    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final m = lineRe.firstMatch(line);
      if (m != null) {
        final filePart = m.group(1);
        final lineNum = int.tryParse(m.group(2) ?? '');
        final colNum = int.tryParse(m.group(3) ?? '');
        final msg = m.group(4)?.trim() ?? line;
        final severity = _classifySeverity(msg);
        problems.add(Problem(
          file: (filePart != null && filePart.isNotEmpty)
              ? filePart
              : defaultFile,
          line: lineNum,
          col: colNum,
          severity: severity,
          message: msg,
        ));
      } else {
        // No line number — still surface as an info line.
        problems.add(Problem(
          file: defaultFile,
          severity: _classifySeverity(line),
          message: line,
        ));
      }
    }
    return problems;
  }

  String _classifySeverity(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('error')) return 'error';
    if (lower.contains('warning') || lower.contains('warn')) return 'warning';
    return 'info';
  }
}

final problemsNotifierProvider =
    NotifierProvider<ProblemsNotifier, ProblemsState>(ProblemsNotifier.new);

/// Whether the Problems panel is visible in the bottom area.
final problemsOpenProvider = StateProvider<bool>((ref) => false);
