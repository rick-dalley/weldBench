import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'models/heightmap.dart';
import 'models/run_progress.dart';
import 'models/weld_parameters.dart';
import 'services/service_launcher.dart';
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
      emptyGroove: _emptyGroove!,
      weldedGroove: _weldedGroove!,
    );
  }
}

class WeldBenchHome extends StatefulWidget {
  final ServiceLauncher launcher;
  final WeldService weldService;
  final Heightmap emptyGroove;
  final Heightmap weldedGroove;

  const WeldBenchHome({
    super.key,
    required this.launcher,
    required this.weldService,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // Only stop weld_service if we're the ones who started it -- if the
    // user already had an instance running before launching weldBench,
    // leave it running for them.
    if (widget.launcher.startedByUs) {
      await widget.launcher.stop();
    }
    return AppExitResponse.exit;
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Share a z-range across the reference panels so their color scales are
    // directly comparable; the simulated panel gets its own scale until we
    // know it's on the same physical basis (it may run in a smaller/offset
    // local domain).
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
            width: 360,
            child: ParameterPanel(
              params: _params,
              onChanged: () => setState(() {}),
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
                    color: Colors.red.shade50,
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _errorText!,
                      style: TextStyle(color: Colors.red.shade900),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: HeightmapView(
                            title: 'Real weld (tack scan, ground truth)',
                            heightmap: widget.weldedGroove,
                            colormap: _colormap,
                            zMinOverride: refZMin,
                            zMaxOverride: refZMax,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: HeightmapView(
                            title: 'ferrousFoam prediction',
                            heightmap: _simulated,
                            colormap: _colormap,
                            loading: _running,
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
