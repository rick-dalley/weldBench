import 'dart:async';
import 'package:flutter/material.dart';

import '../models/run_progress.dart';

const _stageLabels = {
  'staging': 'Staging case',
  'meshing': 'Building mesh',
  'initializing': 'Initializing fields',
  'solving': 'Solving',
};

const _stageOrder = ['staging', 'meshing', 'initializing', 'solving'];

String _formatDuration(double seconds) {
  final d = Duration(milliseconds: (seconds * 1000).round());
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// A horizontal row of stage steps (staging -> meshing -> initializing ->
/// solving), each showing elapsed/running time, so a full weld run -- which
/// can take tens of minutes -- reads as "here's what's happening and how
/// long it's taken so far" rather than a bare spinner. Ticks once a second
/// on its own so the active stage's timer runs smoothly between polls.
class StageTimeline extends StatefulWidget {
  final List<StageRecord> stages;
  final SolveProgress? solveProgress;

  const StageTimeline({super.key, required this.stages, this.solveProgress});

  @override
  State<StageTimeline> createState() => _StageTimelineState();
}

class _StageTimelineState extends State<StageTimeline> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stages.isEmpty) return const SizedBox.shrink();

    final byName = {for (final s in widget.stages) s.name: s};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final name in _stageOrder) _stageChip(context, name, byName[name]),
        ],
      ),
    );
  }

  Widget _stageChip(BuildContext context, String name, StageRecord? record) {
    final label = _stageLabels[name] ?? name;
    final theme = Theme.of(context);

    if (record == null) {
      // Not reached yet.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle_outlined, size: 16, color: theme.disabledColor),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: theme.disabledColor)),
        ],
      );
    }

    final isActive = !record.isDone;
    final elapsed = _formatDuration(record.elapsedS());
    final isSolving = name == 'solving';
    final progress = widget.solveProgress;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isActive)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: isSolving ? progress?.fraction : null,
            ),
          )
        else
          Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
        const SizedBox(width: 6),
        Text(label, style: isActive ? const TextStyle(fontWeight: FontWeight.bold) : null),
        const SizedBox(width: 6),
        Text('($elapsed)', style: theme.textTheme.bodySmall),
        if (isActive && isSolving && progress != null) ...[
          const SizedBox(width: 6),
          Text(
            '— ${(progress.fraction * 100).toStringAsFixed(1)}% '
            '(${progress.simulatedTimeS.toStringAsFixed(4)}s / ${progress.endTimeS.toStringAsFixed(4)}s simulated)',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
