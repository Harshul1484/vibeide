import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/codicons.dart';
import '../../shared/theme.dart';
import 'git_graph.dart';
import 'git_provider.dart';

// ─── Lane colour palette (VS Code–style) ────────────────────────────────────

const _laneColors = [
  Color(0xFF0078D4), // accent blue
  Color(0xFF3FB950), // green
  Color(0xFFD29922), // amber
  Color(0xFFA371F7), // purple
  Color(0xFF39C5CF), // cyan
  Color(0xFFE06C75), // red
];

Color _laneColor(int lane) => _laneColors[lane % _laneColors.length];

const double _rowHeight = 36;
const double _laneWidth = 40;
const double _nodeRadius = 5;
const double _lineWidth = 2;

// ─── Lane assignment ─────────────────────────────────────────────────────────

/// Assigns a lane index to every commit for a simple multi-lane layout.
///
/// Algorithm (simple greedy, top-down):
///   • Each "active slot" holds the hash of the commit that must eventually
///     be reached (i.e., a parent we haven't visited yet).
///   • When we visit commit i:
///     - find the slot whose expected-hash == commits[i].hash → that's the lane.
///     - if no slot matches, open a new slot.
///     - replace that slot's expected-hash with the first parent (continuing the
///       lane); open new slots for any additional parents.
///   • Result: lanes[i] is the integer lane index for commit at position i.
///
/// For pure linear history this always gives lane 0 for every commit.
List<int> _assignLanes(List<GitCommit> commits) {
  // slots[j] = hash of the next commit expected in lane j, or null if free.
  final slots = <String?>[];
  final lanes = <int>[];

  for (final commit in commits) {
    // Find a slot waiting for this commit.
    var lane = slots.indexOf(commit.hash);
    if (lane == -1) {
      // No slot waiting — open a new lane.
      lane = slots.indexOf(null);
      if (lane == -1) {
        lane = slots.length;
        slots.add(null);
      }
    }

    lanes.add(lane);

    // Update the slot with the first parent (lane continues).
    final firstParent = commit.parents.isNotEmpty ? commit.parents[0] : null;
    slots[lane] = firstParent;

    // Open new slots for additional parents (merge commits).
    for (var p = 1; p < commit.parents.length; p++) {
      final parentHash = commit.parents[p];
      // Check if there's already a slot waiting for this parent.
      if (!slots.contains(parentHash)) {
        final free = slots.indexOf(null);
        if (free != -1) {
          slots[free] = parentHash;
        } else {
          slots.add(parentHash);
        }
      }
    }
  }

  return lanes;
}

