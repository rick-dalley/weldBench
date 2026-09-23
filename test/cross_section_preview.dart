// Visual check for CrossSectionView with synthetic data resembling the real
// empty-groove/welded-groove pair, so the depth-vs-X profile, the zero
// (surface) reference line, and the shared depth axis can actually be
// looked at before wiring the flyout into the live app.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/widgets/cross_section_view.dart';

const double _surface = 29.0;

Heightmap _grooveOnly() {
  const n = 80;
  final x = List.generate(n, (i) => i * (30.0 / (n - 1)));
  final y = [180.0, 200.0, 220.0];
  final z = List.generate(n, (xi) {
    final xv = x[xi];
    final grooveBase = _surface - 13.3 * (1 - ((xv - 15.0).abs() / 15.0).clamp(0, 1));
    return List.generate(3, (_) => grooveBase);
  });
  return Heightmap(xMm: x, yMm: y, zMm: z);
}

Heightmap _grooveWithBead() {
  const n = 80;
  final x = List.generate(n, (i) => i * (30.0 / (n - 1)));
  final y = [180.0, 200.0, 220.0];
  final z = List.generate(n, (xi) {
    final xv = x[xi];
    final grooveBase = _surface - 13.3 * (1 - ((xv - 15.0).abs() / 15.0).clamp(0, 1));
    // Bead fills the groove almost exactly flush at Y=200 (yi=1).
    return [
      grooveBase,
      (xv > 8 && xv < 22) ? _surface + 0.03 : grooveBase,
      grooveBase,
    ];
  });
  return Heightmap(xMm: x, yMm: y, zMm: z);
}

void main() {
  testWidgets('preview: cross-section view, empty vs welded at Y=200', (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: CrossSectionView(
                      title: 'Empty groove',
                      heightmap: _grooveOnly(),
                      surfaceReferenceMm: _surface,
                      ySliceMm: 200,
                      depthMinOverride: -1,
                      depthMaxOverride: 14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CrossSectionView(
                      title: 'Real weld (ground truth)',
                      heightmap: _grooveWithBead(),
                      surfaceReferenceMm: _surface,
                      ySliceMm: 200,
                      depthMinOverride: -1,
                      depthMaxOverride: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = tester.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/weldbench_cross_section_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
