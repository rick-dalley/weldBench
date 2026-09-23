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

  /// Passed through to whichever view is active; non-null only while the
  /// caller's cross-section picker toolbar toggle is on (see main.dart), so
  /// tapping a panel is a no-op the rest of the time.
  final void Function(double xMm, double yMm)? onPointPicked;

  /// Forwarded to [PointCloudView] (ignored in flat 2D mode, which has no
  /// notion of an occluding wall to open up) -- see its own doc comment.
  /// Only ever true for the two real profilometer-scan panels.
  final bool showBackingPlate;

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
    this.onPointPicked,
    this.showBackingPlate = false,
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
          onPointPicked: onPointPicked,
        ),
      ViewMode.rotatable => PointCloudView(
          title: title,
          heightmap: heightmap,
          colormap: colormap,
          loading: loading,
          zMinOverride: zMinOverride,
          zMaxOverride: zMaxOverride,
          onPointPicked: onPointPicked,
          showBackingPlate: showBackingPlate,
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

  /// Called with the (xMm, yMm) of the visible surface point nearest a tap,
  /// so a caller can pop up a 2D cross-section slice through that exact
  /// spot -- rotating to near-edge-on gives the general shape, but reading
  /// an exact depth off a tilted 3D view is still guesswork. Left null
  /// (the default) to leave tapping alone -- callers only pass this while
  /// their own "cross-section picker" toolbar toggle is active, so an
  /// ordinary tap while just orbiting the view doesn't do anything
  /// surprising.
  final void Function(double xMm, double yMm)? onPointPicked;

  /// Only meaningful for the real profilometer scans, not a predicted
  /// (ferrousFoam/fast-model) surface: the raw scan's deepest points, right
  /// at the groove center, are the laser seeing through the narrow root gap
  /// between the two beveled plates down to the flat backing table beneath
  /// them -- not a continuation of the V. Rendered naively (as literally
  /// just more heightfield), that reads as a small, confusing square notch.
  /// When true, that narrow notch is detected per-row and rendered instead
  /// as an actual opening in the V walls, with a separate flat table
  /// surface spanning the full groove width beneath it (fading out at the
  /// left/right edges, since the real table plausibly continues beyond
  /// what's shown) -- see _PointCloudPainter's gap-detection logic. Left
  /// false (the default) for predicted surfaces, which have no such
  /// artifact and would just get a spurious hole carved out of a smooth V
  /// if this ran on them.
  final bool showBackingPlate;

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
    this.onPointPicked,
    this.showBackingPlate = false,
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.biggest;
                          final zMin = widget.zMinOverride ?? hm.zMin;
                          final zMax = widget.zMaxOverride ?? hm.zMax;
                          return MouseRegion(
                            cursor: widget.onPointPicked != null
                                ? SystemMouseCursors.precise
                                : MouseCursor.defer,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (details) {
                                setState(() {
                                  _azimuth += details.delta.dx * 0.01;
                                  _elevation = (_elevation - details.delta.dy * 0.01)
                                      .clamp(_minElevation, _maxElevation);
                                });
                              },
                              onDoubleTap: _resetView,
                              onTapUp: widget.onPointPicked == null
                                  ? null
                                  : (details) {
                                      final hit = hitTestGridPoint(
                                        heightmap: hm,
                                        zMin: zMin,
                                        zMax: zMax,
                                        azimuth: _azimuth,
                                        elevation: _elevation,
                                        zExaggeration: widget.zExaggeration,
                                        size: size,
                                        tapPosition: details.localPosition,
                                      );
                                      if (hit != null) {
                                        widget.onPointPicked!(hm.xMm[hit.xi], hm.yMm[hit.yi]);
                                      }
                                    },
                              child: CustomPaint(
                                painter: _PointCloudPainter(
                                  heightmap: hm,
                                  zMin: zMin,
                                  zMax: zMax,
                                  colormap: widget.colormap,
                                  azimuth: _azimuth,
                                  elevation: _elevation,
                                  zExaggeration: widget.zExaggeration,
                                  showBackingPlate: widget.showBackingPlate,
                                ),
                                child: Container(),
                              ),
                            ),
                          );
                        },
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
              widget.onPointPicked != null
                  ? 'tap to inspect a cross-section — drag to rotate'
                  : 'drag to rotate — double-tap to reset',
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
  // 1.0 for an ordinary surface quad. Less than 1.0 only for backing-table
  // quads near the domain's X edges, so the table visually "trails off"
  // there instead of ending in a hard edge -- see
  // _PointCloudPainter._buildBackingPlateQuads.
  final double alpha;
  _Quad(this.a, this.b, this.c, this.d, this.depth, this.color, {this.alpha = 1.0});
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

