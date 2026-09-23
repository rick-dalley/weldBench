import 'package:flutter/material.dart';

/// Shared between [HeightmapView] (2D top-down) and [PointCloudView] (3D
/// rotatable), so both render height the same way and the app-wide
/// Viridis/Grayscale toggle affects every panel consistently.
enum HeightmapColormap {
  viridis,
  grayscale;

  String get label => switch (this) {
        HeightmapColormap.viridis => 'Viridis',
        HeightmapColormap.grayscale => 'Grayscale',
      };
}

/// A handful of control points approximating the viridis colormap, so
/// heightmap panels here read consistently with the matplotlib previews
/// used to validate the underlying data.
const List<Color> _viridisStops = [
  Color(0xFF440154),
  Color(0xFF3B528B),
  Color(0xFF21908C),
  Color(0xFF5DC963),
  Color(0xFFFDE725),
];

Color _viridis(double t) {
  final tt = t.clamp(0.0, 1.0);
  final scaled = tt * (_viridisStops.length - 1);
  final i = scaled.floor().clamp(0, _viridisStops.length - 2);
  final frac = scaled - i;
  return Color.lerp(_viridisStops[i], _viridisStops[i + 1], frac)!;
}

// Dark grey (low/deep) to off-white (high/flat surface) -- not pure black
// or pure white at either end, so the very top and bottom of the range
// still read as distinct shades rather than clipping to a flat color.
const Color _grayscaleLow = Color(0xFF2A2A2A);
const Color _grayscaleHigh = Color(0xFFF5F3EE);

Color _grayscale(double t) => Color.lerp(_grayscaleLow, _grayscaleHigh, t.clamp(0.0, 1.0))!;

Color Function(double) colormapFunction(HeightmapColormap colormap) => switch (colormap) {
      HeightmapColormap.viridis => _viridis,
      HeightmapColormap.grayscale => _grayscale,
    };
