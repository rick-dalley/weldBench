import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/heightmap.dart';
import '../models/weld_parameters.dart';

/// Client for the local Rust orchestration service that runs ferrousFoam and
/// returns the resulting puddle/bead heightmap.
///
/// API contract (local HTTP/JSON, default http://localhost:8787):
///   POST /runs                    body: WeldParameters.toJson()
///                                  -> {"run_id": "..."}
///   GET  /runs/{run_id}           -> {"status": "running"|"done"|"failed", "error": "..."?}
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
  /// heightmap. Calls [onStatus] with each observed status while polling.
  Future<Heightmap> runWeld(
    WeldParameters params, {
    void Function(String status)? onStatus,
    Duration pollInterval = const Duration(milliseconds: 750),
    Duration timeout = const Duration(minutes: 10),
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
      final statusJson = jsonDecode(statusResp.body) as Map<String, dynamic>;
      final status = statusJson['status'] as String;
      onStatus?.call(status);

      if (status == 'done') {
        final resultResp = await _client.get(baseUri.resolve('/runs/$runId/heightmap'));
        if (resultResp.statusCode != 200) {
          throw WeldServiceException(
              'Failed to fetch result for run $runId: HTTP ${resultResp.statusCode}');
        }
        return Heightmap.fromJsonString(resultResp.body);
      } else if (status == 'failed') {
        final err = statusJson['error'] as String? ?? 'unknown error';
        throw WeldServiceException('Run $runId failed: $err');
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
