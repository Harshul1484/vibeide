/// Which version to keep when resolving a merge conflict block.
enum ConflictChoice {
  /// Keep the HEAD / local ("current") version.
  current,

  /// Keep the incoming ("their") version.
  incoming,

  /// Keep both versions (current first, then incoming).
  both,
}

/// Returns the number of conflict blocks in [content] by counting lines that
/// start with `<<<<<<<`.
int countConflicts(String content) {
  var count = 0;
  for (final line in content.split('\n')) {
    if (line.startsWith('<<<<<<<')) count++;
  }
  return count;
}

/// Resolves ALL merge-conflict blocks in [content] according to [choice].
///
/// Uses a line-based state machine — NOT a regex — so it handles multiple
/// conflict blocks in one file correctly.
///
/// Each conflict block has the form:
/// ```
/// <<<<<<< HEAD
/// ... current lines ...
/// =======
/// ... incoming lines ...
/// >>>>>>> branch
/// ```
///
/// The three marker lines are always dropped; only the selected content is
/// emitted.
String resolveConflicts(String content, ConflictChoice choice) {
  // Normalise line endings — we'll re-join with '\n' at the end.
  final lines = content.split('\n');
  final result = <String>[];

  // State machine states.
  const outside = 0;
  const inCurrent = 1;
  const inIncoming = 2;

  var state = outside;
  final currentLines = <String>[];
  final incomingLines = <String>[];

  for (final line in lines) {
    switch (state) {
      case outside:
        if (line.startsWith('<<<<<<<')) {
          // Begin a conflict block — drop the marker line.
          state = inCurrent;
          currentLines.clear();
          incomingLines.clear();
        } else {
          result.add(line);
        }
        break;

      case inCurrent:
        if (line.startsWith('=======')) {
          // Switch to collecting incoming lines — drop the separator.
          state = inIncoming;
        } else {
          currentLines.add(line);
        }
        break;

      case inIncoming:
        if (line.startsWith('>>>>>>>')) {
          // End of conflict block — emit based on choice.
          switch (choice) {
            case ConflictChoice.current:
              result.addAll(currentLines);
              break;
            case ConflictChoice.incoming:
              result.addAll(incomingLines);
              break;
            case ConflictChoice.both:
              result.addAll(currentLines);
              result.addAll(incomingLines);
              break;
          }
          state = outside;
          currentLines.clear();
          incomingLines.clear();
        } else {
          incomingLines.add(line);
        }
        break;
    }
  }

  // If the file ended inside an unclosed conflict block (malformed), emit what
  // we have so we don't lose content silently.
  if (state == inCurrent) {
    result.addAll(currentLines);
  } else if (state == inIncoming) {
    result.addAll(incomingLines);
  }

  return result.join('\n');
}
