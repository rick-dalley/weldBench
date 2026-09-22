import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/main.dart';
import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/services/fast_service_launcher.dart';
import 'package:weld_bench/services/service_launcher.dart';
import 'package:weld_bench/services/weld_fast_service.dart';
import 'package:weld_bench/services/weld_service.dart';

Heightmap _syntheticHeightmap() {
  return Heightmap(
    xMm: [0, 1, 2],
    yMm: [0, 1, 2],
    zMm: [
      [10, 11, 12],
      [11, 12, 13],
      [12, 13, 14],
    ],
  );
}

void main() {
  testWidgets('renders the weld bench shell with a Weld button', (WidgetTester tester) async {
    // WeldBenchHome directly (bypassing WeldBenchApp's _StartupGate, which
    // needs a live weld_service) with synthetic reference data, since this
    // test is about the widget tree rendering correctly, not live data.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: WeldBenchHome(
            launcher: ServiceLauncher(),
            weldService: WeldService(),
            fastLauncher: FastServiceLauncher(),
            fastWeldService: WeldFastService(),
            emptyGroove: _syntheticHeightmap(),
            weldedGroove: _syntheticHeightmap(),
          ),
        ),
      );
      // initState fires a real (but usually fast-failing, if unavailable)
      // weld_fast_service request; give it a moment to settle instead of
      // leaving a pending future/timer at teardown -- runAsync + a bounded
      // wait, not pumpAndSettle (see render_preview.dart's comment on why).
      await Future.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    expect(find.text('weldBench'), findsOneWidget);
    expect(find.text('Weld'), findsOneWidget);
    expect(find.text('Voltage'), findsOneWidget);
  });
}
