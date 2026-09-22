import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/heightmap.dart';
import '../models/weld_parameters.dart';

/// Client for weld_fast_service -- Novarc's internal `weld_sim` real-time
/// GMAW geometry math (vendored into fluid/src/bin/weld_fast_service, see
/// that binary's NOTICE.md for provenance), exposed over HTTP as a
/// microsecond-scale prediction, in contrast to WeldService's runWeld
/// (multi-hour CFD, start + poll).
///
/// API contract (local HTTP/JSON, default http://localhost:8788):
///   POST /predict   body: WeldParameters.toJson() (same shape WeldService
///                    posts to /runs -- weld_fast_service's PredictRequest
///                    mirrors weld_service's RunRequest field-for-field)
///                    -> { heightmap, outputs, findings }
///
/// This is a single request/response round trip, not a polled run -- meant
/// to be called again on every slider change (debounced by the caller; see
/// main.dart) for a live 4th comparison panel.
class WeldFastServiceException implements Exception {
  final String message;
  WeldFastServiceException(this.message);
  @override
  String toString() => 'WeldFastServiceException: $message';
}

class FastPredictOutputs {
  final double currentA;
  final double heatInputJMm;
  final double penetrationMm;
  final double beadWidthMm;
  final double fillRatio;
  final double wettingAngleDeg;

  FastPredictOutputs({
    required this.currentA,
    required this.heatInputJMm,
    required this.penetrationMm,
    required this.beadWidthMm,
    required this.fillRatio,
    required this.wettingAngleDeg,
  });

  factory FastPredictOutputs.fromJson(Map<String, dynamic> json) => FastPredictOutputs(
        currentA: (json['current_a'] as num).toDouble(),
        heatInputJMm: (json['heat_input_j_mm'] as num).toDouble(),
        penetrationMm: (json['penetration_mm'] as num).toDouble(),
        beadWidthMm: (json['bead_width_mm'] as num).toDouble(),
        fillRatio: (json['fill_ratio'] as num).toDouble(),
        wettingAngleDeg: (json['wetting_angle_deg'] as num).toDouble(),
      );
}

class FastFinding {
  final String parameter;
  final String severity; // "warning" | "critical"
  final String message;

  FastFinding({required this.parameter, required this.severity, required this.message});

  factory FastFinding.fromJson(Map<String, dynamic> json) => FastFinding(
        parameter: json['parameter'] as String,
        severity: json['severity'] as String,
        message: json['message'] as String,
      );
}

class FastPredictResult {
  final Heightmap heightmap;
  final FastPredictOutputs outputs;
  final List<FastFinding> findings;

  FastPredictResult({required this.heightmap, required this.outputs, required this.findings});
}

class WeldFastService {
  final Uri baseUri;
  final http.Client _client;

  WeldFastService({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? Uri.parse('http://localhost:8788'),
        _client = client ?? http.Client();

  Future<FastPredictResult> predict(WeldParameters params) async {
    final resp = await _client
        .post(
          baseUri.resolve('/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(params.toJson()),
        )
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw WeldFastServiceException('POST /predict failed: HTTP ${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return FastPredictResult(
      heightmap: Heightmap.fromJson(json['heightmap'] as Map<String, dynamic>),
      outputs: FastPredictOutputs.fromJson(json['outputs'] as Map<String, dynamic>),
      findings:
          (json['findings'] as List).map((f) => FastFinding.fromJson(f as Map<String, dynamic>)).toList(),
    );
  }

  void dispose() => _client.close();
}