// ─── Graph painter ────────────────────────────────────────────────────────────

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.commits,
    required this.lanes,
    required this.index,
  });

  final List<GitCommit> commits;
  final List<int> lanes;
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final commit = commits[index];
    final myLane = lanes[index];
    final cx = _nodeCenterX(myLane);
    final cy = size.height / 2;

    // ── Draw connecting lines first (behind node) ────────────────────────────

    // Determine which lanes are "passing through" this row.
    // A passing lane is one that was opened above and continues below,
    // not the current commit's lane.
    final usedLanesAbove = <int>{};
    for (var i = 0; i < index; i++) {
      usedLanesAbove.add(lanes[i]);
    }

    // Draw the vertical line coming DOWN from this commit to its parent.
    if (commit.parents.isNotEmpty) {
      // Find first parent index.
      final firstParentIdx = _findParentIndex(commit.parents[0]);
      if (firstParentIdx != null && firstParentIdx < commits.length) {
        final parentLane = lanes[firstParentIdx];
        final paint = Paint()
          ..color = _laneColor(myLane)
          ..strokeWidth = _lineWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        if (parentLane == myLane) {
          // Straight vertical line.
          canvas.drawLine(
            Offset(cx, cy + _nodeRadius),
            Offset(cx, size.height),
            paint,
          );
        } else {
          // Curved line going toward parent lane.
          final targetX = _nodeCenterX(parentLane);
          final path = Path()
            ..moveTo(cx, cy + _nodeRadius)
            ..cubicTo(
              cx, cy + size.height * 0.4,
              targetX, cy + size.height * 0.6,
              targetX, size.height,
            );
          canvas.drawPath(path, paint);
        }
      }
    }

    // Draw the vertical line coming UP from this commit to its child.
    // Find which commit above has this commit as its first parent.
    final childIdx = _findChildIndex(index);
    if (childIdx != null) {
      final childLane = lanes[childIdx];
      final paint = Paint()
        ..color = _laneColor(childLane)
        ..strokeWidth = _lineWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      if (childLane == myLane) {
        canvas.drawLine(
          Offset(cx, 0),
          Offset(cx, cy - _nodeRadius),
          paint,
        );
      } else {
        final fromX = _nodeCenterX(childLane);
        final path = Path()
          ..moveTo(fromX, 0)
          ..cubicTo(
            fromX, size.height * 0.4,
            cx, size.height * 0.6,
            cx, cy - _nodeRadius,
          );
        canvas.drawPath(path, paint);
      }
    }

    // Draw pass-through lines for lanes that bypass this row.
    _drawPassThroughLines(canvas, size, index);

    // ── Draw the commit node ─────────────────────────────────────────────────
    final nodePaint = Paint()
      ..color = _laneColor(myLane)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx, cy), _nodeRadius, nodePaint);

    // Thin ring outline.
    canvas.drawCircle(
      Offset(cx, cy),
      _nodeRadius,
      Paint()
        ..color = Colors.black.withAlpha(100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// Returns the horizontal center (in pixels) of a lane column.
  double _nodeCenterX(int lane) =>
      12.0 + lane * 14.0; // lanes spaced 14px apart, first at x=12

  int? _findParentIndex(String parentHash) {
    for (var i = index + 1; i < commits.length; i++) {
      if (commits[i].hash == parentHash) return i;
    }
    return null;
  }

  int? _findChildIndex(int commitIndex) {
    final myHash = commits[commitIndex].hash;
    for (var i = commitIndex - 1; i >= 0; i--) {
      if (commits[i].parents.contains(myHash)) return i;
    }
    return null;
  }

  /// Draw vertical pass-through segments for lanes that are "alive" at this
  /// row but don't own this commit.
  void _drawPassThroughLines(Canvas canvas, Size size, int rowIndex) {
    // Compute the set of active lanes at this row: every parent hash seen
    // in rows above that hasn't been matched to a row yet.
    final activeAtRow = <int, Color>{};

    // Walk from 0..rowIndex-1, track which lanes are still "open".
    final slots = <String?>[];
    for (var i = 0; i < rowIndex; i++) {
      final c = commits[i];
      final lane = lanes[i];
      // Ensure slot exists.
      while (slots.length <= lane) {
        slots.add(null);
      }
      // Advance lane to first parent.
      slots[lane] =
          c.parents.isNotEmpty ? c.parents[0] : null;
      // Add merge parents.
      for (var p = 1; p < c.parents.length; p++) {
        final ph = c.parents[p];
        if (!slots.contains(ph)) {
          final free = slots.indexOf(null);
          if (free != -1) {
            slots[free] = ph;
          } else {
            slots.add(ph);
          }
        }
      }
    }

    // Any non-null slot whose lane != myLane is a pass-through.
    final myLane = lanes[rowIndex];
    for (var lane = 0; lane < slots.length; lane++) {
      if (slots[lane] == null) continue;
      if (lane == myLane) continue;
      final x = _nodeCenterX(lane);
      final paint = Paint()
        ..color = _laneColor(lane)
        ..strokeWidth = _lineWidth
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      activeAtRow[lane] = _laneColor(lane);
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.index != index || old.commits != commits;
}

// ─── Ref pill widget ─────────────────────────────────────────────────────────

class _RefPill extends StatelessWidget {
  const _RefPill({required this.label, required this.isHead});

  final String label;
  final bool isHead;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    // Detect the kind of ref.
    final isTag = label.startsWith('tag:');
    final isRemote = !isTag && label.contains('/') && !label.startsWith('HEAD');
    final displayLabel = label
        .replaceFirst('HEAD -> ', '')
        .replaceFirst('tag: ', '');

    final bg = isHead
        ? c.accent
        : isTag
            ? const Color(0xFF3FB950).withAlpha(40)
            : isRemote
                ? const Color(0xFFA371F7).withAlpha(40)
                : c.accent.withAlpha(40);

    final border = isHead
        ? Colors.transparent
        : isTag
            ? const Color(0xFF3FB950)
            : isRemote
                ? const Color(0xFFA371F7)
                : c.accent;

    final fg = isHead
        ? Colors.white
        : isTag
            ? const Color(0xFF3FB950)
            : isRemote
                ? const Color(0xFFA371F7)
                : c.accent;

    final icon = isTag
        ? Icons.tag
        : isRemote
            ? Codicons.gitBranch
            : Codicons.gitBranch;

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: fg),
          const SizedBox(width: 3),
          Text(
            displayLabel,
            style: TextStyle(
              color: fg,
              fontSize: 9,
              fontWeight: isHead ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Commit bottom sheet ──────────────────────────────────────────────────────

void _showCommitDetails(BuildContext context, GitCommit commit) {
  final c = Theme.of(context).extension<VsCodeColors>()!;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.sidebar,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            commit.message,
            style: TextStyle(
                color: c.fg, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Author: ${commit.author}',
            style: TextStyle(color: c.fgMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  commit.hash,
                  style: TextStyle(
                      color: c.fgMuted,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 16, color: c.fgMuted),
                tooltip: 'Copy hash',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: commit.hash));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hash copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          if (commit.refs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: commit.refs
                  .take(5)
                  .map((r) => _RefPill(
                        label: r,
                        isHead: r.startsWith('HEAD ->'),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ─── Single commit row ────────────────────────────────────────────────────────

class _CommitRow extends StatelessWidget {
  const _CommitRow({
    required this.commit,
    required this.commits,
    required this.lanes,
    required this.index,
    required this.maxLane,
  });

  final GitCommit commit;
  final List<GitCommit> commits;
  final List<int> lanes;
  final int index;
  final int maxLane;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    // Lane column width scales with the max lane used.
    final graphWidth = math.max(_laneWidth, 12.0 + (maxLane + 1) * 14.0);

    return InkWell(
      onTap: () => _showCommitDetails(context, commit),
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Graph lane column ────────────────────────────────────────────
            SizedBox(
              width: graphWidth,
              height: _rowHeight,
              child: CustomPaint(
                painter: _GraphPainter(
                  commits: commits,
                  lanes: lanes,
                  index: index,
                ),
              ),
            ),

            // ── Commit info ──────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: ref pills + message.
                    Row(
                      children: [
                        // Up to 2 ref pills.
                        if (commit.refs.isNotEmpty)
                          ...commit.refs.take(2).map((r) => _RefPill(
                                label: r,
                                isHead: r.startsWith('HEAD ->'),
                              )),
                        if (commit.refs.length > 2)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '+${commit.refs.length - 2}',
                              style: TextStyle(
                                  color: c.fgMuted, fontSize: 9),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            commit.message.isEmpty
                                ? '(no message)'
                                : commit.message,
                            style: TextStyle(
                              color: c.fg,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),

                    // Bottom row: short hash + author.
                    Row(
                      children: [
                        Text(
                          commit.shortHash,
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            commit.author,
                            style: TextStyle(
                                color: c.fgMuted, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Main view ────────────────────────────────────────────────────────────────

/// A scrollable VS Code–style commit graph list.
///
/// Each row has a lane graph column on the left and commit info on the right.
/// Tap a row to see the full hash and copy it.
class GitGraphView extends ConsumerWidget {
  const GitGraphView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final graphAsync = ref.watch(gitGraphProvider);

    return graphAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: c.accent),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Error loading graph',
          style: TextStyle(color: c.fgMuted, fontSize: 12),
        ),
      ),
      data: (commits) {
        if (commits.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No commits yet',
              style: TextStyle(color: c.fgMuted, fontSize: 12),
            ),
          );
        }

        final lanes = _assignLanes(commits);
        final maxLane =
            lanes.isEmpty ? 0 : lanes.reduce((a, b) => a > b ? a : b);

        return ListView.builder(
          itemCount: commits.length,
          itemExtent: _rowHeight,
          itemBuilder: (context, index) => _CommitRow(
            commit: commits[index],
            commits: commits,
            lanes: lanes,
            index: index,
            maxLane: maxLane,
          ),
        );
      },
    );
  }
}
