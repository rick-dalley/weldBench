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
///                                    bundled reference assets)
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
  /// heightmap. Calls [onProgress] with each observed status (including the
  /// stage timeline and live solve progress) while polling.
  Future<Heightmap> runWeld(
    WeldParameters params, {
    void Function(RunStatusUpdate progress)? onProgress,
    Duration pollInterval = const Duration(milliseconds: 750),
    // At the current RealGrooveCase mesh resolution, a full-length (250ms)
    // weld takes on the order of 35-40 minutes wall-clock, and the
    // weld_duration_ms lever goes up to 1000ms (~4x that). 3 hours gives
    // generous headroom without being effectively unbounded; this is a
    // safety backstop, not an expected wait -- the stage timeline is what
    // tells you how it's actually progressing.
    Duration timeout = const Duration(hours: 3),
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

    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw WeldServiceException('Run $runId timed out after $timeout');
      }
      final statusResp = await _client.get(baseUri.resolve('/runs/$runId'));
      if (statusResp.statusCode != 200) {
        throw WeldServiceException(
            'Failed to poll run $runId: HTTP ${statusResp.statusCode}');
      }
      final update = RunStatusUpdate.fromJson(jsonDecode(statusResp.body) as Map<String, dynamic>);
      onProgress?.call(update);

      if (update.status == 'done') {
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
