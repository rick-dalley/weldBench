import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'models/heightmap.dart';
import 'models/run_progress.dart';
import 'models/weld_parameters.dart';
import 'services/fast_service_launcher.dart';
import 'services/service_launcher.dart';
import 'services/weld_fast_service.dart';
import 'services/weld_service.dart';
import 'widgets/heightmap_view.dart';
import 'widgets/parameter_panel.dart';
import 'widgets/stage_timeline.dart';

void main() {
  runApp(const WeldBenchApp());
}

class WeldBenchApp extends StatelessWidget {
  const WeldBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'weldBench',
      theme: ThemeData(colorSchemeSeed: const Color(0xFFB7410E), useMaterial3: true),
      home: const _StartupGate(),
    );
  }
}

/// Ensures weld_service is up (spawning it from the sibling `fluid` checkout
/// if nothing's already listening) and the two real reference scans are
/// loaded, before showing the main UI. This is the one-time cost of not
/// having to start weld_service by hand in a separate terminal.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  final _launcher = ServiceLauncher();
  final _weldService = WeldService();
  final _fastLauncher = FastServiceLauncher();
  final _fastWeldService = WeldFastService();

  String _status = 'starting up...';
  String? _error;
  Heightmap? _emptyGroove;
  Heightmap? _weldedGroove;

  @override
  void initState() {
    super.initState();
    _startup();
  }

  Future<void> _startup() async {
    try {
      await _launcher.ensureRunning(onStatus: (s) {
        if (mounted) setState(() => _status = s);
      });
      setState(() => _status = 'loading reference scans...');
      final empty = await _weldService.fetchEmptyGrooveReference();
      final welded = await _weldService.fetchWeldedGrooveReference();
      if (!mounted) return;
      setState(() {
        _emptyGroove = empty;
        _weldedGroove = welded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      return;
    }

    // weld_fast_service's live 4th panel is a nice-to-have, not required
    // for the rest of the app to work -- don't block startup (or fail the
    // whole app) if it can't be started; the panel itself reports
    // unavailability instead (see WeldBenchHome's _fastError handling).
    try {
      setState(() => _status = 'starting weld_fast_service...');
      await _fastLauncher.ensureRunning(onStatus: (s) {
        if (mounted) setState(() => _status = s);
      });
    } catch (e) {
      // ignore: the 4th panel will show its own "unavailable" state.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Failed to start weld_service:\n$_error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Is a Rust toolchain on PATH, and is fluid a sibling checkout '
                  '(or WELD_SERVICE_DIR set to point at it)?',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_emptyGroove == null || _weldedGroove == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(_status),
            ],
          ),
        ),
      );
    }

    return WeldBenchHome(
      launcher: _launcher,
      weldService: _weldService,
      fastLauncher: _fastLauncher,
      fastWeldService: _fastWeldService,
      emptyGroove: _emptyGroove!,
      weldedGroove: _weldedGroove!,
    );
  }
}

class WeldBenchHome extends StatefulWidget {
  final ServiceLauncher launcher;
  final WeldService weldService;
  final FastServiceLauncher fastLauncher;
  final WeldFastService fastWeldService;
  final Heightmap emptyGroove;
  final Heightmap weldedGroove;

  const WeldBenchHome({
    super.key,
    required this.launcher,
    required this.weldService,
    required this.fastLauncher,
    required this.fastWeldService,
    required this.emptyGroove,
    required this.weldedGroove,
  });

  @override
  State<WeldBenchHome> createState() => _WeldBenchHomeState();
}

class _WeldBenchHomeState extends State<WeldBenchHome> with WidgetsBindingObserver {
  final _params = WeldParameters();

  Heightmap? _simulated;
  bool _running = false;
  String? _errorText;
  List<StageRecord> _stages = [];
  SolveProgress? _solveProgress;
  HeightmapColormap _colormap = HeightmapColormap.viridis;

