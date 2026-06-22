// AI file-edit protocol for VibeIDE agent mode.
//
// The model is instructed to output file changes as fenced blocks:
//
//   <<<VIBE_EDIT path="relative/path/from/repo/root.ext">>>
//   <full new file content>
//   <<<END_VIBE_EDIT>>>
//
// Full file content is used (not diffs) because diffs are error-prone for
// LLMs producing plain text. This module:
//   • defines the system prompt that activates agent mode,
//   • parses `<<<VIBE_EDIT ...>>>` blocks out of AI responses,
//   • strips those blocks from the displayed prose (replacing each with a
//     short inline marker so the chat bubble stays readable).

/// The system-prompt text prepended to the user message when agent mode is on.
///
/// It is embedded as a user-role turn (not a separate "system" field) so it
/// works across Claude, OpenAI, and Gemini adapters uniformly.
const String kAgentSystemPrompt = '''
You are a coding agent inside VibeIDE, a mobile IDE that runs a real Alpine Linux sandbox. The user wants you to READ and EDIT files in their project.

When you need to create or modify a file, output its full new content inside a fenced block EXACTLY like this (no deviation):

<<<VIBE_EDIT path="relative/path/from/repo/root.ext">>>
<complete new file content goes here>
<<<END_VIBE_EDIT>>>

Rules:
- Output the COMPLETE new content of every file you change (never a partial diff or snippet).
- The path is relative to the project root (e.g. "lib/main.dart", "pubspec.yaml").
- To create a new file use the same block with its new path.
- You may include normal prose explanation outside these blocks. Put your explanation BEFORE the blocks.
- Keep edits minimal and focused on the user's request.
- If you only need to explain something without changing files, just reply normally — no blocks needed.
''';

/// A parsed file edit extracted from an AI response.
class FileEdit {
  final String path;
  final String content;
  const FileEdit({required this.path, required this.content});
}

// Regex: matches <<<VIBE_EDIT path="...">>\n...\n<<<END_VIBE_EDIT>>>
// Using non-greedy [\s\S]*? to handle multiple blocks.
final _editBlockRe = RegExp(
  r'<<<VIBE_EDIT path="([^"]+)">>>([\s\S]*?)<<<END_VIBE_EDIT>>>',
  multiLine: true,
);

/// Parses all `<<<VIBE_EDIT ...>>>` blocks from [aiResponse].
///
/// Malformed or unterminated blocks are silently skipped.
/// The path must be non-empty; leading/trailing newlines are stripped from
/// the captured content.
List<FileEdit> parseEdits(String aiResponse) {
  final edits = <FileEdit>[];
  for (final match in _editBlockRe.allMatches(aiResponse)) {
    final path = match.group(1)?.trim() ?? '';
    var content = match.group(2) ?? '';
    // Strip a single leading newline (right after the opening tag) and a
    // single trailing newline (right before the closing tag).
    if (content.startsWith('\n')) content = content.substring(1);
    if (content.endsWith('\n')) content = content.substring(0, content.length - 1);
    if (path.isEmpty) continue;
    edits.add(FileEdit(path: path, content: content));
  }
  return edits;
}

/// Replaces every `<<<VIBE_EDIT ...>>> ... <<<END_VIBE_EDIT>>>` block in
/// [response] with a short human-readable marker, so the chat bubble shows
/// the AI's prose explanation without the giant file dumps.
String stripEdits(String response) {
  return response.replaceAllMapped(_editBlockRe, (match) {
    final path = match.group(1)?.trim() ?? '';
    return '\u{1F4DD} Editing $path';
  }).trim();
}

/// Flattens a file-tree into a list of relative file paths (non-directories
/// only), capped to [maxPaths] entries. Used to build the lean project-context
/// blob sent to the AI when agent mode is on.
List<String> collectFilePaths(
  dynamic node, {
  int maxPaths = 100,
  String prefix = '',
}) {
  final results = <String>[];
  _collectPaths(node, prefix, results, maxPaths);
  return results;
}

void _collectPaths(
  dynamic node,
  String prefix,
  List<String> results,
  int max,
) {
  if (results.length >= max) return;
  final isDir = node.isDir as bool;
  final name = node.name as String;
  final path = prefix.isEmpty ? name : '$prefix/$name';
  if (!isDir) {
    results.add(path);
    return;
  }
  final children = node.children as List<dynamic>;
  for (final child in children) {
    if (results.length >= max) return;
    _collectPaths(child, path, results, max);
  }
}
