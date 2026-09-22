import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/main.dart';

void main() {
  testWidgets('renders the weld bench shell with a Weld button', (WidgetTester tester) async {
    await tester.pumpWidget(const WeldBenchApp());
    await tester.pump();

    expect(find.text('weldBench'), findsOneWidget);
    expect(find.text('Weld'), findsOneWidget);
    expect(find.text('Voltage'), findsOneWidget);
  });
}
