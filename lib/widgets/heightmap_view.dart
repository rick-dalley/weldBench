import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../models/heightmap.dart';

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

/// Rasterizes a [Heightmap] into a [ui.Image] (one pixel per grid cell,
/// viridis-colored), for GPU-cheap scaled display via [Canvas.drawImageRect].
Future<ui.Image> _heightmapToImage(Heightmap hm, {required double zMin, required double zMax}) {
  final nx = hm.nx;
  final ny = hm.ny;
  final range = (zMax - zMin).abs() < 1e-9 ? 1.0 : (zMax - zMin);

  final pixels = Uint8List(nx * ny * 4); // RGBA
  for (var xi = 0; xi < nx; xi++) {
    for (var yi = 0; yi < ny; yi++) {
      final z = hm.zMm[xi][yi];
      final t = (z - zMin) / range;
      final c = _viridis(t);
      // Flip Y so larger Y (further along the weld) renders toward the top.
      final row = ny - 1 - yi;
      final idx = (row * nx + xi) * 4;
      pixels[idx] = (c.r * 255).round();
      pixels[idx + 1] = (c.g * 255).round();
      pixels[idx + 2] = (c.b * 255).round();
      pixels[idx + 3] = 255;
    }
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    nx,
    ny,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class HeightmapView extends StatefulWidget {
  final String title;
  final Heightmap? heightmap;
  final bool loading;
  final String? statusText;

  /// Shared z-range across panels, so color scales line up when comparing.
  /// If null, uses this heightmap's own min/max.
  final double? zMinOverride;
  final double? zMaxOverride;

  const HeightmapView({
    super.key,
    required this.title,
    required this.heightmap,
    this.loading = false,
    this.statusText,
    this.zMinOverride,
    this.zMaxOverride,
  });

  @override
  State<HeightmapView> createState() => _HeightmapViewState();
}

class _HeightmapViewState extends State<HeightmapView> {
  ui.Image? _image;
  Heightmap? _imageForHeightmap;

  @override
  void didUpdateWidget(covariant HeightmapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRebuildImage();
  }

  @override
  void initState() {
    super.initState();
    _maybeRebuildImage();
  }

  void _maybeRebuildImage() {
    final hm = widget.heightmap;
    if (hm == null || identical(hm, _imageForHeightmap)) return;
    _imageForHeightmap = hm;
    final zMin = widget.zMinOverride ?? hm.zMin;
    final zMax = widget.zMaxOverride ?? hm.zMax;
    _heightmapToImage(hm, zMin: zMin, zMax: zMax).then((img) {
      if (!mounted) return;
      setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hm = widget.heightmap;
    final zMin = widget.zMinOverride ?? hm?.zMin;
    final zMax = widget.zMaxOverride ?? hm?.zMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
                child: (hm == null || _image == null)
                    ? const Center(child: Text('No data'))
                    : CustomPaint(
                        painter: _ImagePainter(_image!),
                        child: Container(),
                      ),
              ),
              if (widget.loading)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        if (widget.statusText != null) ...[
                          const SizedBox(height: 8),
                          Text(widget.statusText!, style: const TextStyle(color: Colors.white)),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hm != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'z: ${zMin!.toStringAsFixed(2)} to ${zMax!.toStringAsFixed(2)} mm',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.none);
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) => oldDelegate.image != image;
}