class GridHit {
  final int xi;
  final int yi;
  const GridHit(this.xi, this.yi);
}

/// Finds the full-resolution grid point whose rendered screen position is
/// closest to [tapPosition], using the exact same projection math as
/// [_PointCloudPainter] -- so "the point you tapped" really is the point
/// you were looking at, not some other vertex. Among points within
/// [pixelTolerance] of the tap, the frontmost (smallest camera-space depth)
/// one wins ties, since that's the one actually visible at that screen
/// location when nearer geometry occludes farther geometry. Public and
/// pure so it's directly unit-testable, same as [rotateAndProject].
GridHit? hitTestGridPoint({
  required Heightmap heightmap,
  required double zMin,
  required double zMax,
  required double azimuth,
  required double elevation,
  required double zExaggeration,
  required Size size,
  required Offset tapPosition,
  double pixelTolerance = 18.0,
}) {
  final nx = heightmap.nx, ny = heightmap.ny;
  if (nx == 0 || ny == 0) return null;
  final xMid = (heightmap.xMin + heightmap.xMax) / 2;
  final yMid = (heightmap.yMin + heightmap.yMax) / 2;
  final zRange = (zMax - zMin).abs() < 1e-9 ? 1.0 : (zMax - zMin);
  final zMid = (zMin + zMax) / 2;
  final xySpan = math.max(heightmap.xMax - heightmap.xMin, heightmap.yMax - heightmap.yMin);
  final baseScale = xySpan <= 0 ? 1.0 : 2.0 / xySpan;
  final scale = math.min(size.width, size.height) * 0.42;
  final centerX = size.width / 2;
  final centerY = size.height / 2;

  int? bestXi, bestYi;
  var bestDepth = double.infinity;
  var bestDistSq = double.infinity;
  final toleranceSq = pixelTolerance * pixelTolerance;

  for (var xi = 0; xi < nx; xi++) {
    final x = heightmap.xMm[xi];
    final cx = (x - xMid) * baseScale;
    for (var yi = 0; yi < ny; yi++) {
      final y = heightmap.yMm[yi];
      final z = heightmap.zMm[xi][yi];
      final cy = (y - yMid) * baseScale;
      final cz = -(z - zMid) / zRange * zExaggeration;
      final r = rotateAndProject(cx, cy, cz, azimuth: azimuth, elevation: elevation);
      final sx = centerX + r.x * scale;
      final sy = centerY - r.y * scale;
      final dx = sx - tapPosition.dx;
      final dy = sy - tapPosition.dy;
      final distSq = dx * dx + dy * dy;
      if (distSq > toleranceSq) continue;
      if (r.depth < bestDepth - 1e-6 || (r.depth <= bestDepth + 1e-6 && distSq < bestDistSq)) {
        bestDepth = r.depth;
        bestDistSq = distSq;
        bestXi = xi;
        bestYi = yi;
      }
    }
  }
  if (bestXi == null || bestYi == null) return null;
  return GridHit(bestXi, bestYi);
}

class _PointCloudPainter extends CustomPainter {
  final Heightmap heightmap;
  final double zMin;
  final double zMax;
  final HeightmapColormap colormap;
  final double azimuth;
  final double elevation;
  final double zExaggeration;
  final bool showBackingPlate;

  _PointCloudPainter({
    required this.heightmap,
    required this.zMin,
    required this.zMax,
    required this.colormap,
    required this.azimuth,
    required this.elevation,
    required this.zExaggeration,
    this.showBackingPlate = false,
  });

  // How far above a row's own minimum Z counts as still "the narrow root-
  // gap notch" rather than "the general V-groove floor" -- the notch is a
  // small, sharp additional dip right at the groove center, distinct from
  // (and deeper than) the broader V shape around it. Picked empirically
  // against the real RealGrooveCase scan geometry (root gap ~4.3mm, notch
  // depth relative to the surrounding floor on the order of 1-2mm); a
  // heightmap without this feature (predicted panels never reach this code
  // path at all, gated by showBackingPlate) wouldn't be affected either way.
  static const double _gapDetectionToleranceMm = 1.2;

