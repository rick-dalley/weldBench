import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/models/run_progress.dart';
import 'package:weld_bench/widgets/heightmap_view.dart';
import 'package:weld_bench/widgets/stage_timeline.dart';

Heightmap _syntheticGroove() {
  const n = 60;
  final x = List.generate(n, (i) => i * 0.5);
  final y = List.generate(n, (i) => i * 0.5);
  final z = List.generate(n, (xi) {
    final xv = x[xi];
    final base = 28.0 - 12.0 * (1 - ((xv - 15).abs() / 15).clamp(0, 1));
    return List.generate(n, (yi) => base);
  });
  return Heightmap(xMm: x, yMm: y, zMm: z);
}

void main() {
  testWidgets('preview: stage timeline (mid-run) + grayscale colormap', (tester) async {
    tester.view.physicalSize = const Size(1400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final nowS = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final stages = [
      StageRecord(name: 'staging', startedAtS: nowS - 130, endedAtS: nowS - 129.7),
      StageRecord(name: 'meshing', startedAtS: nowS - 129.7, endedAtS: nowS - 125),
      StageRecord(name: 'initializing', startedAtS: nowS - 125, endedAtS: nowS - 124.4),
      StageRecord(name: 'solving', startedAtS: nowS - 124.4, endedAtS: null),
    ];
    const solveProgress = SolveProgress(simulatedTimeS: 0.0623, endTimeS: 0.25, fraction: 0.249);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  StageTimeline(stages: stages, solveProgress: solveProgress),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: HeightmapView(
                              title: 'Viridis (default)',
                              heightmap: _syntheticGroove(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: HeightmapView(
                              title: 'Grayscale',
                              heightmap: _syntheticGroove(),
                              colormap: HeightmapColormap.grayscale,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
      File('/tmp/weldbench_new_ui_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
