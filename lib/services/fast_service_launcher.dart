import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Starts (or reuses) the local `weld_fast_service` Rust process, same
/// pattern as `ServiceLauncher` does for `weld_service` (see that file) --
/// duplicated rather than shared/generalized, since the two services are
/// meant to stay independent (different binaries, different ports,
/// different failure modes: this one is fine to run without weld_service,
/// just with a less-precisely-calibrated groove -- see weld_fast_service's
/// calibration.rs).
class FastServiceLauncher {
  final Uri baseUri;
  final http.Client _client;
  Process? _process;

  FastServiceLauncher({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? Uri.parse('http://localhost:8788'),
        _client = client ?? http.Client();

  bool get startedByUs => _process != null;

  /// Ensures weld_fast_service is reachable at [baseUri], spawning it from
  /// the sibling `fluid` checkout if nothing answers there yet. Completes
  /// once the service responds to a health check, or throws after
  /// [timeout]. Much shorter timeout than weld_service's launcher -- this
  /// binary has nothing slow to do at startup (no multi-GB point clouds to
  /// parse), just a first-run `cargo build`.
  Future<void> ensureRunning({
    Duration timeout = const Duration(minutes: 2),
    void Function(String message)? onStatus,
  }) async {
    if (await _isReachable()) {
      onStatus?.call('weld_fast_service already running at $baseUri, reusing it');
      return;
    }

    final fluidDir = _resolveFluidDir();
    onStatus?.call('starting weld_fast_service from $fluidDir ...');

    final process = await Process.start(
      'cargo',
      ['run', '--bin', 'weld_fast_service'],
      workingDirectory: fluidDir.path,
      environment: {
        'WELD_FAST_SERVICE_PORT': '${baseUri.port}',
      },
    );
    _process = process;

    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((line) => stdout.write('[weld_fast_service] $line'));
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((line) => stderr.write('[weld_fast_service] $line'));

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isReachable()) {
        onStatus?.call('weld_fast_service is up');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('weld_fast_service did not become reachable at $baseUri within $timeout');
  }

  Future<bool> _isReachable() async {
    try {
      // weld_fast_service only exposes POST /predict; any response (even a
      // 404 for this bogus path) means the server is up and routing -- same
      // reachability-probe reasoning as ServiceLauncher's health check.
      await _client.get(baseUri.resolve('/__health_check__')).timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  Directory _resolveFluidDir() {
    final override = Platform.environment['WELD_SERVICE_DIR'];
    if (override != null && override.isNotEmpty) {
      return Directory(override);
    }
    return Directory('${Directory.current.parent.path}/fluid');
  }

  /// Kills the process we spawned, if any. Does nothing if we reused an
  /// already-running instance.
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    _process = null;
  }

  void dispose() => _client.close();
}
