import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:weld_bench/widgets/point_cloud_view.dart';

void main() {
  group('rotateAndProject', () {
    test('identity (azimuth=0, elevation=0) is a pure top-down passthrough', () {
      final r = rotateAndProject(1.0, 2.0, 3.0, azimuth: 0, elevation: 0);
      expect(r.x, closeTo(1.0, 1e-9));
      expect(r.y, closeTo(2.0, 1e-9));
      expect(r.depth, closeTo(3.0, 1e-9));
    });

    test('azimuth=pi/2 rotates the horizontal plane by 90 degrees', () {
      final r = rotateAndProject(1.0, 0.0, 0.0, azimuth: math.pi / 2, elevation: 0);
      expect(r.x, closeTo(0.0, 1e-9));
      expect(r.y, closeTo(1.0, 1e-9));
    });

    test('elevation=pi/2 (edge-on) turns height into screen-Y and Y-position into depth', () {
      // A point directly "north" in the horizontal plane (cy=1) with some
      // height (cz=1): edge-on, height should dominate screen Y, and the
      // horizontal Y-position should become depth (how far into the screen).
      final r = rotateAndProject(0.0, 1.0, 1.0, azimuth: 0, elevation: math.pi / 2);
      expect(r.y, closeTo(-1.0, 1e-9)); // -cz, since y2 = y1*cosEl - cz*sinEl = 0 - 1*1
      expect(r.depth, closeTo(1.0, 1e-9)); // z2 = y1*sinEl + cz*cosEl = 1*1 + 0
    });

    test('different azimuth/elevation actually produce different output (regression guard)', () {
      // This is the exact bug this test exists to catch: an earlier version
      // of the widget appeared to render identically regardless of the
      // rotation angles passed in (caught by comparing rendered PNGs before
      // committing, not by a unit test -- this locks that catch in).
      const cx = 0.6, cy = -0.3, cz = 0.4;
      final a = rotateAndProject(cx, cy, cz, azimuth: -0.5, elevation: 0.5);
      final b = rotateAndProject(cx, cy, cz, azimuth: 0.0, elevation: 0.0);
      final different = (a.x - b.x).abs() > 1e-6 || (a.y - b.y).abs() > 1e-6 || (a.depth - b.depth).abs() > 1e-6;
      expect(different, isTrue, reason: 'rotation angles must actually change the projected point');
    });

    test('rotation preserves distance from the origin (orthonormal transform)', () {
      const cx = 0.7, cy = -0.4, cz = 0.9;
      final originalDist = math.sqrt(cx * cx + cy * cy + cz * cz);
      final r = rotateAndProject(cx, cy, cz, azimuth: 1.234, elevation: -0.789);
      final rotatedDist = math.sqrt(r.x * r.x + r.y * r.y + r.depth * r.depth);
      expect(rotatedDist, closeTo(originalDist, 1e-9));
    });
  });
}
