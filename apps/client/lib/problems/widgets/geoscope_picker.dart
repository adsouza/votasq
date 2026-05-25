import 'dart:async';
import 'dart:math' as math;

import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Top-tier geoscope IDs — entities of global political/economic
/// significance whose constituents are worth listing as a separate picker
/// tier. Surfaced to users under the heading "Global regions"
/// (l10n key `geoscopeSuperstatesHeading`); `superstate` is the internal
/// codename, kept for backward-compatibility with existing code.
///
/// Mixed bag: 3 large countries (`us`, `in`, `cn`) and 4 regional
/// organizations (`eu` = European Union, `scm` = Mercosur / Mercado Común
/// del Sur, `sea` = ASEAN, `las` = League of Arab States). That's why the
/// level-2 "States" tier under each is heterogeneous: subnational
/// divisions under the countries, sovereign member states under the
/// regional orgs. See the @description on `geoscopeStatesHeading` in the
/// English ARB for the translator-facing version of this note.
const _superstateIds = {'us', 'in', 'eu', 'scm', 'sea', 'las', 'cn'};

/// Top-level metros only show megacities; drilling in lifts the threshold.
const _topLevelMetroPopulationThreshold = 10000000;

/// Shows a modal bottom sheet that lets the user drill into the geoscope
/// hierarchy (superstates → states → metro areas) or substring-filter the
/// flat list of all geoscopes. Returns a future that completes when the
/// sheet is dismissed.
Future<void> showGeoscopePicker(BuildContext context) {
  // Pre-measure the heading so the sheet widens on roomy displays to keep it
  // on a single line. On viewports narrower than the heading the constraint
  // is clamped by the screen anyway, so mobile keeps wrapping.
  final headingStyle = Theme.of(
    context,
  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold);
  final painter = TextPainter(
    text: TextSpan(
      text: context.l10n.geoscopePickerHeading,
      style: headingStyle,
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  // 16 px horizontal padding on each side of the heading inside the sheet.
  final desiredWidth = math.max<double>(painter.size.width + 32, 640);
  painter.dispose();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: desiredWidth),
    builder: (_) => const _GeoscopePickerSheet(),
  );
}

class _GeoscopePickerSheet extends StatefulWidget {
  const _GeoscopePickerSheet();

  @override
  State<_GeoscopePickerSheet> createState() => _GeoscopePickerSheetState();
}

class _GeoscopePickerSheetState extends State<_GeoscopePickerSheet> {
  final _filterController = TextEditingController();
  String _query = '';
  String? _selectedSuperstate;
  String? _selectedCountry;
  bool? _superstatesExpandedOverride;

  bool get _isSuperstatesSectionExpanded =>
      _superstatesExpandedOverride ?? (_selectedCountry == null);

  @override
  void initState() {
    super.initState();
    _filterController.addListener(_onQueryChanged);
    final activeId = context.read<GeoscopeCubit>().state.selectedGeoscope;
    final activeParts = activeId == '/'
        ? const <String>[]
        : activeId.split('/');
    if (activeParts.isNotEmpty) {
      final firstSeg = activeParts.first;
      if (_superstateIds.contains(firstSeg)) {
        _selectedSuperstate = firstSeg;
        if (activeParts.length >= 2) {
          _selectedCountry = activeParts.sublist(0, 2).join('/');
        }
      } else {
        // Non-superstate first segment — this is a country-tier scope like
        // `ca` (Canada) or `mx/mexico-city`. The synthesized state-tier row
        // for `firstSeg` is what carries the expand-marker.
        _selectedCountry = firstSeg;
      }
    }
  }

  @override
  void dispose() {
    _filterController
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final trimmed = _filterController.text.trim();
    if (trimmed != _query) {
      setState(() => _query = trimmed);
    }
  }

  void _select(String geoscope) {
    unawaited(context.read<GeoscopeCubit>().selectGeoscope(geoscope));
    Navigator.of(context).pop();
  }

