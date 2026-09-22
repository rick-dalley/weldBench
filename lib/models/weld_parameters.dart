/// The process parameters exposed as "levers" in the UI.
///
/// `modeled` marks whether ferrousFoam's current physics actually responds to
/// this parameter yet. Its VOF solver models: a moving/stationary Gaussian
/// surface heat flux, Marangoni convection, buoyancy, phase change, and
/// recoil vapor pressure. It does NOT currently model arc plasma physics,
/// shielding gas coverage/turbulence, or ambient atmospheric effects beyond a
/// simple ambient temperature boundary condition. Parameters marked
/// `modeled: false` are shown in the UI (because they matter for matching
/// real shop practice) but currently have no effect on the simulation --
/// changing them won't change ferrousFoam's output until the solver is
/// extended.
enum Polarity { dcep, dcen, ac }

enum WireMaterial { mildSteel, stainlessSteel, aluminum }

enum ShieldingGas { argon, co2, argonCo2Mix, argonHeliumMix }

class WeldParameters {
  // Electrical
  double voltageV;
  Polarity polarity;

  // Wire / deposition
  double wireFeedSpeedMPerMin;
  double wireDiameterMm;
  WireMaterial wireMaterial;
  ShieldingGas shieldingGas;

  // Torch kinematics
  double travelSpeedMmPerS;
  double travelAngleDeg;
  double workAngleDeg;
  double contactTipToWorkDistanceMm;

  // Environment
  double ambientTemperatureC;
  double humidityPct;
  double atmosphericPressureKPa;

  // Weld window
  double weldDurationMs;

  WeldParameters({
    this.voltageV = 22.0,
    this.polarity = Polarity.dcep,
    this.wireFeedSpeedMPerMin = 5.0,
    this.wireDiameterMm = 1.2,
    this.wireMaterial = WireMaterial.mildSteel,
    this.shieldingGas = ShieldingGas.argonCo2Mix,
    this.travelSpeedMmPerS = 0.0, // 0 = stationary tack weld
    this.travelAngleDeg = 0.0,
    this.workAngleDeg = 0.0,
    this.contactTipToWorkDistanceMm = 12.0,
    this.ambientTemperatureC = 20.0,
    this.humidityPct = 50.0,
    this.atmosphericPressureKPa = 101.3,
    this.weldDurationMs = 250.0,
  });

  Map<String, dynamic> toJson() => {
        'voltage_v': voltageV,
        'polarity': polarity.name,
        'wire_feed_speed_m_per_min': wireFeedSpeedMPerMin,
        'wire_diameter_mm': wireDiameterMm,
        'wire_material': wireMaterial.name,
        'shielding_gas': shieldingGas.name,
        'travel_speed_mm_per_s': travelSpeedMmPerS,
        'travel_angle_deg': travelAngleDeg,
        'work_angle_deg': workAngleDeg,
        'contact_tip_to_work_distance_mm': contactTipToWorkDistanceMm,
        'ambient_temperature_c': ambientTemperatureC,
        'humidity_pct': humidityPct,
        'atmospheric_pressure_kpa': atmosphericPressureKPa,
        'weld_duration_ms': weldDurationMs,
      };
}

class LeverSpec {
  final String label;
  final String unit;
  final double min;
  final double max;
  final bool modeled;
  final double Function(WeldParameters) get;
  final void Function(WeldParameters, double) set;

  /// Optional small line of extra context shown under the slider (e.g. a
  /// derived value the user should know but that isn't itself a lever).
  final String Function(WeldParameters)? extraHint;

  const LeverSpec({
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.modeled,
    required this.get,
    required this.set,
    this.extraHint,
  });
}

