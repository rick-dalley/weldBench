// Visual check for PointCloudView: renders the same synthetic V-groove-with-
// bead heightmap at three fixed angles (top-down, default 3/4, near edge-on)
// via the initialAzimuth/initialElevation constructor params, so the
// rotation/projection math can actually be looked at rather than relying on
// a simulated drag gesture (which turned out unreliable in this test
// harness -- two renders before/after a simulated drag came back pixel-
// identical, so this tests the math directly instead).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/widgets/point_cloud_view.dart';

Heightmap _syntheticGrooveWithBead() {
  const n = 120;
  final x = List.generate(n, (i) => i * (29.78 / (n - 1)));
  final y = List.generate(n, (i) => 185.0 + i * (30.0 / (n - 1)));
  final z = List.generate(n, (xi) {
    final xv = x[xi];
    // V-groove: high (29mm) at edges, down to a ~15mm floor in the middle.
    final grooveBase = 29.0 - 14.0 * (1 - ((xv - 14.9).abs() / 14.9).clamp(0, 1));
    return List.generate(n, (yi) {
      final yv = y[yi];
      // A bead bump in the middle third of the seam, tapering at the ends.
      final alongSeam = (yv - 185.0) / 30.0; // 0..1
      final taper = (alongSeam > 0.3 && alongSeam < 0.7) ? 1.0 : 0.0;
      final bump = (xv > 11 && xv < 19) ? 3.0 * taper : 0.0;
      return grooveBase + bump;
    });
  });
  return Heightmap(xMm: x, yMm: y, zMm: z);
}

Future<void> _renderAngle(WidgetTester tester, String label, double azimuth, double elevation, String outPath) async {
  final hm = _syntheticGrooveWithBead();
  await tester.pumpWidget(
    RepaintBoundary(
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            // Unique key per angle: without this, Flutter reuses the same
            // State across these back-to-back pumpWidget calls (same widget
            // type/tree position each time), and since rotation state is
            // deliberately "late-initialized once, then user-owned" (so a
            // real user's drag persists across unrelated rebuilds), reusing
            // state here would freeze every render at the *first* call's
            // angles -- exactly the bug this comment is warning about.
            child: PointCloudView(
              key: ValueKey(label),
              title: label,
              heightmap: hm,
              initialAzimuth: azimuth,
              initialElevation: elevation,
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await Future.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
  final boundary = tester.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(outPath).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('preview: point cloud at top-down, 3/4, and near edge-on angles', (tester) async {
    tester.view.physicalSize = const Size(700, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await _renderAngle(tester, 'Top-down (elevation=0)', 0.0, 0.0, '/tmp/weldbench_pointcloud_topdown.png');
      await _renderAngle(tester, 'Default 3/4 view', -0.5, 0.5, '/tmp/weldbench_pointcloud_default.png');
      await _renderAngle(
        tester,
        'Near edge-on (cross-section)',
        0.0,
        math.pi / 2 - 0.15,
        '/tmp/weldbench_pointcloud_edgeon.png',
      );
    });
  });
}
