import 'package:geolocator/geolocator.dart';

/// Pure helpers behind the `variant: "v6"` location map ([MapPage]).
///
/// Nothing here touches Flutter, the store or a plugin channel, so every rule
/// the screen decides on is testable without a device. `Geolocator
/// .distanceBetween` is the one import and it is pure Haversine maths on the
/// platform-interface base class -- no method channel, so it runs in tests too.

/// One geofence out of `#LQR_LIST`, whose entries are
/// `[name, latitude, longitude, toleranceMeters]`.
class LqrSite {
  const LqrSite({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radius,
  });

  final String name;
  final double lat;
  final double lng;

  /// The site's own tolerance, in metres. This is the ring the map draws.
  final double radius;
}

/// Accuracy at or under which the fix is called good. Same 30 m the
/// `LocationDetector` card already uses for its "Akurasi Rendah" chip, so the
/// home panel and this screen can never disagree about the wording.
const double kLowAccuracyMeters = 30;

/// Accuracy above which the fix is too coarse to draw in the same colour as a
/// good one: the accuracy circle turns amber from here up. It does NOT decide
/// the status -- see [mapFixStatus] for why the geometry does that instead.
const double kCoarseAccuracyMeters = 75;

/// What the bottom sheet says. [unsure] is the state the old screen could not
/// express: the position is known, the boundary is known, and the error bars
/// are wide enough that either answer would be a coin flip.
enum MapFixStatus { searching, inside, outside, unsure }

/// Reads a sheet-sourced value that should be a number. The proxy hands these
/// through as `num` most of the time and as `String` when a tenant typed the
/// coordinate with a leading apostrophe, so both are accepted; anything else
/// drops the whole entry rather than throwing the map away.
double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

/// The registered site nearest to [lat]/[lng].
///
/// Returns null when `#LQR_LIST` is absent, empty, or shaped like anything
/// other than a map of 4-element lists -- the screen then draws the position
/// with no ring, which is honest, instead of inventing a geofence.
LqrSite? nearestLqrSite(Object? lqrList, double lat, double lng) {
  if (lqrList is! Map || lqrList.isEmpty) return null;

  LqrSite? best;
  double bestDistance = double.infinity;

  for (final Object? entry in lqrList.values) {
    if (entry is! List || entry.length < 4) continue;
    final double? siteLat = _asDouble(entry[1]);
    final double? siteLng = _asDouble(entry[2]);
    final double? radius = _asDouble(entry[3]);
    if (siteLat == null || siteLng == null || radius == null) continue;

    final double distance = Geolocator.distanceBetween(
      siteLat,
      siteLng,
      lat,
      lng,
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      best = LqrSite(
        name: entry[0]?.toString() ?? '',
        lat: siteLat,
        lng: siteLng,
        radius: radius,
      );
    }
  }
  return best;
}

/// Metres from the user to the site centre.
double distanceToSite(LqrSite site, double lat, double lng) =>
    Geolocator.distanceBetween(site.lat, site.lng, lat, lng);

/// Metres between the user and the ring, whichever side they are on. This is
/// the "Ke batas" number; the status word says which side it is measured from.
double? metersToBoundary(double? distance, double? radius) =>
    (distance == null || radius == null) ? null : (distance - radius).abs();

/// The one status rule for this screen: the card's own test, split in two.
///
/// `LocationDetector` calls you inside whenever
/// `distance <= radius + accuracy * 2` -- deliberately generous, so a shaky
/// fix does not lock someone out at the gate. On a card that draws no map
/// that is invisible. On a map it is not: live tolerances are as low as 30 m
/// (`op1!M12:M211`), so a 20 m fix stretches the accepted zone to 70 m and a
/// user standing 50 m out would read "Di dalam area" over a picture of
/// themselves plainly outside the ring.
///
/// So the same partition is reported in three parts instead of two:
///
///   * [inside]  -- inside the ring that is actually drawn.
///   * [unsure]  -- outside the ring but inside the card's tolerance. The
///                  card still says inside; this screen declines to confirm
///                  it rather than contradict the picture.
///   * [outside] -- beyond even that, which is exactly where the card says
///                  outside too.
///
/// The two screens therefore never disagree: card-inside covers [inside] and
/// [unsure], card-outside is [outside] exactly. Accuracy only widens the
/// middle band; it never flips an answer.
MapFixStatus mapFixStatus({
  double? distance,
  double? radius,
  double? accuracy,
}) {
  if (distance == null || radius == null || accuracy == null) {
    return MapFixStatus.searching;
  }
  if (distance <= radius) return MapFixStatus.inside;
  if (distance > radius + accuracy * 2) return MapFixStatus.outside;
  return MapFixStatus.unsure;
}

/// `null` renders as an em dash, never as `0 m` -- "we do not know yet" and
/// "you are standing on the line" are different answers.
String metersLabel(double? meters) =>
    meters == null ? '—' : '${meters.round()} m';

String accuracyLabel(double? meters) =>
    meters == null ? '—' : '±${meters.round()} m';
