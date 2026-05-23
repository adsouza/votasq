// CI drift-detection between the Dart notification payload schema and the
// hand-rolled TypeScript interfaces in functions/src/lib/types.ts.
//
// How it works:
//   1. This test builds one instance of each NotificationPayload variant.
//   2. Each is serialized via Freezed's `toJson` to capture the canonical
//      Dart-side JSON shape.
//   3. The JSON is emitted as a TypeScript object literal with an
//      `as const satisfies Record<string, NotificationPayload>` clause and
//      written to
//      functions/src/lib/notification_payload_fixtures.generated.ts.
//   4. `tsc --noEmit` (already part of `npm run typecheck`) then enforces
//      the contract: if Dart adds, removes, or renames a field, the literal
//      stops satisfying the union and tsc fails — surfacing drift in CI
//      before it can ship.
//
// To regenerate after intentional Dart schema changes:
//
//   SYNC_TS_FIXTURES=1 dart test packages/shared/test/src/models/notification_ts_fixture_test.dart
//
// Then commit the regenerated .generated.ts diff.

import 'dart:io';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

Map<String, NotificationPayload> _fixtures() => {
  'voteReceived': const NotificationPayload.voteReceived(
    problemId: 'p1',
    actorUid: 'u1',
  ),
  'problemForked': const NotificationPayload.problemForked(
    originalProblemId: 'orig',
    forkProblemId: 'fork',
    actorUid: 'u1',
  ),
  'problemLinkedUntyped': const NotificationPayload.problemLinked(
    linkedProblemId: 'linked',
    linkerProblemId: 'linker',
    actorUid: 'u1',
  ),
  'problemLinkedSpecialization': const NotificationPayload.problemLinked(
    linkedProblemId: 'linked',
    linkerProblemId: 'linker',
    actorUid: 'u1',
    kind: ProblemLinkKind.specialization,
  ),
  'problemLinkedGeneralization': const NotificationPayload.problemLinked(
    linkedProblemId: 'linked',
    linkerProblemId: 'linker',
    actorUid: 'u1',
    kind: ProblemLinkKind.generalization,
  ),
  'problemRevised': const NotificationPayload.problemRevised(
    problemId: 'p1',
    newVersion: 3,
  ),
  'forkAdopted': const NotificationPayload.forkAdopted(
    forkProblemId: 'fork',
    originalProblemId: 'orig',
    newVersion: 2,
  ),
};

String _generateTsFile() {
  final buf = StringBuffer()
    ..writeln(
      '// GENERATED — DO NOT EDIT BY HAND.',
    )
    ..writeln('//')
    ..writeln(
      '// Source: packages/shared/test/src/models/notification_ts_fixture_test.dart',
    )
    ..writeln('//')
    ..writeln('// Regenerate after intentional Dart schema changes via:')
    ..writeln(
      '//   SYNC_TS_FIXTURES=1 dart test packages/shared/test/src/models/notification_ts_fixture_test.dart',
    )
    ..writeln('//')
    ..writeln('// Drift invariant: `tsc --noEmit` type-checks the')
    ..writeln('// `satisfies NotificationPayload` clause below. If Dart adds,')
    ..writeln(
      '// removes, or renames a field, the literal stops satisfying the',
    )
    ..writeln('// union and tsc fails. CI surfaces drift before it ships.')
    ..writeln()
    ..writeln("import type {NotificationPayload} from './types';")
    ..writeln()
    ..writeln('export const notificationPayloadFixtures = {');
  for (final entry in _fixtures().entries) {
    buf.writeln('  ${entry.key}: ${_toTsLiteral(entry.value.toJson(), 2)},');
  }
  buf.writeln(
    '} as const satisfies Record<string, NotificationPayload>;',
  );
  return buf.toString();
}

String _toTsLiteral(Map<String, dynamic> json, int indent) {
  if (json.isEmpty) return '{}';
  final pad = ' ' * (indent + 2);
  final closePad = ' ' * indent;
  final entries = <String>[];
  for (final entry in json.entries) {
    entries.add('$pad${entry.key}: ${_tsValue(entry.value, indent + 2)},');
  }
  return '{\n${entries.join('\n')}\n$closePad}';
}

String _tsValue(dynamic v, int indent) {
  if (v == null) return 'null';
  if (v is String) {
    final escaped = v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return "'$escaped'";
  }
  if (v is num) return v.toString();
  if (v is bool) return v.toString();
  if (v is Map) {
    return _toTsLiteral(v.cast<String, dynamic>(), indent);
  }
  throw UnsupportedError(
    'notification_ts_fixture: unsupported value type ${v.runtimeType}',
  );
}

void main() {
  test(
    'functions/.../notification_payload_fixtures.generated.ts mirrors Dart toJson',
    () async {
      final expected = _generateTsFile();
      // dart test sets CWD to the package directory. Resolve from
      // packages/shared → repo root → functions/src/lib.
      final file = File(
        '../../functions/src/lib/notification_payload_fixtures.generated.ts',
      );

      if (Platform.environment['SYNC_TS_FIXTURES'] == '1') {
        await file.parent.create(recursive: true);
        await file.writeAsString(expected);
        stdout.writeln('Wrote ${file.path}');
        return;
      }

      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Missing ${file.path}. Generate it via:\n'
            '  SYNC_TS_FIXTURES=1 dart test packages/shared/test/src/models/notification_ts_fixture_test.dart',
      );
      final actual = await file.readAsString();
      expect(
        actual,
        equals(expected),
        reason:
            'TS notification fixture is out of date. Regenerate via:\n'
            '  SYNC_TS_FIXTURES=1 dart test packages/shared/test/src/models/notification_ts_fixture_test.dart\n'
            'Then commit the regenerated diff.',
      );
    },
  );
}
