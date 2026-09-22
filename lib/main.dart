import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models/heightmap.dart';
import 'models/weld_parameters.dart';
import 'services/weld_service.dart';
import 'widgets/heightmap_view.dart';
import 'widgets/parameter_panel.dart';

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
      home: const WeldBenchHome(),
    );
  }
}

class WeldBenchHome extends StatefulWidget {
  const WeldBenchHome({super.key});

  @override
  State<WeldBenchHome> createState() => _WeldBenchHomeState();
}

class _WeldBenchHomeState extends State<WeldBenchHome> {
  final _params = WeldParameters();
  final _weldService = WeldService();

  Heightmap? _emptyGroove;
  Heightmap? _weldedGroove;
  Heightmap? _simulated;

  bool _running = false;
  String? _statusText;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
  }

  Future<void> _loadReferenceData() async {
    final emptyJson = await rootBundle.loadString('assets/reference/reference_empty_groove.json');
    final weldedJson = await rootBundle.loadString('assets/reference/reference_welded_groove.json');
    if (!mounted) return;
    setState(() {
      _emptyGroove = Heightmap.fromJsonString(emptyJson);
      _weldedGroove = Heightmap.fromJsonString(weldedJson);
    });
  }

  Future<void> _runWeld() async {
    setState(() {
      _running = true;
      _statusText = 'starting...';
      _errorText = null;
    });
    try {
      final result = await _weldService.runWeld(
        _params,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _statusText = status);
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
    _weldService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Share a z-range across the reference panels so their color scales are
    // directly comparable; the simulated panel gets its own scale until we
    // know it's on the same physical basis (it may run in a smaller/offset
    // local domain).
    double? refZMin, refZMax;
    if (_emptyGroove != null && _weldedGroove != null) {
      refZMin = [_emptyGroove!.zMin, _weldedGroove!.zMin].reduce((a, b) => a < b ? a : b);
      refZMax = [_emptyGroove!.zMax, _weldedGroove!.zMax].reduce((a, b) => a > b ? a : b);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('weldBench'),
        actions: [
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
                            heightmap: _emptyGroove,
                            zMinOverride: refZMin,
                            zMaxOverride: refZMax,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: HeightmapView(
                            title: 'Real weld (tack scan, ground truth)',
                            heightmap: _weldedGroove,
                            zMinOverride: refZMin,
                            zMaxOverride: refZMax,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: HeightmapView(
                            title: 'ferrousFoam prediction',
                            heightmap: _simulated,
                            loading: _running,
                            statusText: _statusText,
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
