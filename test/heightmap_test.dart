import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:weld_bench/models/heightmap.dart';

void main() {
  test('parses the bundled reference heightmaps', () {
    for (final name in ['reference_empty_groove', 'reference_welded_groove']) {
      final file = File('assets/reference/$name.json');
      expect(file.existsSync(), isTrue, reason: '$name.json should exist');
      final hm = Heightmap.fromJsonString(file.readAsStringSync());
      expect(hm.nx, greaterThan(0));
      expect(hm.ny, greaterThan(0));
      expect(hm.zMm.length, hm.nx);
      expect(hm.zMm.first.length, hm.ny);
      expect(hm.zMax, greaterThan(hm.zMin));
    }
  });
}
