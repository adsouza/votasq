// One-shot backfill: writes canonical lat/lng to metro docs in the
// `geoscopes` collection. Idempotent — re-running overwrites with the
// same values. Uses an update_mask so existing fields (id, label,
// population) are preserved.
//
// Usage (run from `apps/server/`):
//   # Emulator:
//   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8081
//   dart run tool/seed_geoscope_coords.dart --emulator [--dry-run]
//
//   # Production (explicit opt-in, no default):
//   gcloud auth application-default login
//   gcloud auth application-default set-quota-project votasq
//   dart run tool/seed_geoscope_coords.dart --prod [--dry-run]

import 'dart:io';

import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:http/http.dart' as http;

const _scopes = <String>[FirestoreApi.datastoreScope];
const _projectId = 'votasq';

/// Document id (the doc name in the `geoscopes` collection) → lat/lng.
/// Per spec, only METRO docs get coords — supranationals (eu/sea/cn/...),
/// countries, and states do NOT, because a single point can't meaningfully
/// represent them and `findNearestMetro` is intentionally metros-only.
/// Coords are city-centre / metro centroid in WGS84 decimal degrees.
/// References noted in comments so a reviewer can sanity-check.
const _coords = <String, ({double lat, double lng})>{
  // North America metros
  'sfbay': (lat: 37.7793, lng: -122.4193), // SF City Hall
  'socal': (lat: 34.0522, lng: -118.2437), // Downtown LA
  'nyc': (lat: 40.7128, lng: -74.0060), // Manhattan
  'chicago': (lat: 41.8781, lng: -87.6298), // The Loop
  'atlanta': (lat: 33.7490, lng: -84.3880), // Downtown Atlanta
  'miami': (lat: 25.7617, lng: -80.1918), // Downtown Miami
  'philly': (lat: 39.9526, lng: -75.1652), // Center City
  'dc': (lat: 38.9072, lng: -77.0369), // Washington DC, Capitol
  'gta': (lat: 43.6532, lng: -79.3832), // Greater Toronto, downtown
  'cdmx': (lat: 19.4326, lng: -99.1332), // Mexico City, Zócalo

  // South America metros
  'ba': (lat: -34.6037, lng: -58.3816), // Buenos Aires centre
  'sãopaulo': (lat: -23.5505, lng: -46.6333), // São Paulo centre
  'rio': (lat: -22.9068, lng: -43.1729), // Rio centre
  'bogota': (lat: 4.7110, lng: -74.0721), // Bogotá centre
  'lima': (lat: -12.0464, lng: -77.0428), // Lima centre

  // Europe metros
  'paris': (lat: 48.8566, lng: 2.3522), // Île-de-la-Cité
  'berlin': (lat: 52.5200, lng: 13.4050), // Brandenburg Gate
  'rome': (lat: 41.9028, lng: 12.4964), // Colosseum
  'madrid': (lat: 40.4168, lng: -3.7038), // Puerta del Sol
  'london': (lat: 51.5074, lng: -0.1278), // Charing Cross
  'athens': (lat: 37.9838, lng: 23.7275), // Acropolis

  // India metros
  'mumbai': (lat: 19.0760, lng: 72.8777),
  'delhi': (lat: 28.7041, lng: 77.1025),
  'bengaluru': (lat: 12.9716, lng: 77.5946),
  'hyderabad': (lat: 17.3850, lng: 78.4867),
  'chennai': (lat: 13.0827, lng: 80.2707),
  'kolkata': (lat: 22.5726, lng: 88.3639),
  'ahmedabad': (lat: 23.0225, lng: 72.5714),
  'pune': (lat: 18.5204, lng: 73.8567),
  'surat': (lat: 21.1702, lng: 72.8311),
  'jaipur': (lat: 26.9124, lng: 75.7873),
  'kanpur': (lat: 26.4499, lng: 80.3319),
  'lucknow': (lat: 26.8467, lng: 80.9462),

  // China metros (Guangdong omitted — it's a province, ~127M people,
  // a single point can't represent it)
  'beijing': (lat: 39.9042, lng: 116.4074),
  'shanghai': (lat: 31.2304, lng: 121.4737),
  'hongkong': (lat: 22.3193, lng: 114.1694),

  // Japan metro
  'tokyo': (lat: 35.6762, lng: 139.6503),

  // SE Asia metros
  'singapore': (lat: 1.3521, lng: 103.8198), // city-state, doubles as metro
  'jakarta': (lat: -6.2088, lng: 106.8456),
  'krungthep': (lat: 13.7563, lng: 100.5018), // Bangkok
  'manila': (lat: 14.5995, lng: 120.9842),
  'hanoi': (lat: 21.0285, lng: 105.8542),
  'hochiminh': (lat: 10.8231, lng: 106.6297),

  // West / South Asia metros
  'karachi': (lat: 24.8607, lng: 67.0011),
  'dhaka': (lat: 23.8103, lng: 90.4125),
  'istanbul': (lat: 41.0082, lng: 28.9784),
  'jeddah': (lat: 21.4858, lng: 39.1925),
  'riyadh': (lat: 24.7136, lng: 46.6753),

  // Africa metros
  'cairo': (lat: 30.0444, lng: 31.2357),
  'alexandria': (lat: 31.2001, lng: 29.9187),
  'lagos': (lat: 6.5244, lng: 3.3792),
};

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final emulator = args.contains('--emulator');
  final prod = args.contains('--prod');

  if (!emulator && !prod) {
    stderr.writeln(
      'Specify --emulator or --prod. See file header for usage.',
    );
    exit(2);
  }
  if (emulator && prod) {
    stderr.writeln('Cannot specify both --emulator and --prod.');
    exit(2);
  }

  http.Client client;
  String? rootUrl;
  if (emulator) {
    final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
    if (host == null || host.isEmpty) {
      stderr.writeln(
        'FIRESTORE_EMULATOR_HOST must be set when using --emulator '
        '(e.g. 127.0.0.1:8081).',
      );
      exit(2);
    }
    client = _EmulatorOwnerClient(http.Client());
    rootUrl = 'http://$host/';
  } else {
    client = await auth_io.clientViaApplicationDefaultCredentials(
      scopes: _scopes,
    );
  }

  final api = rootUrl == null
      ? FirestoreApi(client)
      : FirestoreApi(client, rootUrl: rootUrl);

  const databasePath = 'projects/$_projectId/databases/(default)';
  const base = '$databasePath/documents';

  var updated = 0;
  try {
    for (final entry in _coords.entries) {
      final docId = entry.key;
      final lat = entry.value.lat;
      final lng = entry.value.lng;
      final docName = '$base/geoscopes/$docId';
      stdout.writeln(
        'doc=$docId lat=$lat lng=$lng dryRun=$dryRun',
      );
      if (dryRun) continue;
      await api.projects.databases.documents.patch(
        Document(
          name: docName,
          fields: {
            'lat': Value(doubleValue: lat),
            'lng': Value(doubleValue: lng),
          },
        ),
        docName,
        updateMask_fieldPaths: ['lat', 'lng'],
      );
      updated++;
    }
  } finally {
    client.close();
  }

  stdout.writeln(
    'updated=$updated dryRun=$dryRun '
    'target=${emulator ? "emulator" : "prod"}',
  );
}

/// Wraps an [http.Client] so every request carries
/// `Authorization: Bearer owner`, the documented Firebase emulator
/// admin-bypass token.
class _EmulatorOwnerClient extends http.BaseClient {
  _EmulatorOwnerClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
