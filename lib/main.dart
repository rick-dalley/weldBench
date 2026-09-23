import 'dart:async';
import 'dart:math' as math;
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
import 'widgets/cross_section_view.dart';
import 'widgets/heightmap_view.dart';
import 'widgets/parameter_panel.dart';
import 'widgets/point_cloud_view.dart';
import 'widgets/stage_timeline.dart';

/// Mean Z over the outer 10% of X-columns on both sides of the real
/// empty-groove scan -- the flat plate surrounding the groove, which the 2D
/// heatmap already renders as yellow/max-Z. Treating that as depth-zero is
/// how the groove/bead depth numbers discussed in-app were derived, and is
/// the reference every cross-section flyout is plotted against, including
/// for the ferrousFoam/fast-model panels (weld_fast_service calibrates its
/// own Z values onto this same absolute scale -- see fluid's calibration.rs).
double _computeSurfaceReferenceMm(Heightmap emptyGroove) {
  final nx = emptyGroove.nx;
  if (nx == 0) return 0;
  final edgeN = math.max(1, (nx * 0.10).round());
  var sum = 0.0;
  var count = 0;
  for (var xi = 0; xi < edgeN; xi++) {
    for (final z in emptyGroove.zMm[xi]) {
      sum += z;
      count++;
    }
  }
  for (var xi = math.max(edgeN, nx - edgeN); xi < nx; xi++) {
    for (final z in emptyGroove.zMm[xi]) {
      sum += z;
      count++;
    }
  }
  return count == 0 ? emptyGroove.zMax : sum / count;
}

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
  PendingRunAction? _pendingRunAction;

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
      initialRunAction: _pendingRunAction,
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
  // If the startup gate's incomplete-run dialog resolved with a choice
  // (see _StartupGate._checkIncompleteRuns), this is it -- kicked off in
  // initState so it behaves exactly like an in-progress weld from the very
  // first frame, rather than requiring a second "Weld" press.
  final PendingRunAction? initialRunAction;

  const WeldBenchHome({
    super.key,
    required this.launcher,
    required this.weldService,
    required this.fastLauncher,
    required this.fastWeldService,
    required this.emptyGroove,
    required this.weldedGroove,
    this.initialRunAction,
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
  ViewMode _viewMode = ViewMode.flat;
  bool _pickingCrossSection = false;
  late final double _surfaceReferenceMm = _computeSurfaceReferenceMm(widget.emptyGroove);

  // Backs the "Previous welds" dropdown in ParameterPanel -- every run
  // weld_service has ever staged, regardless of how it ended (see GET
  // /runs). Refreshed on startup and after each weld finishes, so a just-
  // completed run shows up without needing a full app restart.
  List<RunHistoryEntry> _runHistory = [];

  // weld_fast_service's live prediction -- updated on every slider change
  // (lightly debounced, see _scheduleFastPrediction), not gated by the
  // "Weld" button.
  FastPredictResult? _fastResult;
  String? _fastError;
  Timer? _fastDebounce;

  // While a run (fresh, resumed, or restarted) is in progress, this is its
  // run_id and a separate timer polls GET /runs/{run_id}/heightmap on its
  // own cadence -- alongside (not instead of) the status poll inside
  // WeldService.runWeld/resumeRun/restartRun -- so the ferrousFoam panel
  // shows the solution evolving via live snapshots (see case_runner.rs's
  // background snapshot thread) instead of just a spinner for the whole
  // solve.
  String? _currentRunId;
  Timer? _heightmapPollTimer;
  static const _heightmapPollInterval = Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Populate the fast-model panel immediately on startup, so it isn't
    // blank before the user's first slider touch.
    _updateFastPrediction();
    _loadRunHistory();

    final pending = widget.initialRunAction;
    if (pending != null) {
      switch (pending.kind) {
        case RunActionKind.restart:
          _restartRun(pending.runId);
        case RunActionKind.resume:
          _resumeRun(pending.runId);
        case RunActionKind.view:
          _viewLastResult(pending.runId);
      }
    }
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

  /// Shared driver behind a fresh run, a resume, and a restart: all three
  /// put the UI in exactly the same "in progress" shape (spinner-eligible
  /// panel, stage timeline, live heightmap polling), differing only in
  /// which HTTP calls [starter] makes to get there. [starter] is handed
  /// [onRunId] (call as soon as a run_id is known, fresh or existing, so
  /// live heightmap polling can start) and [onProgress] (status-poll
  /// updates, same shape for all three paths).
  Future<void> _driveRun(
    Future<Heightmap> Function({
      required void Function(String runId) onRunId,
      required void Function(RunStatusUpdate update) onProgress,
    })
        starter,
  ) async {
    setState(() {
      _running = true;
      _errorText = null;
      _stages = [];
      _solveProgress = null;
    });
    try {
      final result = await starter(
        onRunId: _startHeightmapPolling,
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
      _loadRunHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _errorText = e.toString();
      });
    } finally {
      _stopHeightmapPolling();
    }
  }

  Future<void> _runWeld() => _driveRun(
        ({required onRunId, required onProgress}) => widget.weldService.runWeld(
          _params,
          onRunId: onRunId,
          onProgress: onProgress,
        ),
      );

  /// Continues an incomplete/failed run from its startup-gate dialog choice
  /// (see _StartupGate._checkIncompleteRuns) or, in principle, any other
  /// future "resume" entry point -- [runId] is already known, so `onRunId`
  /// is called immediately rather than coming back from a POST /runs.
  Future<void> _resumeRun(String runId) => _driveRun(
        ({required onRunId, required onProgress}) {
          onRunId(runId);
          return widget.weldService.resumeRun(runId, onProgress: onProgress);
        },
      );

  /// Discards an incomplete/failed run's progress and re-solves it from
  /// scratch with the same saved parameters, same run_id.
  Future<void> _restartRun(String runId) => _driveRun(
        ({required onRunId, required onProgress}) {
          onRunId(runId);
          return widget.weldService.restartRun(runId, onProgress: onProgress);
        },
      );

  /// Fetches every weld weld_service has ever staged (see GET /runs) and
  /// lets the user pick one to view, regardless of how it ended -- done,
  /// still running, cleanly paused, or abandoned by a crash. Selecting an
  /// entry reuses [_viewLastResult] to display it exactly like the
  /// startup-gate dialog's "View last result" action: a single best-effort
  /// fetch of whatever heightmap that run has, landing in the normal static
  /// 4-panel comparison view, read-only, no polling. Best-effort: a failure
  /// here just leaves the dropdown showing fewer entries, not worth
  /// interrupting the rest of the app over.
  Future<void> _loadRunHistory() async {
    try {
      final history = await widget.weldService.fetchRunHistory();
      if (!mounted) return;
      setState(() => _runHistory = history);
    } catch (_) {
      // leave whatever list we already had, if any.
    }
  }

  /// A non-resumable (crashed/force-quit/abandoned) run's dead end -- see
  /// IncompleteRun.resumable and _IncompleteRunTile. Does NOT go through
  /// _driveRun: there's nothing to poll, nothing "running", and no resume
  /// option -- just a single best-effort fetch of whatever partial
  /// heightmap snapshot the abandoned run left behind, landing directly in
  /// the normal static 4-panel comparison view, read-only.
  Future<void> _viewLastResult(String runId) async {
    final hm = await widget.weldService.fetchHeightmapIfAvailable(runId);
    if (!mounted) return;
    setState(() {
      _simulated = hm;
      _running = false;
      _stages = [];
      _solveProgress = null;
      _errorText = hm == null ? 'No snapshot was available for run $runId' : null;
    });
  }

  /// The one legitimate way to end a weld early in a way that's later
  /// resumable (see fluid's case_runner::pause_run) -- POSTs
  /// /runs/{run_id}/pause and awaits it settling (see
  /// WeldService.pauseRun). Deliberately does NOT itself flip `_running`
  /// or `_simulated`: the run/resume/restart poll already in flight (inside
  /// _driveRun, via WeldService's shared _pollUntilDone) now treats a
  /// transition to `incomplete` as terminal exactly like `done`, so that
  /// poll unwinds on its own the moment the pause takes effect -- this
  /// method only needs to track its own "pausing" flag so the button can't
  /// be double-pressed, and surface a pause-specific error (e.g. a timeout)
  /// if one occurs.
  bool _pausing = false;

  Future<void> _pauseRun() async {
    final runId = _currentRunId;
    if (runId == null || _pausing) return;
    setState(() => _pausing = true);
    try {
      await widget.weldService.pauseRun(runId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }

  /// Starts (or restarts) the periodic GET /runs/{run_id}/heightmap poll
  /// that keeps the ferrousFoam panel updating with live mid-solve snapshots
  /// -- separate from, and at a coarser interval than, the stage/status
  /// poll inside WeldService's run/resume/restart methods, since the two
  /// are fetching different things (progress metadata vs. the actual
  /// heightmap payload).
  void _startHeightmapPolling(String runId) {
    _heightmapPollTimer?.cancel();
    _currentRunId = runId;
    _heightmapPollTimer = Timer.periodic(_heightmapPollInterval, (_) async {
      final id = _currentRunId;
      if (id == null || !_running) return;
      final hm = await widget.weldService.fetchHeightmapIfAvailable(id);
      if (hm != null && mounted) {
        setState(() => _simulated = hm);
      }
    });
  }

  void _stopHeightmapPolling() {
    _heightmapPollTimer?.cancel();
    _heightmapPollTimer = null;
    _currentRunId = null;
  }

  @override
  void dispose() {
    _fastDebounce?.cancel();
    _heightmapPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pops up all 4 panels' depth profiles at [yMm], referenced to the flat
  /// plate surface -- the direct real-vs-predicted comparison a flat top-down
  /// color map or a tilted 3D view can only gesture at.
  void _showCrossSectionFlyout(double yMm) {
    final refZMin = [widget.emptyGroove.zMin, widget.weldedGroove.zMin].reduce((a, b) => a < b ? a : b);
    final refZMax = [widget.emptyGroove.zMax, widget.weldedGroove.zMax].reduce((a, b) => a > b ? a : b);
    final refDepthMin = _surfaceReferenceMm - refZMax;
    final refDepthMax = _surfaceReferenceMm - refZMin;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.45,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Cross-section at Y = ${yMm.toStringAsFixed(1)} mm',
                          style: Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: CrossSectionView(
                            title: 'Empty groove (no-tack scan)',
                            heightmap: widget.emptyGroove,
                            surfaceReferenceMm: _surfaceReferenceMm,
                            ySliceMm: yMm,
                            depthMinOverride: refDepthMin,
                            depthMaxOverride: refDepthMax,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CrossSectionView(
                            title: 'Real weld (ground truth)',
                            heightmap: widget.weldedGroove,
                            surfaceReferenceMm: _surfaceReferenceMm,
                            ySliceMm: yMm,
                            depthMinOverride: refDepthMin,
                            depthMaxOverride: refDepthMax,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CrossSectionView(
                            title: 'ferrousFoam prediction',
                            heightmap: _simulated,
                            surfaceReferenceMm: _surfaceReferenceMm,
                            ySliceMm: yMm,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CrossSectionView(
                            title: 'Fast model (weld_sim, live)',
                            heightmap: _fastResult?.heightmap,
                            surfaceReferenceMm: _surfaceReferenceMm,
                            ySliceMm: yMm,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
        // Wrapped in one scrolling row rather than a fixed-width actions
        // list -- this toolbar has grown a control at a time over the
        // course of the project (colormap, view mode, cross-section
        // picker, pause, cores, weld) and a fixed Row silently overflows
        // once it no longer fits the window, hiding whatever's off the
        // right edge. Scrolling degrades gracefully at any window width
        // instead of needing a fresh pixel-budget fix every time one more
        // control is added.
        actions: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: [
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
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SegmentedButton<ViewMode>(
                segments: const [
                  ButtonSegment(value: ViewMode.flat, label: Text('2D')),
                  ButtonSegment(value: ViewMode.rotatable, label: Text('3D')),
                ],
                selected: {_viewMode},
                onSelectionChanged: (s) => setState(() => _viewMode = s.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: IconButton(
                icon: const Icon(Icons.gps_fixed),
                tooltip: _pickingCrossSection
                    ? 'Cross-section picker on — tap any panel to inspect that slice'
                    : 'Pick a cross-section: tap any panel afterward to see all 4 depth profiles at that Y',
                color: _pickingCrossSection ? Theme.of(context).colorScheme.primary : null,
                style: _pickingCrossSection
                    ? IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                    : null,
                onPressed: () => setState(() => _pickingCrossSection = !_pickingCrossSection),
              ),
            ),
          ),
          if (_running)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _pausing ? null : _pauseRun,
                  icon: const Icon(Icons.pause),
                  label: Text(_pausing ? 'Pausing…' : 'Pause'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${parallelCoresLever.label} ${_params.parallelCores.round()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SizedBox(
                    width: 80,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _params.parallelCores.clamp(parallelCoresLever.min, parallelCoresLever.max),
                        min: parallelCoresLever.min,
                        max: parallelCoresLever.max,
                        divisions: (parallelCoresLever.max - parallelCoresLever.min).round(),
                        label: _params.parallelCores.round().toString(),
                        // Splits the solve when the NEXT weld starts, not
                        // something already running -- disabled mid-run so
                        // it can't look like it's doing something live.
                        onChanged: _running
                            ? null
                            : (v) => setState(() => _params.parallelCores = v.roundToDouble()),
                      ),
                    ),
                  ),
                ],
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
              ]),
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
              previousWelds: _runHistory,
              onSelectPreviousWeld: (entry) => _viewLastResult(entry.runId),
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
                          child: AdaptiveHeightmapView(
                            title: 'Empty groove (no-tack scan)',
                            heightmap: widget.emptyGroove,
                            colormap: _colormap,
                            viewMode: _viewMode,
                            zMinOverride: refZMin,
                            zMaxOverride: refZMax,
                            onPointPicked: _pickingCrossSection ? (x, y) => _showCrossSectionFlyout(y) : null,
                            showBackingPlate: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AdaptiveHeightmapView(
                            title: 'Real weld (tack scan, ground truth)',
                            heightmap: widget.weldedGroove,
                            colormap: _colormap,
                            viewMode: _viewMode,
                            zMinOverride: refZMin,
                            zMaxOverride: refZMax,
                            onPointPicked: _pickingCrossSection ? (x, y) => _showCrossSectionFlyout(y) : null,
                            showBackingPlate: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AdaptiveHeightmapView(
                            title: 'ferrousFoam prediction',
                            heightmap: _simulated,
                            colormap: _colormap,
                            viewMode: _viewMode,
                            loading: _running,
                            onPointPicked: _pickingCrossSection ? (x, y) => _showCrossSectionFlyout(y) : null,
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
                            viewMode: _viewMode,
                            onPointPicked: _pickingCrossSection ? (x, y) => _showCrossSectionFlyout(y) : null,
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
  final ViewMode viewMode;
  final void Function(double xMm, double yMm)? onPointPicked;

  const FastModelPanel({
    super.key,
    required this.heightmap,
    required this.outputs,
    required this.findings,
    required this.error,
    required this.colormap,
    required this.viewMode,
    this.onPointPicked,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AdaptiveHeightmapView(
            title: 'Fast model (weld_sim, live)',
            heightmap: heightmap,
            colormap: colormap,
            viewMode: viewMode,
            onPointPicked: onPointPicked,
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
