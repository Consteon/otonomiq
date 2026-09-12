import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/page/map_page_support.dart';

/// Two registered sites roughly 1.1 km apart in BSD.
const Map<String, dynamic> _lqr = <String, dynamic>{
  'a': <dynamic>['BSD Tech Center', -6.3020, 106.6520, 100],
  'b': <dynamic>['Gudang Utara', -6.3120, 106.6520, 250],
};

void main() {
  group('nearestLqrSite', () {
    test('picks the nearer of two registered sites', () {
      final LqrSite? site = nearestLqrSite(_lqr, -6.3025, 106.6521);
      expect(site, isNotNull);
      expect(site!.name, 'BSD Tech Center');
      expect(site.radius, 100);
    });

    test('picks the other one when the user is standing at it', () {
      final LqrSite? site = nearestLqrSite(_lqr, -6.3119, 106.6519);
      expect(site!.name, 'Gudang Utara');
      expect(site.radius, 250);
    });

    test('null / empty / wrong-shaped #LQR_LIST yields no geofence', () {
      expect(nearestLqrSite(null, -6.3, 106.6), isNull);
      expect(nearestLqrSite(<String, dynamic>{}, -6.3, 106.6), isNull);
      expect(nearestLqrSite('bukan map', -6.3, 106.6), isNull);
      expect(nearestLqrSite(<String, dynamic>{'a': 'bukan list'}, -6.3, 106.6),
          isNull);
    });

    test('a malformed entry is skipped, not fatal to the rest', () {
      final LqrSite? site = nearestLqrSite(
        <String, dynamic>{
          'short': <dynamic>['Kurang kolom', -6.3020],
          'bad': <dynamic>['Bukan angka', 'x', 'y', 'z'],
          'ok': <dynamic>['Yang benar', -6.3020, 106.6520, 100],
        },
        -6.3025,
        106.6521,
      );
      expect(site!.name, 'Yang benar');
    });

    test('coordinates that arrive as Strings are still read', () {
      final LqrSite? site = nearestLqrSite(
        <String, dynamic>{
          'a': <dynamic>['Teks', '-6.3020', '106.6520', '100'],
        },
        -6.3025,
        106.6521,
      );
      expect(site, isNotNull);
      expect(site!.radius, 100);
    });
  });

  group('mapFixStatus — the three states the mock draws', () {
    test('inside: 48 m to the boundary at ±52 m accuracy', () {
      expect(
        mapFixStatus(distance: 52, radius: 100, accuracy: 52),
        MapFixStatus.inside,
      );
    });

    test('outside: 140 m past the boundary at ±18 m accuracy', () {
      expect(
        mapFixStatus(distance: 240, radius: 100, accuracy: 18),
        MapFixStatus.outside,
      );
    });

    test('unsure: 12 m past the ring but well inside the tolerance', () {
      expect(
        mapFixStatus(distance: 112, radius: 100, accuracy: 120),
        MapFixStatus.unsure,
      );
    });

    test('searching whenever any input is still unknown', () {
      expect(mapFixStatus(distance: null, radius: 100, accuracy: 10),
          MapFixStatus.searching);
      expect(mapFixStatus(distance: 10, radius: null, accuracy: 10),
          MapFixStatus.searching);
      expect(mapFixStatus(distance: 10, radius: 100, accuracy: null),
          MapFixStatus.searching);
    });
  });

  group('mapFixStatus — the two edges of the band', () {
    test('green only inside the ring that is actually drawn', () {
      expect(mapFixStatus(distance: 30, radius: 30, accuracy: 20),
          MapFixStatus.inside);
      expect(mapFixStatus(distance: 30.1, radius: 30, accuracy: 20),
          MapFixStatus.unsure);
    });

    test('red only past the card\'s own tolerance, never before it', () {
      // The live 30 m tolerance with a 20 m fix: the card accepts out to 70 m.
      expect(mapFixStatus(distance: 70, radius: 30, accuracy: 20),
          MapFixStatus.unsure);
      expect(mapFixStatus(distance: 70.1, radius: 30, accuracy: 20),
          MapFixStatus.outside);
    });

    test('the two screens never contradict each other', () {
      // Whatever the card calls inside (distance <= radius + 2 * accuracy)
      // the map calls inside or unsure — never outside — and vice versa.
      for (final double radius in const <double>[30, 100, 200]) {
        for (final double accuracy in const <double>[5, 20, 52, 120]) {
          for (double distance = 0; distance < 900; distance += 7) {
            final bool cardInside = distance <= radius + accuracy * 2;
            final MapFixStatus s = mapFixStatus(
                distance: distance, radius: radius, accuracy: accuracy);
            expect(s == MapFixStatus.outside, !cardInside,
                reason: 'r=$radius acc=$accuracy d=$distance');
          }
        }
      }
    });

    test('a perfect fix leaves no band at all', () {
      expect(mapFixStatus(distance: 100, radius: 100, accuracy: 0),
          MapFixStatus.inside);
      expect(mapFixStatus(distance: 100.1, radius: 100, accuracy: 0),
          MapFixStatus.outside);
    });
  });

  group('numbers the sheet prints', () {
    test('distance to the boundary is unsigned; the status word gives the side',
        () {
      expect(metersToBoundary(52, 100), 48);
      expect(metersToBoundary(240, 100), 140);
      expect(metersToBoundary(null, 100), isNull);
      expect(metersToBoundary(52, null), isNull);
    });

    test('unknown prints an em dash, never a zero', () {
      expect(metersLabel(null), '—');
      expect(accuracyLabel(null), '—');
      expect(metersLabel(0), '0 m');
      expect(metersLabel(47.6), '48 m');
      expect(accuracyLabel(51.7), '±52 m');
    });
  });

  test('distanceToSite measures from the site centre', () {
    const LqrSite site = LqrSite(
      name: 'BSD Tech Center',
      lat: -6.3020,
      lng: 106.6520,
      radius: 100,
    );
    expect(distanceToSite(site, -6.3020, 106.6520), closeTo(0, 0.001));
    // ~0.001 degree of latitude is ~111 m.
    expect(distanceToSite(site, -6.3030, 106.6520), closeTo(111, 2));
  });
}
