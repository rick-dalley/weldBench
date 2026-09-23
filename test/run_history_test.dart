import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:weld_bench/models/run_progress.dart';

void main() {
  group('RunHistoryEntry.fromJson', () {
    test('parses a done run (real weld_service GET /runs response shape)', () {
      // Captured verbatim from a real GET /runs response against actual
      // completed run directories, not a guessed shape.
      const json = '''
      {
        "run_id": "11d2a765-8479-4412-90fb-d619f47823d9",
        "started_at_s": 1790129003.1272588,
        "status": "done",
        "latest_time_s": null,
        "end_time_s": null,
        "request": null,
        "has_heightmap": true
      }
      ''';
      final entry = RunHistoryEntry.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(entry.runId, '11d2a765-8479-4412-90fb-d619f47823d9');
      expect(entry.status, RunHistoryStatus.done);
      expect(entry.hasHeightmap, isTrue);
      expect(entry.latestTimeS, isNull);
      expect(entry.request, isNull);
      expect(entry.startedAt, isNotNull);
    });

    test('parses an incomplete_not_resumable run with live progress fields', () {
      const json = '''
      {
        "run_id": "e4804071-b83d-4c45-b62b-4ff7f8089e44",
        "started_at_s": 1790129052.6141632,
        "status": "incomplete_not_resumable",
        "latest_time_s": 0.03507076198,
        "end_time_s": 0.15,
        "request": null,
        "has_heightmap": false
      }
      ''';
      final entry = RunHistoryEntry.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(entry.status, RunHistoryStatus.incompleteNotResumable);
      expect(entry.hasHeightmap, isFalse);
      expect(entry.latestTimeS, closeTo(0.03507076198, 1e-9));
      expect(entry.endTimeS, closeTo(0.15, 1e-9));
    });

    test('startedAt converts started_at_s (unix seconds) to a real DateTime', () {
      final entry = RunHistoryEntry.fromJson({
        'run_id': 'x',
        'started_at_s': 1790129003.1272588,
        'status': 'done',
        'has_heightmap': true,
      });
      final dt = entry.startedAt!;
      // 1790129003 unix seconds -> a real, sane calendar date (not 1970, not
      // some garbage far-future value) -- the actual conversion correctness
      // (exact calendar date) isn't asserted since that's timezone-relative,
      // but this guards against a unit mixup (e.g. forgetting to convert
      // seconds to milliseconds), which would land wildly off from "now".
      expect(dt.year, greaterThan(2020));
      expect(dt.year, lessThan(2100));
    });

    test('an unrecognized status string falls back to incompleteNotResumable, not a crash', () {
      final entry = RunHistoryEntry.fromJson({
        'run_id': 'x',
        'status': 'some_future_status_this_client_does_not_know_about',
        'has_heightmap': false,
      });
      expect(entry.status, RunHistoryStatus.incompleteNotResumable);
    });
  });
}
