import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/heightmap.dart';

/// A 2D depth-vs-X profile at a fixed Y ("slice"), referenced to the flat
/// plate surface rather than to the heightmap's raw absolute Z -- the same
/// convention used to read the real profilometer scans (the flat outer
/// plate renders as yellow/max-Z in the 2D view; treating that as zero lets
/// "how deep is the groove" / "how full is the bead" be read directly as a
/// number and a shape, rather than inferred from a color-to-number lookup.
class CrossSectionView extends StatelessWidget {
  final String title;
  final Heightmap? heightmap;
  final double surfaceReferenceMm;
  final double ySliceMm;
  final bool loading;
  final String? statusText;
  final double? depthMinOverride;
  final double? depthMaxOverride;

  const CrossSectionView({
    super.key,
    required this.title,
    required this.heightmap,
    required this.surfaceReferenceMm,
    required this.ySliceMm,
    this.loading = false,
    this.statusText,
    this.depthMinOverride,
    this.depthMaxOverride,
  });

  @override
  Widget build(BuildContext context) {
    final hm = heightmap;
    List<double>? xs;
    List<double>? depths;
    double? depthMin;
    double? depthMax;
    double? actualYMm;

    if (hm != null && hm.ny > 0 && hm.nx > 0) {
      var yi = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < hm.ny; i++) {
        final d = (hm.yMm[i] - ySliceMm).abs();
        if (d < bestDist) {
          bestDist = d;
          yi = i;
        }
      }
      actualYMm = hm.yMm[yi];
      xs = hm.xMm;
      depths = [for (var xi = 0; xi < hm.nx; xi++) surfaceReferenceMm - hm.zMm[xi][yi]];
      var lo = depthMinOverride ?? depths.reduce((a, b) => a < b ? a : b);
      var hi = depthMaxOverride ?? depths.reduce((a, b) => a > b ? a : b);
      // Always keep the surface line (depth = 0) in frame, even if this
      // particular panel's data happens to stay entirely above or below it.
      if (lo > 0) lo = 0;
      if (hi < 0) hi = 0;
      depthMin = lo;
      depthMax = hi;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
                child: (hm == null || xs == null || depths == null)
                    ? const Center(child: Text('No data'))
                    : CustomPaint(
                        painter: _CrossSectionPainter(
                          xs: xs,
                          depths: depths,
                          depthMin: depthMin!,
                          depthMax: depthMax!,
                        ),
                        child: Container(),
                      ),
              ),
              if (loading)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        if (statusText != null) ...[
                          const SizedBox(height: 8),
                          Text(statusText!, style: const TextStyle(color: Colors.white)),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hm != null && actualYMm != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Y = ${actualYMm.toStringAsFixed(1)} mm  ·  depth below surface: '
              '${depthMin!.toStringAsFixed(2)} to ${depthMax!.toStringAsFixed(2)} mm',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _CrossSectionPainter extends CustomPainter {
  final List<double> xs;
  final List<double> depths;
  final double depthMin;
  final double depthMax;

  _CrossSectionPainter({
    required this.xs,
    required this.depths,
    required this.depthMin,
    required this.depthMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 10.0;
    final plotRect = Rect.fromLTWH(margin, margin, size.width - 2 * margin, size.height - 2 * margin);
    final xMin = xs.first;
    final xMax = xs.last;
    final xRange = (xMax - xMin).abs() < 1e-9 ? 1.0 : (xMax - xMin);
    final depthRange = (depthMax - depthMin).abs() < 1e-9 ? 1.0 : (depthMax - depthMin);

    // Depth increases downward on screen -- surface at top, groove floor at
    // the bottom -- matching how a physical cross-section actually looks.
    Offset toScreen(double x, double depth) {
      final tx = (x - xMin) / xRange;
      final td = (depth - depthMin) / depthRange;
      return Offset(plotRect.left + tx * plotRect.width, plotRect.top + td * plotRect.height);
    }

    final zeroY = toScreen(xMin, 0).dy;
    _drawDashedLine(
      canvas,
      Offset(plotRect.left, zeroY),
      Offset(plotRect.right, zeroY),
      Paint()
        ..color = Colors.grey.shade500
        ..strokeWidth = 1,
    );

    final path = Path();
    for (var i = 0; i < xs.length; i++) {
      final p = toScreen(xs[i], depths[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.deepOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final direction = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final start = a + direction * covered;
      final end = a + direction * math.min(covered + dashWidth, total);
      canvas.drawLine(start, end, paint);
      covered += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _CrossSectionPainter oldDelegate) =>
      oldDelegate.xs != xs ||
      oldDelegate.depths != depths ||
      oldDelegate.depthMin != depthMin ||
      oldDelegate.depthMax != depthMax;
}
