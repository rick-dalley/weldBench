import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/heightmap.dart';
import '../models/run_progress.dart';
import '../models/weld_parameters.dart';

/// Client for the local Rust orchestration service that runs ferrousFoam and
/// returns the resulting puddle/bead heightmap.
///
/// API contract (local HTTP/JSON, default http://localhost:8787):
///   POST /runs                    body: WeldParameters.toJson()
///                                  -> {"run_id": "..."}
///   GET  /runs/{run_id}           -> RunStatusUpdate JSON (status, stage
///                                    timeline, live solve progress -- see
///                                    models/run_progress.dart)
///   GET  /runs/{run_id}/heightmap -> Heightmap JSON (same shape as the
///                                    bundled reference assets), served even
///                                    mid-run once a live snapshot exists
///                                    (Heightmap.complete == false)
///   GET  /runs/incomplete         -> [IncompleteRun] -- runs left mid-solve
///                                    by a process that went away, offered
///                                    to the user at startup (see main.dart's
///                                    _StartupGate)
///   POST /runs/{run_id}/resume    -> {"run_id": "..."} then poll like runWeld
///   POST /runs/{run_id}/restart   -> {"run_id": "..."} then poll like runWeld
///   POST /runs/{run_id}/pause     -> {"run_id": "..."} then poll until not
///                                    `running` (see [WeldService.pauseRun])
class WeldServiceException implements Exception {
  final String message;
  WeldServiceException(this.message);
  @override
  String toString() => 'WeldServiceException: $message';
}

class WeldService {
  final Uri baseUri;
  final http.Client _client;

