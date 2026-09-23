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
/// (running/done/failed/incomplete) plus the stage timeline, present on
/// every status so the timeline stays visible (with final timings) after
/// completion too.
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

/// One entry of GET /runs/incomplete (see fluid's src/bin/weld_service/
/// main.rs and api_types.rs's IncompleteRunSummary) -- a run whose solving
/// stage was left open by a process that went away mid-solve, discovered by
/// weld_service on startup. `request` is kept as the raw JSON map (rather
/// than parsed into WeldParameters) since it's only ever used here to show a
/// short human-readable summary in the startup "resume or restart?" dialog,
/// not fed back into the parameter panel.
class IncompleteRun {
  final String runId;
  final double? latestTimeS;
  final double? endTimeS;
  final Map<String, dynamic>? request;
  // True only if this run was stopped via an explicit, deliberate Pause
  // that confirmed ferrousFoam exited cleanly (see fluid's
  // case_runner::pause_run / is_paused_cleanly) -- false for a run left by
  // a crash/force-quit/kill -9, which is never safe to resume from (the
  // last written timestep may itself be mid-write/torn). A non-resumable
  // run's last snapshot is still viewable read-only ("View last result"),
  // just not continuable ("Continue").
  final bool resumable;

  const IncompleteRun({
    required this.runId,
    this.latestTimeS,
    this.endTimeS,
    this.request,
    required this.resumable,
  });

  factory IncompleteRun.fromJson(Map<String, dynamic> json) => IncompleteRun(
        runId: json['run_id'] as String,
        latestTimeS: (json['latest_time_s'] as num?)?.toDouble(),
        endTimeS: (json['end_time_s'] as num?)?.toDouble(),
        request: json['request'] as Map<String, dynamic>?,
        resumable: json['resumable'] as bool? ?? false,
      );
}

/// What the user picked in the startup gate's incomplete-run dialog (see
/// main.dart's _StartupGate) -- carried into WeldBenchHome so it can kick
/// off the resume/restart/view the same way a fresh "Weld" button press
/// would (resume/restart) or as a plain one-shot fetch (view).
enum RunActionKind {
  /// Continue solving from where it left off -- only ever offered for a
  /// `resumable: true` run (see IncompleteRun.resumable).
  resume,

  /// Discard progress and re-solve from scratch with the same parameters.
  restart,

  /// A non-resumable (crashed/abandoned) run's dead end: fetch whatever
  /// partial heightmap snapshot it left behind and show it read-only in the
  /// normal comparison view -- no resume, no polling, no "still running"
  /// spinner.
  view,
}

class PendingRunAction {
  final String runId;
  final RunActionKind kind;

  const PendingRunAction({required this.runId, required this.kind});
}

/// One entry of GET /runs (see fluid's main.rs::list_run_history and
/// api_types.rs's RunHistoryEntry) -- every weld run weld_service has ever
/// staged, found by scanning its runs/ directory directly rather than
/// relying on in-memory state, so this covers runs from before the current
/// weld_service process even started. Backs the "past welds" dropdown.
enum RunHistoryStatus {
  running,
  done,
  incompleteResumable,
  incompleteNotResumable;

  static RunHistoryStatus fromWire(String s) => switch (s) {
        'running' => RunHistoryStatus.running,
        'done' => RunHistoryStatus.done,
        'incomplete_resumable' => RunHistoryStatus.incompleteResumable,
        'incomplete_not_resumable' => RunHistoryStatus.incompleteNotResumable,
        _ => RunHistoryStatus.incompleteNotResumable,
      };

  String get label => switch (this) {
        RunHistoryStatus.running => 'running',
        RunHistoryStatus.done => 'done',
        RunHistoryStatus.incompleteResumable => 'paused (resumable)',
        RunHistoryStatus.incompleteNotResumable => 'incomplete',
      };
}

class RunHistoryEntry {
  final String runId;
  final double? startedAtS;
  final RunHistoryStatus status;
  final double? latestTimeS;
  final double? endTimeS;
  final Map<String, dynamic>? request;
  final bool hasHeightmap;

  const RunHistoryEntry({
    required this.runId,
    this.startedAtS,
    required this.status,
    this.latestTimeS,
    this.endTimeS,
    this.request,
    required this.hasHeightmap,
  });

  DateTime? get startedAt =>
      startedAtS == null ? null : DateTime.fromMillisecondsSinceEpoch((startedAtS! * 1000).round());

  factory RunHistoryEntry.fromJson(Map<String, dynamic> json) => RunHistoryEntry(
        runId: json['run_id'] as String,
        startedAtS: (json['started_at_s'] as num?)?.toDouble(),
        status: RunHistoryStatus.fromWire(json['status'] as String),
        latestTimeS: (json['latest_time_s'] as num?)?.toDouble(),
        endTimeS: (json['end_time_s'] as num?)?.toDouble(),
        request: json['request'] as Map<String, dynamic>?,
        hasHeightmap: json['has_heightmap'] as bool? ?? false,
      );
}
