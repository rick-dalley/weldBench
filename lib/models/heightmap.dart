import 'dart:convert';

/// A regular-grid heightmap: z(x, y) in millimeters.
///
/// This is the common interchange format across the three sources compared
/// in this app: real profilometer scans (rasterized from point clouds),
/// and ferrousFoam's simulated free-surface (alpha1 = 0.5 isosurface,
/// extracted onto the same grid).
class Heightmap {
  final List<double> xMm;
  final List<double> yMm;
  final List<List<double>> zMm; // zMm[xi][yi]

  Heightmap({required this.xMm, required this.yMm, required this.zMm});

  int get nx => xMm.length;
  int get ny => yMm.length;

  double get xMin => xMm.first;
  double get xMax => xMm.last;
  double get yMin => yMm.first;
  double get yMax => yMm.last;

  double get zMin {
    var m = double.infinity;
    for (final row in zMm) {
      for (final v in row) {
        if (v < m) m = v;
      }
    }
    return m;
  }

  double get zMax {
    var m = -double.infinity;
    for (final row in zMm) {
      for (final v in row) {
        if (v > m) m = v;
      }
    }
    return m;
  }

  factory Heightmap.fromJson(Map<String, dynamic> json) {
    return Heightmap(
      xMm: (json['x_mm'] as List).map((e) => (e as num).toDouble()).toList(),
      yMm: (json['y_mm'] as List).map((e) => (e as num).toDouble()).toList(),
      zMm: (json['z_mm'] as List)
          .map((row) => (row as List).map((e) => (e as num).toDouble()).toList())
          .toList(),
    );
  }

  static Heightmap fromJsonString(String s) =>
      Heightmap.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