  // weld_fast_service's live prediction -- updated on every slider change
  // (lightly debounced, see _scheduleFastPrediction), not gated by the
  // "Weld" button.
  FastPredictResult? _fastResult;
  String? _fastError;
  Timer? _fastDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Populate the fast-model panel immediately on startup, so it isn't
    // blank before the user's first slider touch.
    _updateFastPrediction();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // Only stop a service if we're the ones who started it -- if the user
    // already had an instance running before launching weldBench, leave it
    // running for them.
    if (widget.launcher.startedByUs) {
      await widget.launcher.stop();
    }
    if (widget.fastLauncher.startedByUs) {
      await widget.fastLauncher.stop();
    }
    return AppExitResponse.exit;
  }

  /// Debounces rapid slider drags (each one calls this via ParameterPanel's
  /// onChanged) so we don't fire an HTTP request per intermediate drag
  /// frame -- weld_fast_service is fast enough that it wouldn't matter much
  /// server-side, but there's no reason to hammer it either.
  void _scheduleFastPrediction() {
    _fastDebounce?.cancel();
    _fastDebounce = Timer(const Duration(milliseconds: 75), _updateFastPrediction);
  }

  Future<void> _updateFastPrediction() async {
    try {
      final result = await widget.fastWeldService.predict(_params);
      if (!mounted) return;
      setState(() {
        _fastResult = result;
        _fastError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fastError = e.toString();
      });
    }
  }

  Future<void> _runWeld() async {
    setState(() {
      _running = true;
      _errorText = null;
      _stages = [];
      _solveProgress = null;
    });
    try {
      final result = await widget.weldService.runWeld(
        _params,
        onProgress: (update) {
          if (!mounted) return;
          setState(() {
            _stages = update.stages;
            _solveProgress = update.solveProgress;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _simulated = result;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _errorText = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _fastDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Share a z-range across the reference panels so their color scales are
    // directly comparable; the ferrousFoam panel gets its own scale until we
    // know it's on the same physical basis (it may run in a smaller/offset
    // local domain). The fast-model panel is deliberately given its own
    // scale too (not folded into refZMin/refZMax), even though
    // weld_fast_service *does* calibrate its Z values onto the same
    // absolute scale as the real scans (see fluid's calibration.rs): its
    // heightmap changes on every slider drag, so sharing the range would
    // make the two real (static) panels' colors continuously rescale/
    // flicker as the user drags a slider that has nothing to do with those
    // scans -- undermining exactly the reference-vs-reference comparison
    // the shared range exists for. The numeric "z: X to Y mm" caption under
    // each panel is still on the same absolute scale and directly
    // comparable even though the color gradients aren't forced to match.
    final refZMin = [widget.emptyGroove.zMin, widget.weldedGroove.zMin].reduce((a, b) => a < b ? a : b);
    final refZMax = [widget.emptyGroove.zMax, widget.weldedGroove.zMax].reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('weldBench'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SegmentedButton<HeightmapColormap>(
                segments: const [
                  ButtonSegment(value: HeightmapColormap.viridis, label: Text('Viridis')),
                  ButtonSegment(value: HeightmapColormap.grayscale, label: Text('Grayscale')),
                ],
                selected: {_colormap},
                onSelectionChanged: (s) => setState(() => _colormap = s.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: FilledButton.icon(
                onPressed: _running ? null : _runWeld,
                icon: const Icon(Icons.local_fire_department),
                label: const Text('Weld'),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            // Narrowed from 360 to make room for the 4th heightmap panel
            // without the others getting too cramped.
            width: 320,
            child: ParameterPanel(
              params: _params,
              onChanged: () {
                setState(() {});
                _scheduleFastPrediction();
              },
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (_stages.isNotEmpty) StageTimeline(stages: _stages, solveProgress: _solveProgress),
                if (_errorText != null)
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 220),
                    color: Colors.red.shade50,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Run failed',
                                style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copy error to clipboard',
                              color: Colors.red.shade900,
                              onPressed: () => Clipboard.setData(ClipboardData(text: _errorText!)),
                            ),
                          ],
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _errorText!,
                              style: TextStyle(color: Colors.red.shade900, fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: HeightmapView(
                            title: 'Empty groove (no-tack scan)',
                            heightmap: widget.emptyGroove,
                            colormap: _colormap,
                            zMinOverride: refZMin,
                            zMaxOverride: refZMax,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: HeightmapView(
                            title: 'Real weld (tack scan, ground truth)',
                            heightmap: widget.weldedGroove,
                            colormap: _colormap,
                            zMinOverride: refZMin,
                            zMaxOverride: refZMax,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: HeightmapView(
                            title: 'ferrousFoam prediction',
                            heightmap: _simulated,
                            colormap: _colormap,
                            loading: _running,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FastModelPanel(
                            heightmap: _fastResult?.heightmap,
                            outputs: _fastResult?.outputs,
                            findings: _fastResult?.findings ?? const [],
                            error: _fastError,
                            colormap: _colormap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The 4th comparison panel: weld_fast_service's live prediction, plus a
/// small text summary of its numeric outputs and any process-window
/// findings underneath -- separate from [HeightmapView] itself (shared by
/// all 4 panels) so the other 3 panels aren't affected by this extra text.
class FastModelPanel extends StatelessWidget {
  final Heightmap? heightmap;
  final FastPredictOutputs? outputs;
  final List<FastFinding> findings;
  final String? error;
  final HeightmapColormap colormap;

  const FastModelPanel({
    super.key,
    required this.heightmap,
    required this.outputs,
    required this.findings,
    required this.error,
    required this.colormap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: HeightmapView(
            title: 'Fast model (weld_sim, live)',
            heightmap: heightmap,
            colormap: colormap,
          ),
        ),
        if (error == null && outputs != null) ...[
          const SizedBox(height: 4),
          Text(
            '${outputs!.currentA.toStringAsFixed(0)} A · '
            '${outputs!.heatInputJMm.toStringAsFixed(0)} J/mm · '
            'pen ${outputs!.penetrationMm.toStringAsFixed(1)} mm · '
            'width ${outputs!.beadWidthMm.toStringAsFixed(1)} mm · '
            'fill ${(outputs!.fillRatio * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final f in findings.take(2))
            Text(
              f.message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: f.severity == 'critical' ? Colors.red.shade700 : Colors.orange.shade800,
                  ),
            ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }
}