  // Hard ceiling on the detected notch width, regardless of how far the
  // tolerance-based expansion below would otherwise go. Needed for the
  // welded scan specifically: where a tack bead fills the groove, its own
  // tapered edges stay within _gapDetectionToleranceMm of the row's
  // minimum over a much wider span than the true notch (observed up to
  // ~10mm on real data), which would wrongly carve a hole out of solid
  // bead material -- "the tack doesn't fill in" in the 3D view. The real
  // root gap is a known, fixed physical dimension (~4.3mm, confirmed
  // against both the calibration constant used elsewhere in this app and
  // directly against bare-groove rows of the real scan, which detect
  // 4.3-4.5mm on their own, well under this cap); this just stops the
  // *welded* rows' wider, gentler bead-taper dip from being mistaken for
  // it. Verified against real data: with this cap, bare-groove rows are
  // completely unaffected (already under it), while previously-inflated
  // welded rows correctly clamp down to a narrow strip again.
  static const double _gapMaxWidthMm = 6.0;

  /// The raw X-range (in mm) of the row's narrow root-gap notch, isolated
  /// from the broader V-shaped floor (or, on a welded row, the bead) around
  /// it by looking only at points within [_gapDetectionToleranceMm] of the
  /// row's minimum, capped to [_gapMaxWidthMm] wide (see its doc comment).
  /// The notch is a real, physical feature of the root gap itself (present
  /// the full length of the groove, not just where a tack weld happens to
  /// sit), so this is expected to find something on every row of a real
  /// scan.
  ({double xLoMm, double xHiMm}) _detectGapXRangeMm(int yi) {
    final nx = heightmap.nx;
    var minZ = double.infinity;
    var minXi = 0;
    for (var xi = 0; xi < nx; xi++) {
      final z = heightmap.zMm[xi][yi];
      if (z < minZ) {
        minZ = z;
        minXi = xi;
      }
    }
    final threshold = minZ + _gapDetectionToleranceMm;
    var loXi = minXi;
    while (loXi > 0 && heightmap.zMm[loXi - 1][yi] <= threshold) {
      loXi--;
    }
    var hiXi = minXi;
    while (hiXi < nx - 1 && heightmap.zMm[hiXi + 1][yi] <= threshold) {
      hiXi++;
    }
    // Shrink symmetrically toward the true minimum until back under the
    // cap, preferring to trim whichever side is currently farther from it.
    while (heightmap.xMm[hiXi] - heightmap.xMm[loXi] > _gapMaxWidthMm && (hiXi > minXi || loXi < minXi)) {
      final distHi = hiXi > minXi ? heightmap.xMm[hiXi] - heightmap.xMm[minXi] : -1.0;
      final distLo = loXi < minXi ? heightmap.xMm[minXi] - heightmap.xMm[loXi] : -1.0;
      if (distHi >= distLo && hiXi > minXi) {
        hiXi--;
      } else if (loXi < minXi) {
        loXi++;
      } else {
        hiXi--;
      }
    }
    return (xLoMm: heightmap.xMm[loXi], xHiMm: heightmap.xMm[hiXi]);
  }

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

    // The real scan's narrow root-gap notch, per decimated row -- null
    // entries mean "no gap detected on this row" (shouldn't normally happen
    // on a real scan, but guards against a degenerate/empty heightmap).
    // Only computed when showBackingPlate is set, since this is meaningless
    // (and wasted work) for a predicted surface.
    final gapRangesByRow = showBackingPlate
        ? [for (final yi in yIndices) _detectGapXRangeMm(yi)]
        : null;

    bool cellIsInGap(int xpi, int ypi) {
      if (gapRangesByRow == null) return false;
      final xLo = heightmap.xMm[xIndices[xpi]];
      final xHi = heightmap.xMm[xIndices[xpi + 1]];
      // Require BOTH bounding rows to independently agree this column
      // range is inside their own gap -- conservative, so a single noisy
      // row doesn't punch an isolated hole in the wall.
      for (final ypiToCheck in [ypi, ypi + 1]) {
        final g = gapRangesByRow[ypiToCheck];
        if (xLo < g.xLoMm || xHi > g.xHiMm) return false;
      }
      return true;
    }

