/// Mirrors weld_service's progress.rs types (see fluid/src/bin/weld_service/
/// progress.rs and api_types.rs's RunStatusResponse) -- one stage record per
/// staging/meshing/initializing/solving transition, plus live solve
/// progress while "solving" is the open stage.
class StageRecord {
  final String name;
  final double startedAtS;
  final double? endedAtS;

  const StageRecord({required this.name, required this.startedAtS, this.endedAtS});

  bool get isDone => endedAtS != null;

  /// Elapsed seconds: the closed duration if done, otherwise time since it
  /// started (computed against wall-clock "now" so this ticks live between
  /// polls, not just when a new status arrives).
  double elapsedS({DateTime? now}) {
    if (endedAtS != null) return endedAtS! - startedAtS;
    final nowS = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000.0;
    return (nowS - startedAtS).clamp(0, double.infinity);
  }

  factory StageRecord.fromJson(Map<String, dynamic> json) => StageRecord(
        name: json['name'] as String,
        startedAtS: (json['started_at_s'] as num).toDouble(),
        endedAtS: (json['ended_at_s'] as num?)?.toDouble(),
      );
}

class SolveProgress {
  final double simulatedTimeS;
  final double endTimeS;
  final double fraction;

  const SolveProgress({required this.simulatedTimeS, required this.endTimeS, required this.fraction});

  factory SolveProgress.fromJson(Map<String, dynamic> json) => SolveProgress(
        simulatedTimeS: (json['simulated_time_s'] as num).toDouble(),
        endTimeS: (json['end_time_s'] as num).toDouble(),
        fraction: (json['fraction'] as num).toDouble(),
      );
}

/// The full status payload from GET /runs/{id}: the plain status string
/// (running/done/failed) plus the stage timeline, present on every status
/// so the timeline stays visible (with final timings) after completion too.
class RunStatusUpdate {
  final String status;
  final List<StageRecord> stages;
  final SolveProgress? solveProgress;
  final String? error;

  const RunStatusUpdate({
    required this.status,
    required this.stages,
    this.solveProgress,
    this.error,
  });

  factory RunStatusUpdate.fromJson(Map<String, dynamic> json) => RunStatusUpdate(
        status: json['status'] as String,
        stages: (json['stages'] as List? ?? [])
            .map((s) => StageRecord.fromJson(s as Map<String, dynamic>))
            .toList(),
        solveProgress:
            json['solve_progress'] != null ? SolveProgress.fromJson(json['solve_progress'] as Map<String, dynamic>) : null,
        error: json['error'] as String?,
      );
}
