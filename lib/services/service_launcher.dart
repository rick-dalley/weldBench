import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Starts (or reuses) the local `weld_service` Rust process so the user
/// never has to run it by hand in a separate terminal. Convenience only:
/// if something is already listening on the target port, we assume it's a
/// compatible weld_service instance and just use it, rather than spawning a
/// second one that would immediately fail to bind the port anyway.
class ServiceLauncher {
  final Uri baseUri;
  final http.Client _client;
  Process? _process;

  ServiceLauncher({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? Uri.parse('http://localhost:8787'),
        _client = client ?? http.Client();

  bool get startedByUs => _process != null;

  /// Ensures weld_service is reachable at [baseUri], spawning it from the
  /// sibling `fluid` checkout if nothing answers there yet. Completes once
  /// the service responds to a health check, or throws after [timeout].
  Future<void> ensureRunning({
    Duration timeout = const Duration(minutes: 2),
    void Function(String message)? onStatus,
  }) async {
    if (await _isReachable()) {
      onStatus?.call('weld_service already running at $baseUri, reusing it');
      return;
    }

    final fluidDir = _resolveFluidDir();
    onStatus?.call('starting weld_service from $fluidDir ...');

    final process = await Process.start(
      'cargo',
      ['run', '--bin', 'weld_service'],
      workingDirectory: fluidDir.path,
      environment: {
        // Keep this in sync with ServiceLauncher.baseUri's port if you ever
        // change the default -- both must agree on which port to use.
        'WELD_SERVICE_PORT': '${baseUri.port}',
      },
    );
    _process = process;

    // Surface the child's output with a prefix rather than swallowing it --
    // useful for diagnosing a stuck/failed CFD run without a separate
    // terminal.
    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((line) => stdout.write('[weld_service] $line'));
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((line) => stderr.write('[weld_service] $line'));

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isReachable()) {
        onStatus?.call('weld_service is up');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('weld_service did not become reachable at $baseUri within $timeout');
  }

  Future<bool> _isReachable() async {
    try {
      // Any HTTP response (even a 404 for a bogus run id) means the server
      // is up and routing; we don't care about the status code here.
      await _client.get(baseUri.resolve('/runs/__health_check__')).timeout(const Duration(seconds: 2));
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
    // Default layout on this machine: weldBench and fluid are sibling
    // checkouts (.../physics/weldBench, .../physics/fluid).
    return Directory('${Directory.current.parent.path}/fluid');
  }

  /// Kills the process we spawned, if any. Does nothing if we reused an
  /// already-running instance -- it's not ours to kill.
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    // Give it a moment to shut down cleanly before we move on; we don't
    // block app exit indefinitely on this.
    await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    _process = null;
  }

  void dispose() => _client.close();
}