  /// Tap handler for filter-mode results. Leaves dismiss as before; items with
  /// descendants instead drill into hierarchical mode focused on them so the
  /// user can still pick a child (e.g. a metro under a tapped state).
  void _handleFilteredTap(String id) {
    final geoCubit = context.read<GeoscopeCubit>();
    final allGeo = geoCubit.state.availableGeoscopes;
    final hasChildren = allGeo.any((g) => g.id.startsWith('$id/'));
    if (!hasChildren) {
      _select(id);
      return;
    }

    _filterController.clear();
    final parts = id.split('/');
    setState(() {
      _superstatesExpandedOverride = null;
      if (_superstateIds.contains(id)) {
        _selectedSuperstate = id;
        _selectedCountry = null;
      } else if (parts.length >= 2 && _superstateIds.contains(parts.first)) {
        _selectedSuperstate = parts.first;
        _selectedCountry = parts.sublist(0, 2).join('/');
      } else {
        // Non-superstate country (e.g. `mx`) — the synthesized state-tier row
        // for its first segment carries the expand-marker via _selectedCountry.
        _selectedSuperstate = null;
        _selectedCountry = parts.first;
      }
    });
    unawaited(geoCubit.selectGeoscope(id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<GeoscopeCubit, GeoscopeState>(
      listenWhen: (prev, curr) => prev.pendingToast != curr.pendingToast,
      listener: (context, state) {
        final toast = state.pendingToast;
        if (toast == null) return;
        final message = switch (toast) {
          GeoscopeToast.denied => l10n.geoscopeLocationDenied,
          GeoscopeToast.unavailable => l10n.geoscopeLocationUnavailable,
        };
        showErrorToast(message);
        context.read<GeoscopeCubit>().clearPendingToast();
      },
      buildWhen: (prev, curr) =>
          prev.locationStatus != curr.locationStatus ||
          prev.locationSuggestion != curr.locationSuggestion ||
          prev.locationDenied != curr.locationDenied ||
          prev.selectedGeoscope != curr.selectedGeoscope,
      builder: (context, state) {
        // The filter is only meaningful at the top of the hierarchy.
        // Drilling into a superstate or state disables the field; backing
        // out re-enables it.
        final filterEnabled =
            _selectedSuperstate == null && _selectedCountry == null;
        return Padding(
          // Keep the sheet's content above the on-screen keyboard while
          // typing.
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    l10n.geoscopePickerHeading,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _filterController,
                    enabled: filterEnabled,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.geoscopeFilterHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _filterController.clear,
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (!state.locationDenied) _buildLocationRow(context, state),
                Flexible(
                  child: _query.isEmpty
                      ? _buildHierarchical(context)
                      : _buildFiltered(context, _query.toLowerCase()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocationRow(BuildContext context, GeoscopeState state) {
    final l10n = context.l10n;
    final cubit = context.read<GeoscopeCubit>();

    if (state.locationSuggestion != null) {
      final suggestion = state.locationSuggestion!;
      final allGeo = state.availableGeoscopes;
      final match = allGeo.where((g) => g.id == suggestion.id).firstOrNull;
      final label = match?.label ?? suggestion.id;
      return ListTile(
        leading: const Icon(Icons.my_location),
        title: Text(label),
        subtitle: Text(
          l10n.geoscopeSuggestionDistance(suggestion.distanceKm.round()),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () async {
                await cubit.acceptLocationSuggestion();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(l10n.geoscopeSuggestionAccept),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: cubit.dismissLocationSuggestion,
            ),
          ],
        ),
      );
    }

    final isFetching = state.locationStatus == GeoscopeLocationStatus.fetching;
    return ListTile(
      leading: isFetching
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location),
      title: Text(l10n.geoscopeUseMyLocation),
      onTap: isFetching
          ? null
          : () async {
              final before = cubit.state.selectedGeoscope;
              await cubit.selectNearestMetroFromLocation();
              final after = cubit.state.selectedGeoscope;
              if (before != after && context.mounted) {
                Navigator.of(context).pop();
              }
            },
    );
  }

  Widget _buildFiltered(BuildContext context, String queryLower) {
    final l10n = context.l10n;
    final geoCubit = context.read<GeoscopeCubit>();
    final allGeo = geoCubit.state.availableGeoscopes;
    final activeId = geoCubit.state.selectedGeoscope;

    final matches = allGeo
        .where((g) => g.label.toLowerCase().contains(queryLower))
        .toList();
    final includeGlobal = l10n.geoscopeGlobal.toLowerCase().contains(
      queryLower,
    );

    if (!includeGlobal && matches.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView(
      shrinkWrap: true,
      children: [
        if (includeGlobal)
          ListTile(
            title: Text('🌐 ${l10n.geoscopeGlobal}'),
            trailing: activeId == '/' ? const Icon(Icons.check) : null,
            onTap: () => _select('/'),
          ),
        for (final g in matches)
          ListTile(
            title: Text(g.label),
            trailing: activeId == g.id ? const Icon(Icons.check) : null,
            onTap: () => _handleFilteredTap(g.id),
          ),
      ],
    );
  }

  Widget _buildHierarchical(BuildContext context) {
    final l10n = context.l10n;
    final geoCubit = context.read<GeoscopeCubit>();
    final allGeo = geoCubit.state.availableGeoscopes;
    final activeId = geoCubit.state.selectedGeoscope;
    final labelMap = {for (final g in allGeo) g.id: g.label};
    final superstates = allGeo
        .where((g) => _superstateIds.contains(g.id))
        .toList();

    // Build States section.
    List<({String id, String label, int population, double? lat, double? lng})>
    stateItems;
    if (_selectedSuperstate != null) {
      final prefix = '$_selectedSuperstate/';
      stateItems = allGeo
          .where(
            (g) => g.id.startsWith(prefix) && g.id.split('/').length == 2,
          )
          .toList();
    } else {
      // Walking allGeo in population-desc order ensures the first hit
      // per firstSeg wins. The retained population is therefore the
      // largest known for that prefix — either the country-level
      // geoscope itself (if present) or its biggest sub-region.
      final seen = <String>{};
      stateItems = [];
      for (final g in allGeo) {
        final firstSeg = g.id.split('/').first;
        if (!_superstateIds.contains(firstSeg) && seen.add(firstSeg)) {
          stateItems.add((
            id: firstSeg,
            label: labelMap[firstSeg] ?? firstSeg,
            population: g.population,
            lat: null,
            lng: null,
          ));
        }
      }
    }

    // Build Metro areas section. When no superstate or state is selected,
    // the unfiltered list is enormous, so restrict to megacities. Drilling
    // into a region removes the threshold.
    List<({String id, String label, int population, double? lat, double? lng})>
    metroItems;
    if (_selectedCountry != null) {
      final prefix = '$_selectedCountry/';
      metroItems = allGeo.where((g) => g.id.startsWith(prefix)).toList();
    } else if (_selectedSuperstate != null) {
      final prefix = '$_selectedSuperstate/';
      metroItems = allGeo
          .where(
            (g) => g.id.startsWith(prefix) && g.id.split('/').length >= 3,
          )
          .toList();
    } else {
      metroItems = allGeo.where((g) {
        final parts = g.id.split('/');
        final isMetro =
            parts.length >= 3 ||
            (parts.length == 2 && !_superstateIds.contains(parts.first));
        return isMetro && g.population >= _topLevelMetroPopulationThreshold;
      }).toList();
    }

    return ListView(
      shrinkWrap: true,
      children: [
        // Global option.
        ListTile(
          title: Text('🌐 ${l10n.geoscopeGlobal}'),
          trailing: activeId == '/' ? const Icon(Icons.check) : null,
          onTap: () => _select('/'),
        ),
        const Divider(),
        InkWell(
          onTap: () {
            setState(() {
              _superstatesExpandedOverride = !_isSuperstatesSectionExpanded;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.geoscopeSuperstatesHeading,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Icon(
                  _isSuperstatesSectionExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (_isSuperstatesSectionExpanded)
          for (final s in superstates)
            ListTile(
              title: Text(s.label),
              trailing: activeId == s.id
                  ? const Icon(Icons.check)
                  : _selectedSuperstate == s.id
                  ? const Icon(Icons.expand_more)
                  : null,
              onTap: () {
                if (_selectedSuperstate == s.id) {
                  setState(() {
                    _selectedSuperstate = null;
                    _selectedCountry = null;
                    _superstatesExpandedOverride = null;
                  });
                  unawaited(geoCubit.selectGeoscope('/'));
                } else {
                  setState(() {
                    if (_selectedSuperstate != s.id) {
                      _selectedCountry = null;
                    }
                    _selectedSuperstate = s.id;
                    _superstatesExpandedOverride = null;
                  });
                  unawaited(geoCubit.selectGeoscope(s.id));
                }
              },
            ),

        // States section.
        if (stateItems.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text(
              l10n.geoscopeStatesHeading,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          for (final m in stateItems)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              title: Text(m.label),
              trailing: activeId == m.id
                  ? const Icon(Icons.check)
                  : _selectedCountry == m.id
                  ? const Icon(Icons.expand_more)
                  : null,
              onTap: () {
                if (_selectedCountry == m.id) {
                  setState(() {
                    _selectedCountry = null;
                    _superstatesExpandedOverride = null;
                  });
                  unawaited(
                    geoCubit.selectGeoscope(_selectedSuperstate ?? '/'),
                  );
                } else {
                  unawaited(geoCubit.selectGeoscope(m.id));
                  final hasMetro = allGeo.any(
                    (g) => g.id.startsWith('${m.id}/'),
                  );
                  if (hasMetro) {
                    setState(() {
                      _selectedCountry = m.id;
                      _superstatesExpandedOverride = null;
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
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text(
              l10n.geoscopeMetroAreasHeading,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          for (final b in metroItems)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 48, right: 16),
              title: Text(b.label),
              trailing: activeId == b.id ? const Icon(Icons.check) : null,
              onTap: () {
                if (activeId == b.id) {
                  unawaited(
                    geoCubit.selectGeoscope(
                      _selectedCountry ?? _selectedSuperstate ?? '/',
                    ),
                  );
                  setState(() {});
                } else {
                  unawaited(geoCubit.selectGeoscope(b.id));
                  Navigator.of(context).pop();
                }
              },
            ),
        ],
      ],
    );
  }
}
