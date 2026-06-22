import 'package:flutter/material.dart';
import 'package:vibeide/shared/theme.dart';

// Diff line types
enum _DiffLineKind { fileHeader, hunkHeader, added, removed, context }

class _DiffLine {
  final _DiffLineKind kind;
  final String text;
  const _DiffLine(this.kind, this.text);
}

List<_DiffLine> _parse(String unifiedDiff) {
  final lines = <_DiffLine>[];
  for (final raw in unifiedDiff.split('\n')) {
    if (raw.startsWith('diff --git') ||
        raw.startsWith('index ') ||
        raw.startsWith('--- ') ||
        raw.startsWith('+++ ')) {
      lines.add(_DiffLine(_DiffLineKind.fileHeader, raw));
    } else if (raw.startsWith('@@ ')) {
      lines.add(_DiffLine(_DiffLineKind.hunkHeader, raw));
    } else if (raw.startsWith('+')) {
      lines.add(_DiffLine(_DiffLineKind.added, raw));
    } else if (raw.startsWith('-')) {
      lines.add(_DiffLine(_DiffLineKind.removed, raw));
    } else {
      lines.add(_DiffLine(_DiffLineKind.context, raw));
    }
  }
  return lines;
}

/// A widget that renders a unified diff string with syntax-highlighted lines.
/// When [split] is true it renders a side-by-side two-column view; otherwise
/// a standard unified view.
class DiffView extends StatelessWidget {
  final String unifiedDiff;
  final bool split;

  const DiffView({super.key, required this.unifiedDiff, this.split = false});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final lines = _parse(unifiedDiff);

    if (unifiedDiff.trim().isEmpty) {
      return Center(
        child: Text(
          'No diff to display',
          style: TextStyle(color: c.fgMuted, fontSize: 12),
        ),
      );
    }

    if (split) {
      return _SplitView(lines: lines, c: c);
    }
    return _UnifiedView(lines: lines, c: c);
  }
}

// ---------------------------------------------------------------------------
// Unified view
// ---------------------------------------------------------------------------

class _UnifiedView extends StatelessWidget {
  final List<_DiffLine> lines;
  final VsCodeColors c;
  const _UnifiedView({required this.lines, required this.c});

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines.map((l) => _UnifiedLine(line: l, c: c)).toList(),
          ),
        ),
      ),
    );
  }
}

class _UnifiedLine extends StatelessWidget {
  final _DiffLine line;
  final VsCodeColors c;
  const _UnifiedLine({required this.line, required this.c});

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color textColor;
    String marker;
    double fontSize;