    // Build one filled quad per grid cell (4 shared corners), rather than
    // disconnected points -- a surface has real occlusion (a near ridge
    // hides whatever's behind it), which is what actually makes rotating to
    // an edge-on angle read as a clean cross-section instead of every Y
    // value's points all showing through on top of each other. Cells fully
    // inside the detected root-gap notch are skipped entirely -- a real
    // opening, not surface -- so the separate backing-plate quads built
    // below are actually visible through it rather than just being drawn
    // behind an unbroken wall.
    final quads = <_Quad>[];
    for (var xpi = 0; xpi < xIndices.length - 1; xpi++) {
      for (var ypi = 0; ypi < yIndices.length - 1; ypi++) {
        if (cellIsInGap(xpi, ypi)) continue;
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

    if (showBackingPlate) {
      quads.addAll(_buildBackingPlateQuads(
        xIndices: xIndices,
        yIndices: yIndices,
        xMid: xMid,
        yMid: yMid,
        zMid: zMid,
        zRange: zRange,
        baseScale: baseScale,
        colorOf: colorOf,
      ));
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
      final fillColor = q.alpha >= 1.0 ? q.color : q.color.withValues(alpha: q.color.a * q.alpha);
      canvas.drawPath(path, Paint()..color = fillColor);
      // A thin matching-but-darker edge keeps individual cells faintly
      // legible as a surface (grid lines) rather than a flat color blob,
      // without the harsh look of a contrasting wireframe color.
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor.withValues(alpha: fillColor.a * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  /// A flat surface at the deepest Z the scan recorded anywhere (the most
  /// plausible reading of the backing table, glimpsed only through the
  /// narrow root gap) -- spanning the FULL X width of the groove (matching
  /// the two top plates' outer edges, not just the gap itself), since the
  /// real table plausibly extends at least that far either way. Its own
  /// left/right edges fade toward transparent rather than ending in a hard
  /// line, since the table almost certainly continues beyond what the scan
  /// actually captured.
  List<_Quad> _buildBackingPlateQuads({
    required List<int> xIndices,
    required List<int> yIndices,
    required double xMid,
    required double yMid,
    required double zMid,
    required double zRange,
    required double baseScale,
    required Color Function(double) colorOf,
  }) {
    var tableZ = double.infinity;
    for (final row in heightmap.zMm) {
      for (final z in row) {
        if (z < tableZ) tableZ = z;
      }
    }
    final cz = -(tableZ - zMid) / zRange * zExaggeration;
    final t = ((tableZ - zMin) / zRange).clamp(0.0, 1.0);
    final color = colorOf(t);

    // Fraction of the domain width, at each end, over which the table
    // fades from fully transparent (at the very edge) to fully opaque.
    const fadeFraction = 0.15;
    final xLoMm = heightmap.xMin;
    final xHiMm = heightmap.xMax;
    final span = (xHiMm - xLoMm).abs() < 1e-9 ? 1.0 : (xHiMm - xLoMm);
    double edgeAlpha(double xMm) {
      final tFromLo = (xMm - xLoMm) / span;
      final distFromEdge = math.min(tFromLo, 1.0 - tFromLo);
      return (distFromEdge / fadeFraction).clamp(0.0, 1.0);
    }

    _Projected project(double xMm, double yMm) {
      final cx = (xMm - xMid) * baseScale;
      final cy = (yMm - yMid) * baseScale;
      final r = rotateAndProject(cx, cy, cz, azimuth: azimuth, elevation: elevation);
      return _Projected(r.x, r.y, r.depth, color);
    }

    final quads = <_Quad>[];
    for (var xpi = 0; xpi < xIndices.length - 1; xpi++) {
      final xLo = heightmap.xMm[xIndices[xpi]];
      final xHi = heightmap.xMm[xIndices[xpi + 1]];
      final alpha = math.min(edgeAlpha(xLo), edgeAlpha(xHi));
      if (alpha <= 0.0) continue;
      for (var ypi = 0; ypi < yIndices.length - 1; ypi++) {
        final yLo = heightmap.yMm[yIndices[ypi]];
        final yHi = heightmap.yMm[yIndices[ypi + 1]];
        final a = project(xLo, yLo);
        final b = project(xHi, yLo);
        final c = project(xHi, yHi);
        final d = project(xLo, yHi);
        final avgDepth = (a.depth + b.depth + c.depth + d.depth) / 4;
        quads.add(_Quad(a, b, c, d, avgDepth, color, alpha: alpha));
      }
    }
    return quads;
  }

  @override
  bool shouldRepaint(covariant _PointCloudPainter oldDelegate) {
    return oldDelegate.heightmap != heightmap ||
        oldDelegate.zMin != zMin ||
        oldDelegate.zMax != zMax ||
        oldDelegate.colormap != colormap ||
        oldDelegate.azimuth != azimuth ||
        oldDelegate.elevation != elevation ||
        oldDelegate.zExaggeration != zExaggeration ||
        oldDelegate.showBackingPlate != showBackingPlate;
  }
}
