import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weld_bench/main.dart';

void main() {
  testWidgets('render a PNG preview of the full app for visual review', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(const RepaintBoundary(child: WeldBenchApp()));
      // Asset loading (rootBundle.loadString) and ui.decodeImageFromPixels
      // both use real platform callbacks that need runAsync to resolve
      // inside a widget test; pump a bounded number of times rather than
      // pumpAndSettle (which can hang waiting on something that never
      // truly quiesces).
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
