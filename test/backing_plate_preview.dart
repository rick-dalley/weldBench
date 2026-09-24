// Visual check for the root-gap/backing-plate 3D rendering fix, against
// REAL profilometer scan data (not synthetic), fetched fresh from a live
// weld_service and saved to a fixed path so this test doesn't need network
// access (flutter_test blocks real HTTP calls anyway).
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/widgets/point_cloud_view.dart';

const _emptyDataPath =
    '/tmp/claude-1000/-home-rick-Code-physics/c7400b2b-8608-47d0-ae45-3b490f44a1d7/scratchpad/real_empty_groove_fresh.json';
const _weldedDataPath =
    '/tmp/claude-1000/-home-rick-Code-physics/c7400b2b-8608-47d0-ae45-3b490f44a1d7/scratchpad/real_welded_groove_repositioned.json';

Future<void> _renderAt(
  WidgetTester tester,
  String label,
  bool showBackingPlate,
  String outPath, {
  String dataPath = _emptyDataPath,
}) async {
  final hm = Heightmap.fromJsonString(File(dataPath).readAsStringSync());
  await tester.pumpWidget(
    RepaintBoundary(
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: PointCloudView(
              key: ValueKey(label),
              title: label,
              heightmap: hm,
              // A typical 3/4 orbit angle (the widget's own default) rather
              // than near-edge-on, so the whole shape -- including the wide
              // backing plate -- fits in frame and its geometry (not just
              // its color) is actually visible.
              initialAzimuth: -0.6,
              initialElevation: 0.65,
              showBackingPlate: showBackingPlate,
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
  testWidgets('preview: real empty-groove scan, with and without backing plate', (tester) async {
    tester.view.physicalSize = const Size(700, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await _renderAt(tester, 'Before fix', false, '/tmp/weldbench_backing_plate_before.png');
      await _renderAt(tester, 'After fix', true, '/tmp/weldbench_backing_plate_after.png');
    });
  });

  testWidgets('preview: real welded scan, repositioned window, with the depth gate', (tester) async {
    tester.view.physicalSize = const Size(700, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await _renderAt(
        tester,
        'Welded, backing plate on',
        true,
        '/tmp/weldbench_backing_plate_welded.png',
        dataPath: _weldedDataPath,
      );
      await _renderAt(
        tester,
        'Welded, backing plate off',
        false,
        '/tmp/weldbench_backing_plate_welded_off.png',
        dataPath: _weldedDataPath,
      );
    });
  });
}
