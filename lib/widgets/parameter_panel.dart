import 'package:flutter/material.dart';

import '../models/weld_parameters.dart';

/// The "levers": grouped sliders for continuous parameters and dropdowns for
/// categorical ones. Levers marked not-yet-modeled by ferrousFoam are shown
/// dimmed with a note, rather than hidden, so the UI is honest about current
/// solver fidelity without hiding parameters that matter for real practice.
class ParameterPanel extends StatelessWidget {
  final WeldParameters params;
  final VoidCallback onChanged;

  const ParameterPanel({super.key, required this.params, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Process parameters', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _dropdownTile<Polarity>(
          label: 'Polarity',
          value: params.polarity,
          items: Polarity.values,
          labelOf: (p) => p.name.toUpperCase(),
          onChanged: (v) {
            params.polarity = v;
            onChanged();
          },
        ),
        _dropdownTile<WireMaterial>(
          label: 'Wire material',
          value: params.wireMaterial,
          items: WireMaterial.values,
          labelOf: (m) => switch (m) {
            WireMaterial.mildSteel => 'Mild steel',
            WireMaterial.stainlessSteel => 'Stainless steel',
            WireMaterial.aluminum => 'Aluminum',
          },
          onChanged: (v) {
            params.wireMaterial = v;
            onChanged();
          },
        ),
        _dropdownTile<ShieldingGas>(
          label: 'Shielding gas',
          value: params.shieldingGas,
          items: ShieldingGas.values,
          labelOf: (g) => switch (g) {
            ShieldingGas.argon => 'Argon',
            ShieldingGas.co2 => 'CO₂',
            ShieldingGas.argonCo2Mix => 'Ar/CO₂ mix',
            ShieldingGas.argonHeliumMix => 'Ar/He mix',
          },
          onChanged: (v) {
            params.shieldingGas = v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        for (final group in leverGroups) ...[
          Text(group.key, style: Theme.of(context).textTheme.titleSmall),
          for (final lever in group.value) _leverTile(context, lever),
          const SizedBox(height: 12),
        ],
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            lockedGeometryNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _leverTile(BuildContext context, LeverSpec lever) {
    final value = lever.get(params).clamp(lever.min, lever.max);
    final color = lever.modeled ? null : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lever.label,
                  style: TextStyle(color: color),
                ),
              ),
              Text(
                '${value.toStringAsFixed(2)} ${lever.unit}',
                style: TextStyle(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              if (!lever.modeled)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Not yet modeled by ferrousFoam — has no effect on the simulation yet.',
                    child: Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
          Slider(
            value: value,
            min: lever.min,
            max: lever.max,
            activeColor: lever.modeled ? null : Colors.grey,
            onChanged: (v) {
              lever.set(params, v);
              onChanged();
            },
          ),
          if (lever.extraHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                lever.extraHint!(params),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dropdownTile<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required void Function(T) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<T>(
            value: value,
            items: [
              for (final item in items)
                DropdownMenuItem(value: item, child: Text(labelOf(item))),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
