import 'dart:convert';
import 'dart:io';

import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:server/src/db.dart';
import 'package:test/test.dart';

/// The Firestore emulator does not enforce composite indexes (per CLAUDE.md),
/// so e2e tests cannot catch index/query drift. This test instead parses
/// `firestore.indexes.json` and asserts that the StructuredQuery built by
/// [buildProblemsListingQuery] is served by at least one deployed index.
///
/// History: this exact bug shipped in May 2026 when the `hidden` field was
/// added to the client query (and indexes) but not to the server query — the
/// server's GET /api/problems returned 500 in prod for every caller. This
/// test would have caught it: the query's equality set was {solved} but no
/// index had `[solved, votes, __name__]` (every index had `hidden` between
/// `solved` and `votes`).
void main() {
  late Map<String, dynamic> indexesJson;

  setUpAll(() {
    final file = _findIndexesFile();
    indexesJson = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('listing query (no geoscope) matches a deployed problems index', () {
    final query = buildProblemsListingQuery(pageSize: 99);
    expect(
      _findMatchingIndex(indexesJson, 'problems', query),
      isNotNull,
      reason: _mismatchReason('GET /api/problems (no geoscope)', query),
    );
  });

  test('listing query (with geoscope) matches a deployed problems index', () {
    final query = buildProblemsListingQuery(pageSize: 99, geoscope: 'na/us');
    expect(
      _findMatchingIndex(indexesJson, 'problems', query),
      isNotNull,
      reason: _mismatchReason('GET /api/problems?geoscope=...', query),
    );
  });
}

String _mismatchReason(String label, fs.StructuredQuery query) {
  final orderBy = _orderByOf(
    query,
  ).map((o) => '${o.field?.fieldPath} ${o.direction}').toList();
  return 'No composite index in firestore.indexes.json serves the '
      '$label listing query. The query filters on '
      '${_equalityFieldsOf(query)} and orders by $orderBy.';
}

/// Locate `firestore.indexes.json` whether tests are run from the package
/// directory (`apps/server`) or the repo root.
File _findIndexesFile() {
  for (final path in const [
    '../../firestore.indexes.json',
    'firestore.indexes.json',
  ]) {
    final f = File(path);
    if (f.existsSync()) return f;
  }
  fail(
    'Could not locate firestore.indexes.json from ${Directory.current.path}',
  );
}

/// Returns the matching index entry, or null if no index serves [query].
///
/// Firestore composite-index matching (simplified): an index
/// `[f1, f2, ..., fk]` serves a query iff:
///   - the leading `n` fields are the query's equality filters (as a set),
///     where `n` = number of equality filters; and
///   - the remaining fields match the query's `orderBy` in order and direction.
Map<String, dynamic>? _findMatchingIndex(
  Map<String, dynamic> indexesJson,
  String collectionGroup,
  fs.StructuredQuery query,
) {
  final equality = _equalityFieldsOf(query);
  final orderBy = _orderByOf(query);
  final indexes = (indexesJson['indexes'] as List).cast<Map<String, dynamic>>();

  for (final index in indexes) {
    if (index['collectionGroup'] != collectionGroup) continue;
    final fields = (index['fields'] as List).cast<Map<String, dynamic>>();
    if (fields.length != equality.length + orderBy.length) continue;

    final prefix = fields.take(equality.length).toList();
    final prefixFieldNames = prefix
        .map((f) => f['fieldPath'] as String)
        .toSet();
    if (prefixFieldNames.length != equality.length) continue;
    if (!prefixFieldNames.containsAll(equality)) continue;

    var suffixMatches = true;
    for (var i = 0; i < orderBy.length; i++) {
      final indexField = fields[equality.length + i];
      final ob = orderBy[i];
      if (indexField['fieldPath'] != ob.field?.fieldPath) {
        suffixMatches = false;
        break;
      }
      if (indexField['order'] != ob.direction) {
        suffixMatches = false;
        break;
      }
    }
    if (suffixMatches) return index;
  }
  return null;
}

/// Walk the query's `where` clause and collect the set of field paths that
/// appear in EQUAL field-filters. Treats an OR over the same field (used for
/// the geoscope ancestor expansion) as a single equality on that field —
/// Firestore handles this with the same composite index it uses for `IN`.
Set<String> _equalityFieldsOf(fs.StructuredQuery query) {
  final fields = <String>{};
  final where = query.where;
  if (where != null) _walkFilter(where, fields);
  return fields;
}

void _walkFilter(fs.Filter filter, Set<String> equality) {
  final fieldFilter = filter.fieldFilter;
  if (fieldFilter != null && fieldFilter.op == 'EQUAL') {
    final path = fieldFilter.field?.fieldPath;
    if (path != null) equality.add(path);
    return;
  }
  final composite = filter.compositeFilter;
  if (composite != null) {
    for (final child in composite.filters ?? const <fs.Filter>[]) {
      _walkFilter(child, equality);
    }
  }
}

List<fs.Order> _orderByOf(fs.StructuredQuery query) =>
    query.orderBy ?? const <fs.Order>[];
