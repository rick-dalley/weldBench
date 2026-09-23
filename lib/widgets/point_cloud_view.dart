import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/heightmap.dart';
import 'colormap.dart';
import 'heightmap_view.dart';

/// Whether a panel shows the flat top-down color map or the rotatable 3D
/// view -- one global toggle affects all panels (see main.dart), so the
/// same weld is always compared the same way across all 4 columns.
enum ViewMode {
  flat,
  rotatable;

  String get label => switch (this) {
        ViewMode.flat => '2D',
        ViewMode.rotatable => '3D',
      };
}

/// Switches between [HeightmapView] and [PointCloudView] for one panel,
/// so call sites don't each need their own if/else -- add a new view mode
/// in one place if a third ever shows up.
class AdaptiveHeightmapView extends StatelessWidget {
  final String title;
  final Heightmap? heightmap;
  final HeightmapColormap colormap;
  final ViewMode viewMode;
  final bool loading;
  final String? statusText;
  final double? zMinOverride;
  final double? zMaxOverride;

  const AdaptiveHeightmapView({
    super.key,
    required this.title,
    required this.heightmap,
    required this.colormap,
    required this.viewMode,
    this.loading = false,
    this.statusText,
    this.zMinOverride,
    this.zMaxOverride,
  });

  @override
  Widget build(BuildContext context) {
    return switch (viewMode) {
      ViewMode.flat => HeightmapView(
          title: title,
          heightmap: heightmap,
          colormap: colormap,
          loading: loading,
          statusText: statusText,
          zMinOverride: zMinOverride,
          zMaxOverride: zMaxOverride,
        ),
      ViewMode.rotatable => PointCloudView(
          title: title,
          heightmap: heightmap,
          colormap: colormap,
          loading: loading,
          zMinOverride: zMinOverride,
          zMaxOverride: zMaxOverride,
        ),
    };
  }
}

/// A rotatable 3D point-cloud rendering of a [Heightmap] -- drag to orbit.
/// The point: a flat top-down color map tells you *where* the groove is,
/// but not intuitively *how deep* -- rotating to a near-edge-on angle here
/// gives you the cross-section profile directly, and depth reads the way
/// depth actually looks, not as a color-to-number lookup.
class PointCloudView extends StatefulWidget {
  final String title;
  final Heightmap? heightmap;
  final HeightmapColormap colormap;
  final bool loading;
  final double? zMinOverride;
  final double? zMaxOverride;

  /// How much to exaggerate height relative to the (much larger) X/Y span,
  /// so the groove actually reads as a groove rather than a near-flat
  /// plane. Real depth is ~15mm over a ~30mm span -- true-scale would look
  /// almost flat from most angles.
  final double zExaggeration;

  /// Starting orbit angles (radians). Exposed mainly so tests/previews can
  /// verify the rotation math directly instead of through a simulated drag
  /// gesture; also handy if a future caller wants to open on a specific
  /// angle (e.g. a saved "cross-section" view). Double-tap resets back to
  /// these, not to the class-level defaults.
  final double initialAzimuth;
  final double initialElevation;

  const PointCloudView({
    super.key,
    required this.title,
    required this.heightmap,
    this.colormap = HeightmapColormap.viridis,
    this.loading = false,
    this.zMinOverride,
    this.zMaxOverride,
    this.zExaggeration = 3.0,
    this.initialAzimuth = -0.5,
    this.initialElevation = 0.5,
  });

  @override
  State<PointCloudView> createState() => _PointCloudViewState();
}

class _PointCloudViewState extends State<PointCloudView> {
  late double _azimuth = widget.initialAzimuth;
  late double _elevation = widget.initialElevation;

  static const double _minElevation = -math.pi / 2 + 0.05;
  static const double _maxElevation = math.pi / 2 - 0.05;

