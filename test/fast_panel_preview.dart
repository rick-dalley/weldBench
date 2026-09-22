// Visual check for the 4th ("Fast model") panel with realistic synthetic
// data, entirely independent of a real network call: `flutter_test` always
// installs a mock `HttpOverrides` (see `HttpOverrides.current` inside any
// `testWidgets` body), so a real POST to weld_fast_service can never
// succeed from inside a widget test -- that's Flutter's own test-hermeticity
// feature, not a bug here (verified separately: a plain `dart run` script
// hitting the real running weld_fast_service works fine, see this task's
// write-up). This preview instead constructs `FastPredictOutputs` /
// `FastFinding` / `Heightmap` directly (plain Dart objects, no I/O) with
// numbers matching a real /predict response, to check the panel's layout,
// colors, and stats/findings text render correctly.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/main.dart';
import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/services/weld_fast_service.dart';
import 'package:weld_bench/widgets/heightmap_view.dart';

Heightmap _syntheticFastPrediction() {
  // Mimics the real weld_fast_service response shape (bare groove + a
  // raised bead running down the middle third of the seam window).
  const n = 60;
  final x = List.generate(n, (i) => i * 0.5); // 0..29.5mm, like the real X window
  final y = List.generate(n, (i) => 185.0 + i * 0.5); // 185..214.5mm, like the real Y window
  final z = List.generate(n, (xi) {
    final xv = x[xi];
    final grooveFloor = 28.9 - 13.1 * (1 - ((xv - 14.9).abs() / 9.9).clamp(0, 1));
    return List.generate(n, (yi) {
      final yv = y[yi];
      final onSeam = yv > 191 && yv < 209 && (xv - 14.9).abs() < 3.5;
      return onSeam ? grooveFloor + 4.0 : grooveFloor;
    });
  });
  return Heightmap(xMm: x, yMm: y, zMm: z);
}

void main() {
  testWidgets('preview: fast-model panel with realistic synthetic data', (tester) async {
    tester.view.physicalSize = const Size(500, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final outputs = FastPredictOutputs(
      currentA: 187.3,
      heatInputJMm: 618.4,
      penetrationMm: 5.2,
      beadWidthMm: 7.9,
      fillRatio: 1.04,
      wettingAngleDeg: 29.6,
    );
    final findings = [
      FastFinding(
        parameter: 'penetration_mm',
        severity: 'warning',
        message: 'Estimated penetration (5.2mm) exceeds the 1.5mm root face -- proud but stable reinforcement expected.',
      ),
    ];

    await tester.runAsync(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: FastModelPanel(
                  heightmap: _syntheticFastPrediction(),
                  outputs: outputs,
                  findings: findings,
                  error: null,
                  colormap: HeightmapColormap.viridis,
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }

      final boundary = tester.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/weldbench_fast_panel_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
