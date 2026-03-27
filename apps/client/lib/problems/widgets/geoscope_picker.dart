import 'dart:async';

import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Shows a modal bottom sheet that lets the user drill into the geoscope
/// hierarchy (superstates → states → metro areas) and select one.
void showGeoscopePicker(BuildContext context) {
  final l10n = context.l10n;
  final geoscopeCubit = context.read<GeoscopeCubit>();
  final geoState = geoscopeCubit.state;
  const superstateIds = {'us', 'in', 'eu'};
  final allGeo = geoState.availableGeoscopes;
  final labelMap = {for (final g in allGeo) g.id: g.label};
  final superstates = allGeo
      .where((g) => superstateIds.contains(g.id))
      .toList();

  final activeParts = geoState.selectedGeoscope == '/'
      ? <String>[]
      : geoState.selectedGeoscope.split('/');
  String? selectedSuperstate;
  String? selectedCountry;
  if (activeParts.isNotEmpty) {
    final firstSeg = activeParts.first;
    if (superstateIds.contains(firstSeg)) {
      selectedSuperstate = firstSeg;
      if (activeParts.length >= 2) {
        selectedCountry = activeParts.sublist(0, 2).join('/');
      }
    } else if (activeParts.length >= 2) {
      selectedCountry = firstSeg;
    }
  }

  unawaited(
    showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            // Build States section.
            List<({String id, String label})> stateItems;
            if (selectedSuperstate != null) {
              final prefix = '$selectedSuperstate/';
              stateItems = allGeo
                  .where(
                    (g) =>
                        g.id.startsWith(prefix) && g.id.split('/').length == 2,
                  )
                  .toList();
            } else {
              final seen = <String>{};
              stateItems = [];
              for (final g in allGeo) {
                final firstSeg = g.id.split('/').first;
                if (!superstateIds.contains(firstSeg) && seen.add(firstSeg)) {
                  stateItems.add((
                    id: firstSeg,
                    label: labelMap[firstSeg] ?? firstSeg,
                  ));
                }
              }
            }

            // Build Metro areas section.
            List<({String id, String label})> metroItems;
            if (selectedCountry != null) {
              final prefix = '$selectedCountry/';
              metroItems = allGeo
                  .where((g) => g.id.startsWith(prefix))
                  .toList();
            } else if (selectedSuperstate != null) {
              final prefix = '$selectedSuperstate/';
              metroItems = allGeo
                  .where(
                    (g) =>
                        g.id.startsWith(prefix) && g.id.split('/').length >= 3,
                  )
                  .toList();
            } else {
              metroItems = allGeo.where((g) {
                final parts = g.id.split('/');
                return parts.length >= 3 ||
                    (parts.length == 2 && !superstateIds.contains(parts.first));
              }).toList();
            }

            final activeId = geoscopeCubit.state.selectedGeoscope;

            return ListView(
              children: [
                // Global option.
                ListTile(
                  title: Text('🌐 ${l10n.geoscopeGlobal}'),
                  trailing: activeId == '/' ? const Icon(Icons.check) : null,
                  onTap: () {
                    unawaited(geoscopeCubit.selectGeoscope('/'));
                    Navigator.of(context).pop();
                  },
                ),
                const Divider(),

                // Superstates header.
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    top: 8,
                    bottom: 4,
                  ),
                  child: Text(
                    'Superstates',
                    style: Theme.of(sheetContext).textTheme.labelSmall,
                  ),
                ),
                for (final s in superstates)
                  ListTile(
                    title: Text(s.label),
                    trailing: activeId == s.id
                        ? const Icon(Icons.check)
                        : selectedSuperstate == s.id
                        ? const Icon(Icons.expand_more)
                        : null,
                    onTap: () {
                      if (selectedSuperstate == s.id) {
                        setSheetState(() {
                          selectedSuperstate = null;
                          selectedCountry = null;
                        });
                        unawaited(geoscopeCubit.selectGeoscope('/'));
                      } else {
                        setSheetState(() {
                          if (selectedSuperstate != s.id) {
                            selectedCountry = null;
                          }
                          selectedSuperstate = s.id;
                        });
                        unawaited(geoscopeCubit.selectGeoscope(s.id));
                      }
                    },
                  ),

                // States section.
                if (stateItems.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      top: 8,
                      bottom: 4,
                    ),
                    child: Text(
                      'States',
                      style: Theme.of(sheetContext).textTheme.labelSmall,
                    ),
                  ),
                  for (final m in stateItems)
                    ListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 32,
                        right: 16,
                      ),
                      title: Text(m.label),
                      trailing: activeId == m.id
                          ? const Icon(Icons.check)
                          : selectedCountry == m.id
                          ? const Icon(Icons.expand_more)
                          : null,
                      onTap: () {
                        if (selectedCountry == m.id) {
                          setSheetState(() {
                            selectedCountry = null;
                          });
                          unawaited(
                            geoscopeCubit.selectGeoscope(
                              selectedSuperstate ?? '/',
                            ),
                          );
                        } else {
                          unawaited(
                            geoscopeCubit.selectGeoscope(m.id),
                          );
                          final hasMetro = allGeo.any(
                            (g) => g.id.startsWith('${m.id}/'),
                          );
                          if (hasMetro) {
                            setSheetState(() {
                              selectedCountry = m.id;
                            });
                          } else {
                            Navigator.of(context).pop();
                          }
                        }
                      },
                    ),
                ],

                // Metro areas section.
                if (metroItems.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      top: 8,
                      bottom: 4,
                    ),
                    child: Text(
                      'Metro areas',
                      style: Theme.of(sheetContext).textTheme.labelSmall,
                    ),
                  ),
                  for (final b in metroItems)
                    ListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 48,
                        right: 16,
                      ),
                      title: Text(b.label),
                      trailing: activeId == b.id
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        if (activeId == b.id) {
                          unawaited(
                            geoscopeCubit.selectGeoscope(
                              selectedCountry ?? selectedSuperstate ?? '/',
                            ),
                          );
                          setSheetState(() {});
                        } else {
                          unawaited(
                            geoscopeCubit.selectGeoscope(b.id),
                          );
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                ],
              ],
            );
          },
        );
      },
    ),
  );
}
