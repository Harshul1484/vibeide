/// Data model for the git commit graph.
library;

/// A single commit entry parsed from `git log --all --pretty=format:...`.
class GitCommit {
  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.parents,
    required this.author,
    required this.message,
    required this.refs,
  });

  /// Full 40-char SHA-1.
  final String hash;

  /// Abbreviated hash (7 chars by default).
  final String shortHash;

  /// Full hashes of parent commits (empty for root commits, two for merges).
  final List<String> parents;

  /// Author name (from %an).
  final String author;

  /// Commit subject line (from %s).
  final String message;

  /// Decorations from %D, e.g. ["HEAD -> main", "origin/main", "tag: v1.0"].
  /// Empty if no refs point to this commit.
  final List<String> refs;
}
