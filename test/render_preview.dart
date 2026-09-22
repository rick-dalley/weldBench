import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/main.dart';
import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/services/service_launcher.dart';
import 'package:weld_bench/services/weld_service.dart';

// A small synthetic V-groove-like heightmap: high plate surface at the
// edges, dipping to a lower "groove floor" in the middle. Real fidelity is
// already validated separately (against the live weld_service endpoints);
// this is purely for a visual sanity check of the widget rendering.
Heightmap _syntheticGroove({double bump = 0}) {
  const n = 60;
  final x = List.generate(n, (i) => i * 0.5);
  final y = List.generate(n, (i) => i * 0.5);
  final z = List.generate(n, (xi) {
    final xv = x[xi];
    final base = 28.0 - 12.0 * (1 - ((xv - 15).abs() / 15).clamp(0, 1));
    return List.generate(n, (yi) => base + (bump > 0 && xv > 12 && xv < 18 ? bump : 0));
  });
  return Heightmap(xMm: x, yMm: y, zMm: z);
}

void main() {
  testWidgets('render a PNG preview of the full app shell for visual review', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        RepaintBoundary(
          child: MaterialApp(
            home: WeldBenchHome(
              launcher: ServiceLauncher(),
              weldService: WeldService(),
              emptyGroove: _syntheticGroove(),
              weldedGroove: _syntheticGroove(bump: 3),
            ),
          ),
        ),
      );
      // ui.decodeImageFromPixels uses a real platform callback that needs
      // runAsync to resolve inside a widget test; pump a bounded number of
      // times rather than pumpAndSettle (which can hang indefinitely).
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }

      final boundary = tester.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/weldbench_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