/// Continuous levers, grouped for display. Categorical fields (polarity,
/// wire material, shielding gas) are handled separately as dropdowns.
final List<MapEntry<String, List<LeverSpec>>> leverGroups = [
  MapEntry('Electrical', [
    LeverSpec(
      label: 'Voltage',
      unit: 'V',
      min: 10,
      max: 40,
      modeled: true,
      get: (p) => p.voltageV,
      set: (p, v) => p.voltageV = v,
    ),
  ]),
  MapEntry('Wire / deposition', [
    LeverSpec(
      label: 'Wire feed speed',
      unit: 'm/min',
      min: 1,
      max: 20,
      modeled: true,
      get: (p) => p.wireFeedSpeedMPerMin,
      set: (p, v) => p.wireFeedSpeedMPerMin = v,
    ),
    LeverSpec(
      label: 'Wire diameter',
      unit: 'mm',
      min: 0.6,
      max: 2.4,
      modeled: true,
      get: (p) => p.wireDiameterMm,
      set: (p, v) => p.wireDiameterMm = v,
    ),
  ]),
  MapEntry('Torch kinematics', [
    LeverSpec(
      label: 'Travel speed',
      unit: 'mm/s',
      min: 0,
      max: 15,
      modeled: true,
      get: (p) => p.travelSpeedMmPerS,
      set: (p, v) => p.travelSpeedMmPerS = v,
    ),
    LeverSpec(
      label: 'Travel angle',
      unit: 'deg',
      min: -30,
      max: 30,
      modeled: true,
      get: (p) => p.travelAngleDeg,
      set: (p, v) => p.travelAngleDeg = v,
    ),
    LeverSpec(
      label: 'Work angle',
      unit: 'deg',
      min: -45,
      max: 45,
      modeled: true,
      get: (p) => p.workAngleDeg,
      set: (p, v) => p.workAngleDeg = v,
    ),
    LeverSpec(
      label: 'Contact tip to work distance',
      unit: 'mm',
      min: 6,
      max: 25,
      modeled: true,
      get: (p) => p.contactTipToWorkDistanceMm,
      set: (p, v) => p.contactTipToWorkDistanceMm = v,
    ),
  ]),
  MapEntry('Environment (not yet modeled by ferrousFoam)', [
    LeverSpec(
      label: 'Ambient temperature',
      unit: '°C',
      min: -10,
      max: 45,
      modeled: true,
      get: (p) => p.ambientTemperatureC,
      set: (p, v) => p.ambientTemperatureC = v,
    ),
    LeverSpec(
      label: 'Humidity',
      unit: '%',
      min: 0,
      max: 100,
      modeled: false,
      get: (p) => p.humidityPct,
      set: (p, v) => p.humidityPct = v,
    ),
    LeverSpec(
      label: 'Atmospheric pressure',
      unit: 'kPa',
      min: 80,
      max: 105,
      modeled: false,
      get: (p) => p.atmosphericPressureKPa,
      set: (p, v) => p.atmosphericPressureKPa = v,
    ),
  ]),
  MapEntry('Weld window', [
    LeverSpec(
      label: 'Arc-on time',
      unit: 'ms',
      min: 50,
      max: 1000,
      modeled: true,
      get: (p) => p.weldDurationMs,
      set: (p, v) => p.weldDurationMs = v,
      // weld_service treats this as the arc-on dwell ("tshift"), then runs
      // for END_TIME_MULTIPLE_OF_DWELL (currently 3x, see fluid's
      // src/bin/weld_service/mapping.rs::estimate_timing) beyond it -- a
      // ramp-down plus a cooldown tail, so the pool actually finishes
      // solidifying before the run ends. The total simulated (and thus
      // wall-clock) time is that multiple, not this slider's raw value.
      extraHint: (p) => 'total simulated: ~${(p.weldDurationMs * 3).round()}ms (incl. ramp-down + cooldown)',
    ),
  ]),
];

/// Joint geometry (plate thickness, groove angle, root gap, root face) is
/// intentionally NOT an editable lever in this build: the current target is
/// a fixed real groove scan (assets/reference/reference_empty_groove.json),
/// so its geometry is given, not chosen. These become real levers once
/// ferrousFoam can generate a parametric groove instead of loading a scan.
const String lockedGeometryNote =
    'Plate thickness, groove angle, root gap, and root face are fixed by '
    'the loaded groove scan for this calibration target, not editable here.';