  void _resetView() {
    setState(() {
      _azimuth = widget.initialAzimuth;
      _elevation = widget.initialElevation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hm = widget.heightmap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            ),
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 18),
              tooltip: 'Reset view',
              onPressed: _resetView,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
                child: hm == null
                    ? const Center(child: Text('No data'))
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          setState(() {
                            _azimuth += details.delta.dx * 0.01;
                            _elevation =
                                (_elevation - details.delta.dy * 0.01).clamp(_minElevation, _maxElevation);
                          });
                        },
                        onDoubleTap: _resetView,
                        child: CustomPaint(
                          painter: _PointCloudPainter(
                            heightmap: hm,
                            zMin: widget.zMinOverride ?? hm.zMin,
                            zMax: widget.zMaxOverride ?? hm.zMax,
                            colormap: widget.colormap,
                            azimuth: _azimuth,
                            elevation: _elevation,
                            zExaggeration: widget.zExaggeration,
                          ),
                          child: Container(),
                        ),
                      ),
              ),
              if (widget.loading)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
            ],
          ),
        ),
        if (hm != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'drag to rotate — double-tap to reset',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _Projected {
  final double x; // screen-space, pre-scale/center
  final double y;
  final double depth; // camera-space depth, larger = farther; used for sorting
  final Color color;
  _Projected(this.x, this.y, this.depth, this.color);
}

class _Quad {
  final _Projected a, b, c, d;
  final double depth;
  final Color color;
  _Quad(this.a, this.b, this.c, this.d, this.depth, this.color);
}

/// A rotated-then-orthographically-projected 3D point: [x] and [y] are
/// screen-space coordinates (before scaling/centering), [depth] is
/// camera-space depth (larger = farther from the viewer).
///
/// Rotation order: spin around the vertical (height) axis by [azimuth]
/// first, then tilt the resulting view by [elevation] (0 = looking straight
/// down the height axis/top-down, +-pi/2 = looking level/edge-on).
/// Pure and public specifically so this can be unit-tested directly,
/// independent of any widget/gesture/rendering machinery.
class RotatedPoint {
  final double x;
  final double y;
  final double depth;
  const RotatedPoint(this.x, this.y, this.depth);
}

RotatedPoint rotateAndProject(
  double cx,
  double cy,
  double cz, {
  required double azimuth,
  required double elevation,
}) {
  final cosAz = math.cos(azimuth), sinAz = math.sin(azimuth);
  final cosEl = math.cos(elevation), sinEl = math.sin(elevation);

  final x1 = cx * cosAz - cy * sinAz;
  final y1 = cx * sinAz + cy * cosAz;
  final y2 = y1 * cosEl - cz * sinEl;
  final z2 = y1 * sinEl + cz * cosEl;

  return RotatedPoint(x1, y2, z2);
}

class _PointCloudPainter extends CustomPainter {
  final Heightmap heightmap;
  final double zMin;
  final double zMax;
  final HeightmapColormap colormap;
  final double azimuth;
  final double elevation;
  final double zExaggeration;

  _PointCloudPainter({
    required this.heightmap,
    required this.zMin,
    required this.zMax,
    required this.colormap,
    required this.azimuth,
    required this.elevation,
    required this.zExaggeration,
  });

  // Cap the rendered mesh resolution for interactive-rate dragging --
  // decimating a 300x300 grid down to at most ~70 per axis is still plenty
  // dense to read the shape, and keeps per-frame quad count in the low
  // thousands.
  static const int _maxPerAxis = 70;

  @override
  void paint(Canvas canvas, Size size) {
    final nx = heightmap.nx;
    final ny = heightmap.ny;
    if (nx == 0 || ny == 0) return;

    final strideX = math.max(1, (nx / _maxPerAxis).ceil());
    final strideY = math.max(1, (ny / _maxPerAxis).ceil());
    final xIndices = [for (var xi = 0; xi < nx; xi += strideX) xi];
    final yIndices = [for (var yi = 0; yi < ny; yi += strideY) yi];
    if (xIndices.length < 2 || yIndices.length < 2) return;

    final xMid = (heightmap.xMin + heightmap.xMax) / 2;
    final yMid = (heightmap.yMin + heightmap.yMax) / 2;
    final zRange = (zMax - zMin).abs() < 1e-9 ? 1.0 : (zMax - zMin);
    final zMid = (zMin + zMax) / 2;
    // Common X/Y scale so the groove's true aspect ratio is preserved;
    // height gets the same base scale times the exaggeration factor.
    final xySpan = math.max(heightmap.xMax - heightmap.xMin, heightmap.yMax - heightmap.yMin);
    final baseScale = xySpan <= 0 ? 1.0 : 2.0 / xySpan;

    final colorOf = colormapFunction(colormap);

    // Project every (decimated) grid vertex once, indexed [xi_pos][yi_pos]
    // (positions into xIndices/yIndices, not raw heightmap indices) so the
    // per-cell quad-building below can look up each corner by position
    // without re-projecting shared corners four times.
    final proj = List.generate(
      xIndices.length,
      (xpi) => List.generate(yIndices.length, (ypi) {
        final xi = xIndices[xpi];
        final yi = yIndices[ypi];
        final x = heightmap.xMm[xi];
        final y = heightmap.yMm[yi];
        final z = heightmap.zMm[xi][yi];
        final cx = (x - xMid) * baseScale;
        final cy = (y - yMid) * baseScale;
        // Negated: higher physical height should move UP on screen (the
        // universal convention for every terrain/elevation view), but
        // rotateAndProject's screen-Y and the canvas's pixel-Y are both
        // "larger value = higher up" internally -- without this flip the
        // deep groove floor ends up rendered above the plate surface.
        final cz = -(z - zMid) / zRange * zExaggeration;
        final r = rotateAndProject(cx, cy, cz, azimuth: azimuth, elevation: elevation);
        final t = ((z - zMin) / zRange).clamp(0.0, 1.0);
        return _Projected(r.x, r.y, r.depth, colorOf(t));
      }),
    );

    // Build one filled quad per grid cell (4 shared corners), rather than
    // disconnected points -- a surface has real occlusion (a near ridge
    // hides whatever's behind it), which is what actually makes rotating to
    // an edge-on angle read as a clean cross-section instead of every Y
    // value's points all showing through on top of each other.
    final quads = <_Quad>[];
    for (var xpi = 0; xpi < xIndices.length - 1; xpi++) {
      for (var ypi = 0; ypi < yIndices.length - 1; ypi++) {
        final a = proj[xpi][ypi];
        final b = proj[xpi + 1][ypi];
        final c = proj[xpi + 1][ypi + 1];
        final d = proj[xpi][ypi + 1];
        final avgDepth = (a.depth + b.depth + c.depth + d.depth) / 4;
        // Average the 4 corners' colors by averaging their underlying
        // height fraction isn't tracked post-color, so approximate with a
        // straight color lerp chain -- close enough at this resolution
        // (adjacent cells differ little in height) and avoids re-deriving t.
        final avgColor = Color.lerp(Color.lerp(a.color, b.color, 0.5), Color.lerp(c.color, d.color, 0.5), 0.5)!;
        quads.add(_Quad(a, b, c, d, avgDepth, avgColor));
      }
    }

    // Painter's algorithm: draw far-to-near so nearer geometry correctly
    // occludes farther geometry.
    quads.sort((q1, q2) => q2.depth.compareTo(q1.depth));

    final scale = math.min(size.width, size.height) * 0.42;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    Offset toScreen(_Projected p) => Offset(centerX + p.x * scale, centerY - p.y * scale);

    for (final q in quads) {
      final sa = toScreen(q.a), sb = toScreen(q.b), sc = toScreen(q.c), sd = toScreen(q.d);
      final path = Path()
        ..moveTo(sa.dx, sa.dy)
        ..lineTo(sb.dx, sb.dy)
        ..lineTo(sc.dx, sc.dy)
        ..lineTo(sd.dx, sd.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = q.color);
      // A thin matching-but-darker edge keeps individual cells faintly
      // legible as a surface (grid lines) rather than a flat color blob,
      // without the harsh look of a contrasting wireframe color.
      canvas.drawPath(
        path,
        Paint()
          ..color = q.color.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PointCloudPainter oldDelegate) {
    return oldDelegate.heightmap != heightmap ||
        oldDelegate.zMin != zMin ||
        oldDelegate.zMax != zMax ||
        oldDelegate.colormap != colormap ||
        oldDelegate.azimuth != azimuth ||
        oldDelegate.elevation != elevation ||
        oldDelegate.zExaggeration != zExaggeration;
  }
}
