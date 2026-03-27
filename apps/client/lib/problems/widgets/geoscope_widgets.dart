import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared/shared.dart';

/// Resolve a geoscope ID to its human-readable label using the available
/// geoscopes from [GeoscopeCubit]. Falls back to the last path segment
/// in upper case when no match is found.
String geoscopeLabel(BuildContext context, String geoscope) {
  if (geoscope == '/') return '🌐 ${context.l10n.geoscopeGlobal}';
  final available = context.read<GeoscopeCubit>().state.availableGeoscopes;
  for (final g in available) {
    if (g.id == geoscope) return g.label;
  }
  return geoscope.split('/').last.toUpperCase();
}

/// Build a geoscope dropdown for the given [geoscope] value.
/// [currentValue] is the currently selected ID, [onChanged] is called when
/// the user picks a new level. Returns an empty list if the geoscope is
/// global (`"/"`), hiding the dropdown entirely.
List<Widget> buildGeoscopeDropdown(
  BuildContext context, {
  required String geoscope,
  required String currentValue,
  required ValueChanged<String> onChanged,
  bool enabled = true,
  bool compact = true,
}) {
  if (geoscope == '/') return [];
  final l10n = context.l10n;
  final geoState = context.read<GeoscopeCubit>().state;
  final ancestorIds = geoscopeAncestors(geoscope).reversed.toList();
  final labelMap = {
    for (final g in geoState.availableGeoscopes) g.id: g.label,
  };

  final items = ancestorIds.map((id) {
    final label = id == '/'
        ? '🌐 ${l10n.geoscopeGlobal}'
        : (labelMap[id] ?? id.split('/').last.toUpperCase());
    return DropdownMenuItem(value: id, child: Text(label));
  }).toList();

  // If currentValue isn't in the ancestor list (e.g. problem was created
  // under a different geoscope), fall back to the most granular ancestor.
  final effectiveValue = ancestorIds.contains(currentValue)
      ? currentValue
      : ancestorIds.first;

  return [
    const SizedBox(width: 8),
    Tooltip(
      message: l10n.geoscopeDropdownTooltip,
      child: DropdownButton<String>(
        value: effectiveValue,
        menuWidth: 240,
        items: items,
        selectedItemBuilder: (_) => ancestorIds.map((id) {
          if (compact) {
            if (id == '/') return const Text('🌐');
            return Text(id.split('/').last);
          }
          final label = id == '/'
              ? '🌐 ${l10n.geoscopeGlobal}'
              : (labelMap[id] ?? id);
          return Text(label);
        }).toList(),
        onChanged: enabled
            ? (value) {
                if (value == null) return;
                onChanged(value);
              }
            : null,
      ),
    ),
  ];
}
