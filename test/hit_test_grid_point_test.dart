import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:weld_bench/models/heightmap.dart';
import 'package:weld_bench/widgets/point_cloud_view.dart';

/// A flat 3x3 grid, so straight top-down (azimuth=0, elevation=0) projects
/// each grid point to a screen position solvable by hand -- see the
/// comments below for the exact numbers this locks in.
Heightmap _flatGrid() {
  return Heightmap(
    xMm: [0, 10, 20],
    yMm: [0, 10, 20],
    zMm: [
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0],
    ],
  );
}

void main() {
  group('hitTestGridPoint', () {
    final hm = _flatGrid();
    const size = Size(300, 300);

    test('exact tap on the center grid point resolves to it', () {
      // xMid=yMid=10, baseScale=0.1 -> center point (x=10,y=10) projects to
      // screen (150, 150) exactly (centerX/centerY with no offset).
      final hit = hitTestGridPoint(
        heightmap: hm,
        zMin: 0,
        zMax: 0,
        azimuth: 0,
        elevation: 0,
        zExaggeration: 3.0,
        size: size,
        tapPosition: const Offset(150, 150),
      );
      expect(hit, isNotNull);
      expect(hit!.xi, 1);
      expect(hit.yi, 1);
    });

    test('exact tap on a corner grid point resolves to it', () {
      // (x=0,y=0) -> cx=cy=-1 -> screen (150-126, 150+126) = (24, 276).
      final hit = hitTestGridPoint(
        heightmap: hm,
        zMin: 0,
        zMax: 0,
        azimuth: 0,
        elevation: 0,
        zExaggeration: 3.0,
        size: size,
        tapPosition: const Offset(24, 276),
      );
      expect(hit, isNotNull);
      expect(hit!.xi, 0);
      expect(hit.yi, 0);
    });

    test('a tap slightly off a grid point still resolves to it (tolerance)', () {
      final hit = hitTestGridPoint(
        heightmap: hm,
        zMin: 0,
        zMax: 0,
        azimuth: 0,
        elevation: 0,
        zExaggeration: 3.0,
        size: size,
        tapPosition: const Offset(155, 145),
      );
      expect(hit, isNotNull);
      expect(hit!.xi, 1);
      expect(hit.yi, 1);
    });

    test('a tap far from every grid point resolves to nothing', () {
      final hit = hitTestGridPoint(
        heightmap: hm,
        zMin: 0,
        zMax: 0,
        azimuth: 0,
        elevation: 0,
        zExaggeration: 3.0,
        size: size,
        tapPosition: const Offset(0, 0),
      );
      expect(hit, isNull);
    });

    test('an empty heightmap resolves to nothing', () {
      final empty = Heightmap(xMm: const [], yMm: const [], zMm: const []);
      final hit = hitTestGridPoint(
        heightmap: empty,
        zMin: 0,
        zMax: 0,
        azimuth: 0,
        elevation: 0,
        zExaggeration: 3.0,
        size: size,
        tapPosition: const Offset(150, 150),
      );
      expect(hit, isNull);
    });
  });
}
