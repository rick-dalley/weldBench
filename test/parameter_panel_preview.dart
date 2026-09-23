// Visual check for ParameterPanel's new "Previous welds" dropdown at the
// top of the form.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/models/run_progress.dart';
import 'package:weld_bench/models/weld_parameters.dart';
import 'package:weld_bench/widgets/parameter_panel.dart';

void main() {
  testWidgets('preview: ParameterPanel with a Previous welds dropdown', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final history = [
      RunHistoryEntry(
        runId: 'a',
        startedAtS: DateTime(2026, 9, 23, 6, 36).millisecondsSinceEpoch / 1000.0,
        status: RunHistoryStatus.done,
        hasHeightmap: true,
      ),
      RunHistoryEntry(
        runId: 'b',
        startedAtS: DateTime(2026, 9, 22, 19, 3).millisecondsSinceEpoch / 1000.0,
        status: RunHistoryStatus.incompleteNotResumable,
        hasHeightmap: false,
      ),
    ];

    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          home: Scaffold(
            body: ParameterPanel(
              params: WeldParameters(),
              onChanged: () {},
              previousWelds: history,
              onSelectPreviousWeld: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = tester.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/weldbench_parameter_panel_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
