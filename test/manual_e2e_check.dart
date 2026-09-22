// Not part of the normal test suite (no `flutter_test` import, run via
// `dart run test/manual_e2e_check.dart`) -- a real, non-mocked exercise of
// the auto-start feature: spawn weld_service for real, fetch real reference
// data from real PLY files, confirm it's actually usable, then confirm the
// "reuse if already running" path works too.
import 'package:weld_bench/services/service_launcher.dart';
import 'package:weld_bench/services/weld_service.dart';

Future<void> main() async {
  final launcher = ServiceLauncher();
  final weldService = WeldService();

  print('--- first ensureRunning() call (expect: spawns weld_service) ---');
  await launcher.ensureRunning(onStatus: print);
  print('startedByUs: ${launcher.startedByUs}');
  if (!launcher.startedByUs) {
    throw StateError('expected to have spawned weld_service, but startedByUs is false');
  }

  print('--- fetching real reference scans ---');
  final empty = await weldService.fetchEmptyGrooveReference();
  final welded = await weldService.fetchWeldedGrooveReference();
  print('empty groove: ${empty.nx}x${empty.ny}, z in [${empty.zMin}, ${empty.zMax}]');
  print('welded groove: ${welded.nx}x${welded.ny}, z in [${welded.zMin}, ${welded.zMax}]');

  print('--- second launcher, ensureRunning() again (expect: reuses existing) ---');
  final launcher2 = ServiceLauncher();
  await launcher2.ensureRunning(onStatus: print);
  print('startedByUs (should be false, reused): ${launcher2.startedByUs}');
  if (launcher2.startedByUs) {
    throw StateError('expected to reuse the already-running instance, but it spawned a new one');
  }

  print('--- stopping the one we started ---');
  await launcher.stop();
  print('OK: full auto-start / reuse / stop cycle verified.');
}