  WeldService({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? Uri.parse('http://localhost:8787'),
        _client = client ?? http.Client();

  /// Starts a run, polls until it's done, and returns the resulting
  /// heightmap. Calls [onRunId] as soon as the run_id is known (e.g. so a
  /// caller can start a separate concurrent poll of GET
  /// /runs/{run_id}/heightmap for a live mid-solve preview -- see main.dart),
  /// and [onProgress] with each observed status (stage timeline, live solve
  /// progress) while polling.
  Future<Heightmap> runWeld(
    WeldParameters params, {
    void Function(String runId)? onRunId,
    void Function(RunStatusUpdate progress)? onProgress,
    Duration pollInterval = const Duration(milliseconds: 750),
  }) async {
    final startResp = await _client.post(
      baseUri.resolve('/runs'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(params.toJson()),
    );
    if (startResp.statusCode != 200) {
      throw WeldServiceException(
          'Failed to start run: HTTP ${startResp.statusCode} ${startResp.body}');
    }
    final runId = (jsonDecode(startResp.body) as Map<String, dynamic>)['run_id'] as String;
    onRunId?.call(runId);
    return _pollUntilDone(runId, onProgress: onProgress, pollInterval: pollInterval);
  }

  /// Resumes a run left `incomplete` (or `failed`) by a process that went
  /// away mid-solve -- ferrousFoam picks up from its latest written
  /// timestep (see fluid's case_runner.rs::resume_solve). Polls exactly like
  /// [runWeld] afterward; [runId] is already known by the caller (it's an
  /// existing run), so there's no separate `onRunId` callback here.
  Future<Heightmap> resumeRun(
    String runId, {
    void Function(RunStatusUpdate progress)? onProgress,
    Duration pollInterval = const Duration(milliseconds: 750),
  }) async {
    final resp = await _client.post(baseUri.resolve('/runs/$runId/resume'));
    if (resp.statusCode != 200) {
      throw WeldServiceException('Failed to resume run $runId: HTTP ${resp.statusCode} ${resp.body}');
    }
    return _pollUntilDone(runId, onProgress: onProgress, pollInterval: pollInterval);
  }

  /// Discards an incomplete/failed run's progress and re-runs it from
  /// scratch with its originally-saved parameters, keeping the same run_id.
  /// Polls exactly like [runWeld] afterward.
  Future<Heightmap> restartRun(
    String runId, {
    void Function(RunStatusUpdate progress)? onProgress,
    Duration pollInterval = const Duration(milliseconds: 750),
  }) async {
    final resp = await _client.post(baseUri.resolve('/runs/$runId/restart'));
    if (resp.statusCode != 200) {
      throw WeldServiceException('Failed to restart run $runId: HTTP ${resp.statusCode} ${resp.body}');
    }
    return _pollUntilDone(runId, onProgress: onProgress, pollInterval: pollInterval);
  }

  /// Deliberately (and only ever safely-resumably) stops a currently-running
  /// run early: POSTs /runs/{run_id}/pause, which rewrites the case's
  /// controlDict to stop cleanly and waits for ferrousFoam to actually exit
  /// -- see fluid's case_runner::pause_run, which can take up to a few
  /// minutes -- then polls status here until it's no longer `running`.
  /// Normally settles into `incomplete` (successfully, safely paused --
  /// see IncompleteRun.resumable), but returns as soon as the status is
  /// anything other than `running` (also covering the rare race where the
  /// solve finishes on its own right as the pause request lands, or fails).
  ///
  /// This poll is independent of (and deliberately redundant with) whatever
  /// runWeld/resumeRun/restartRun poll is already in flight for this run_id
  /// -- that poll's own [_pollUntilDone] also treats `incomplete` as
  /// terminal now, and is what actually flips a caller's "running"/result
  /// state; this method exists so a caller can await the pause action
  /// itself (e.g. to know when it's safe to re-enable a "Pause" button)
  /// without depending on that other poll's callback timing.
  Future<void> pauseRun(
    String runId, {
    void Function(RunStatusUpdate progress)? onProgress,
    Duration pollInterval = const Duration(milliseconds: 750),
    // Mirrors case_runner::pause_run's own generous (few-minutes) timeout
    // plus slack for the HTTP round trip/poll cadence -- pausing should
    // normally be much faster than a full solve, so this is intentionally
    // much shorter than runWeld's 3-hour safety backstop.
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final resp = await _client.post(baseUri.resolve('/runs/$runId/pause'));
    if (resp.statusCode != 200) {
      throw WeldServiceException('Failed to pause run $runId: HTTP ${resp.statusCode} ${resp.body}');
    }
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw WeldServiceException('Pausing run $runId timed out after $timeout');
      }
      final statusResp = await _client.get(baseUri.resolve('/runs/$runId'));
      if (statusResp.statusCode != 200) {
        throw WeldServiceException('Failed to poll run $runId while pausing: HTTP ${statusResp.statusCode}');
      }
      final update = RunStatusUpdate.fromJson(jsonDecode(statusResp.body) as Map<String, dynamic>);
      onProgress?.call(update);
      if (update.status != 'running') return;
      await Future.delayed(pollInterval);
    }
  }

  /// Shared status-poll-until-done/failed loop backing [runWeld],
  /// [resumeRun], and [restartRun] -- they only differ in how the run_id
  /// they poll came to exist. Also treats a transition to `incomplete` as
  /// terminal (alongside `done`), fetching whatever heightmap snapshot is
  /// currently available exactly like a finished result -- this is what
  /// lets an in-flight run/resume/restart poll unwind cleanly (back to
  /// "not running") the moment a concurrent Pause request (see [pauseRun])
  /// takes effect.
  ///
  /// Deliberately has no wall-clock timeout: a full-length weld is expected
  /// to take many hours (observed ~12.5h for a real run at the current
  /// weld_duration_ms range), and an arbitrary real-world-hours ceiling
  /// only serves to lose track of a run that's still genuinely progressing
  /// -- see the "Past welds" dropdown incident this replaced a 3-hour
  /// timeout over. The real, meaningful bound on how long this polls is
  /// already the run itself: ferrousFoam stops on its own once it reaches
  /// its target simulated end_time_s (driven by weld_duration_ms and, via
  /// travel_speed, how far the arc has actually traveled) -- i.e. the run
  /// is capped by distance/duration of the weld itself, not by how long a
  /// human has been waiting. If a run is truly stuck forever (not just
  /// slow), the stage timeline/solve-progress callbacks -- or, after an app
  /// restart, GET /runs -- are what surface that, not a client-side clock.
  Future<Heightmap> _pollUntilDone(
    String runId, {
    void Function(RunStatusUpdate progress)? onProgress,
    Duration pollInterval = const Duration(milliseconds: 750),
  }) async {
    while (true) {
      final statusResp = await _client.get(baseUri.resolve('/runs/$runId'));
      if (statusResp.statusCode != 200) {
        throw WeldServiceException(
            'Failed to poll run $runId: HTTP ${statusResp.statusCode}');
      }
      final update = RunStatusUpdate.fromJson(jsonDecode(statusResp.body) as Map<String, dynamic>);
      onProgress?.call(update);

      if (update.status == 'done' || update.status == 'incomplete') {
        final resultResp = await _client.get(baseUri.resolve('/runs/$runId/heightmap'));
        if (resultResp.statusCode != 200) {
          throw WeldServiceException(
              'Failed to fetch result for run $runId: HTTP ${resultResp.statusCode}');
        }
        return Heightmap.fromJsonString(resultResp.body);
      } else if (update.status == 'failed') {
        throw WeldServiceException('Run $runId failed: ${update.error ?? 'unknown error'}');
      }

      await Future.delayed(pollInterval);
    }
  }

  /// Fetches every run weld_service has ever staged (see GET /runs), found
  /// by scanning its runs/ directory directly rather than relying on
  /// in-memory state -- covers runs from before the current weld_service
  /// process even started. Backs the "past welds" dropdown (see main.dart).
  /// Newest-first, as the server already sorts it.
  Future<List<RunHistoryEntry>> fetchRunHistory() async {
    final resp = await _client.get(baseUri.resolve('/runs'));
    if (resp.statusCode != 200) {
      throw WeldServiceException('Failed to fetch run history: HTTP ${resp.statusCode} ${resp.body}');
    }
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => RunHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetches every run currently left `incomplete` on weld_service (see GET
  /// /runs/incomplete) -- surfaced once at startup so the user can choose to
  /// resume or restart each one (see main.dart's _StartupGate).
  Future<List<IncompleteRun>> fetchIncompleteRuns() async {
    final resp = await _client.get(baseUri.resolve('/runs/incomplete'));
    if (resp.statusCode != 200) {
      throw WeldServiceException('Failed to fetch incomplete runs: HTTP ${resp.statusCode} ${resp.body}');
    }
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => IncompleteRun.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// A single best-effort fetch of whatever heightmap (final or live
  /// mid-solve snapshot, see Heightmap.complete) is currently available for
  /// [runId], or null if none exists yet (still staging/meshing) or the
  /// request otherwise fails -- meant to be called on its own timer
  /// alongside the status poll while a run is in progress (see main.dart),
  /// not to throw and interrupt that polling over a transient hiccup.
  Future<Heightmap?> fetchHeightmapIfAvailable(String runId) async {
    try {
      final resp = await _client.get(baseUri.resolve('/runs/$runId/heightmap'));
      if (resp.statusCode != 200) return null;
      return Heightmap.fromJsonString(resp.body);
    } catch (_) {
      return null;
    }
  }

  /// Fetches the real empty-groove scan, rasterized by weld_service from
  /// the source PLY point cloud (see fluid's src/bin/weld_service/reference.rs).
  Future<Heightmap> fetchEmptyGrooveReference() => _fetchReference('/reference/empty-groove');

  /// Fetches the real post-tack-weld scan (ground truth), same source.
  Future<Heightmap> fetchWeldedGrooveReference() => _fetchReference('/reference/welded-groove');

  Future<Heightmap> _fetchReference(String path) async {
    final resp = await _client.get(baseUri.resolve(path));
    if (resp.statusCode != 200) {
      throw WeldServiceException('Failed to fetch $path: HTTP ${resp.statusCode} ${resp.body}');
    }
    return Heightmap.fromJsonString(resp.body);
  }

  void dispose() => _client.close();
}