    switch (line.kind) {
      case _DiffLineKind.added:
        bg = const Color(0xFF1B3329);
        textColor = const Color(0xFF3FB950);
        marker = '+';
        fontSize = 12;
      case _DiffLineKind.removed:
        bg = const Color(0xFF3A1D1D);
        textColor = const Color(0xFFF85149);
        marker = '-';
        fontSize = 12;
      case _DiffLineKind.hunkHeader:
        bg = const Color(0xFF0D1F3A);
        textColor = const Color(0xFF79C0FF);
        marker = ' ';
        fontSize = 11;
      case _DiffLineKind.fileHeader:
        bg = null;
        textColor = c.fgMuted;
        marker = ' ';
        fontSize = 11;
      case _DiffLineKind.context:
        bg = null;
        textColor = c.fg;
        marker = ' ';
        fontSize = 12;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: Text(
              marker,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize,
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
          Text(
            line.text.length > 1 ? line.text.substring(1) : '',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: fontSize,
              color: textColor,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Split view — two-column side by side
// ---------------------------------------------------------------------------

class _SplitLine {
  final String? left;  // removed / context
  final String? right; // added / context
  final _DiffLineKind kind;
  const _SplitLine({this.left, this.right, required this.kind});
}

List<_SplitLine> _toSplitLines(List<_DiffLine> lines) {
  final result = <_SplitLine>[];
  var i = 0;
  while (i < lines.length) {
    final l = lines[i];
    if (l.kind == _DiffLineKind.fileHeader ||
        l.kind == _DiffLineKind.hunkHeader) {
      result.add(_SplitLine(left: l.text, right: l.text, kind: l.kind));
      i++;
    } else if (l.kind == _DiffLineKind.context) {
      result.add(_SplitLine(left: l.text, right: l.text, kind: l.kind));
      i++;
    } else if (l.kind == _DiffLineKind.removed) {
      // Collect a run of removals then a run of additions and pair them.
      final removals = <String>[];
      while (i < lines.length && lines[i].kind == _DiffLineKind.removed) {
        removals.add(lines[i].text);
        i++;
      }
      final additions = <String>[];
      while (i < lines.length && lines[i].kind == _DiffLineKind.added) {
        additions.add(lines[i].text);
        i++;
      }
      final max = removals.length > additions.length
          ? removals.length
          : additions.length;
      for (var j = 0; j < max; j++) {
        result.add(_SplitLine(
          left: j < removals.length ? removals[j] : null,
          right: j < additions.length ? additions[j] : null,
          kind: _DiffLineKind.removed, // sentinel; we check left/right nullness
        ));
      }
    } else if (l.kind == _DiffLineKind.added) {
      result.add(_SplitLine(left: null, right: l.text, kind: _DiffLineKind.added));
      i++;
    } else {
      i++;
    }
  }
  return result;
}

class _SplitView extends StatelessWidget {
  final List<_DiffLine> lines;
  final VsCodeColors c;
  const _SplitView({required this.lines, required this.c});

  @override
  Widget build(BuildContext context) {
    final splitLines = _toSplitLines(lines);

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: splitLines.map((sl) => _SplitRow(sl: sl, c: c)).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  final _SplitLine sl;
  final VsCodeColors c;
  const _SplitRow({required this.sl, required this.c});

  @override
  Widget build(BuildContext context) {
    if (sl.kind == _DiffLineKind.fileHeader ||
        sl.kind == _DiffLineKind.hunkHeader) {
      final textColor = sl.kind == _DiffLineKind.hunkHeader
          ? const Color(0xFF79C0FF)
          : c.fgMuted;
      final bg = sl.kind == _DiffLineKind.hunkHeader
          ? const Color(0xFF0D1F3A)
          : null;
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Text(
          sl.left ?? '',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: textColor,
            height: 1.4,
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SplitCell(
            text: sl.left,
            isAdded: false,
            hasContent: sl.left != null,
            c: c,
          ),
          Container(width: 1, color: c.border),
          _SplitCell(
            text: sl.right,
            isAdded: true,
            hasContent: sl.right != null,
            c: c,
          ),
        ],
      ),
    );
  }
}

class _SplitCell extends StatelessWidget {
  final String? text;
  final bool isAdded;
  final bool hasContent;
  final VsCodeColors c;
  const _SplitCell({
    required this.text,
    required this.isAdded,
    required this.hasContent,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color textColor;
    String marker;

    if (!hasContent) {
      // Empty cell (padding for un-paired lines)
      return SizedBox(
        width: 340,
        child: Container(color: const Color(0xFF161616)),
      );
    }

    if (text != null && text!.startsWith('+')) {
      bg = const Color(0xFF1B3329);
      textColor = const Color(0xFF3FB950);
      marker = '+';
    } else if (text != null && text!.startsWith('-')) {
      bg = const Color(0xFF3A1D1D);
      textColor = const Color(0xFFF85149);
      marker = '-';
    } else {
      bg = null;
      textColor = c.fg;
      marker = ' ';
    }

    final content = text ?? '';
    final displayText = content.length > 1 ? content.substring(1) : '';

    return Container(
      width: 340,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 12,
            child: Text(
              marker,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
