import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'package:vibeide/features/extensions/extensions_provider.dart';

class SearchHit {
  final String file; // relative path
  final int line;
  final String text; // the matching line

  const SearchHit({
    required this.file,
    required this.line,
    required this.text,
  });
}

class SearchResults {
  final List<SearchHit> hits;
  final int fileCount;

  const SearchResults({required this.hits, required this.fileCount});

  static const empty = SearchResults(hits: [], fileCount: 0);
}

/// Escapes a query string for safe embedding in a double-quoted shell argument.
String _escapeForShell(String s) {
  return s.replaceAll(r'\', r'\\').replaceAll(r'"', r'\"').replaceAll(r'$', r'\$');
}

Future<SearchResults> runSearch(
  WidgetRef ref,
  String query, {
  bool caseSensitive = false,
  bool regex = false,
}) async {
  final sandboxState = ref.read(sandboxProvider);
  if (sandboxState != SandboxState.ready) return SearchResults.empty;

  final project = ref.read(activeProjectProvider);
  if (project == null) return SearchResults.empty;

  final q = query.trim();
  if (q.isEmpty) return SearchResults.empty;

  final projectPath = project.localPath;
  final client = ref.read(sandboxClientProvider);
  final installedTools = ref.read(installedToolsProvider).valueOrNull ?? const {};
  final hasRg = installedTools.contains('ripgrep');

  final escapedQuery = _escapeForShell(q);
  final escapedPath = projectPath.replaceAll("'", "'\\''");

  final String cmd;
  if (hasRg) {
    // rg: --line-number --no-heading --color never
    // -F for fixed strings (non-regex), -i for case insensitive
    final flags = StringBuffer();
    if (!caseSensitive) flags.write(' -i');
    if (!regex) flags.write(' -F');
    cmd = 'cd \'$escapedPath\' && rg --line-number --no-heading --color never$flags -m 200 -- "$escapedQuery" . 2>/dev/null | head -500';
  } else {
    // grep fallback
    final flags = StringBuffer('-rn');
    if (!caseSensitive) flags.write('i');
    if (!regex) flags.write('F');
    cmd = 'cd \'$escapedPath\' && grep -${flags.toString()} -- "$escapedQuery" . 2>/dev/null | head -500';
  }

  final (_, output) = await client.execToCompletion('/bin/sh', ['-lc', cmd]);

  final hits = <SearchHit>[];
  final filesSeen = <String>{};

  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    // Format: ./path/to/file:lineNum:matchtext  OR  path/to/file:lineNum:matchtext
    // Strip leading ./ if present
    final stripped = line.startsWith('./') ? line.substring(2) : line;

    // Find first colon (file path)
    final firstColon = stripped.indexOf(':');
    if (firstColon < 0) continue;

    // Find second colon (line number)
    final secondColon = stripped.indexOf(':', firstColon + 1);
    if (secondColon < 0) continue;

    final filePart = stripped.substring(0, firstColon);
    final lineNumPart = stripped.substring(firstColon + 1, secondColon);
    final textPart = stripped.substring(secondColon + 1);

    final lineNum = int.tryParse(lineNumPart);
    if (lineNum == null) continue;
    if (filePart.isEmpty) continue;

    filesSeen.add(filePart);
    hits.add(SearchHit(file: filePart, line: lineNum, text: textPart));

    if (hits.length >= 500) break;
  }

  return SearchResults(hits: hits, fileCount: filesSeen.length);
}
