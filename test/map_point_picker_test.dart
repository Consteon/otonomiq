import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/widget/map_point_picker.dart';

void main() {
  // ── formatLatLng ───────────────────────────────────────────────────

  group('formatLatLng (anti-corruption: dot-decimal, 6dp)', () {
    test('standard negative/positive pair', () {
      expect(formatLatLng(-6.302154, 106.653428), '-6.302154,106.653428');
    });

    test('rounds to 6 decimal places', () {
      expect(formatLatLng(-6.3021541234, 106.6534289999),
          '-6.302154,106.653429');
    });

    test('zero coordinates', () {
      expect(formatLatLng(0, 0), '0.000000,0.000000');
    });

    test('always uses dot, never comma-decimal (locale-independent)', () {
      final result = formatLatLng(-6.302154, 106.653428);
      // Exactly two parts separated by comma
      final parts = result.split(',');
      expect(parts.length, 2);
      // Each part uses dot as decimal separator
      expect(parts[0], contains('.'));
      expect(parts[1], contains('.'));
      // No space around comma
      expect(result, isNot(contains(', ')));
      expect(result, isNot(contains(' ,')));
    });

    test('extreme values', () {
      expect(formatLatLng(-90, -180), '-90.000000,-180.000000');
      expect(formatLatLng(90, 180), '90.000000,180.000000');
    });
  });

  // ── parseOptionalPosition ──────────────────────────────────────────

  group('parseOptionalPosition', () {
    test('null -> null', () {
      expect(parseOptionalPosition(null), isNull);
    });

    test('empty string -> null', () {
      expect(parseOptionalPosition(''), isNull);
    });

    test('whitespace-only string -> null', () {
      expect(parseOptionalPosition('  '), isNull);
    });

    test('valid int string -> int', () {
      expect(parseOptionalPosition('14'), 14);
    });

    test('int value passthrough -> int', () {
      expect(parseOptionalPosition(15), 15);
    });

    test('zero -> null (positions are 1-based)', () {
      expect(parseOptionalPosition('0'), isNull);
    });

    test('negative -> null', () {
      expect(parseOptionalPosition('-1'), isNull);
    });

    test('non-numeric string -> null', () {
      expect(parseOptionalPosition('abc'), isNull);
    });

    test('float string -> null (int.tryParse rejects)', () {
      expect(parseOptionalPosition('14.5'), isNull);
    });
  });

  // ── mapPickerSlot ──────────────────────────────────────────────────

  group('mapPickerSlot (length-guarded text segments)', () {
    test('full text: all 9 segments accessible', () {
      final input = 'Belum ada'
          '${separator[1]}Lokasi Saya'
          '${separator[1]}Cari di Peta'
          '${separator[1]}Ganti'
          '${separator[1]}Cari alamat...'
          '${separator[1]}Pakai'
          '${separator[1]}Mencari...'
          '${separator[1]}GPS gagal'
          '${separator[1]}Jaringan error';
      final slots = diamondTextToList(input);
      expect(slots.length, 9);
      expect(mapPickerSlot(slots, 0, 'def'), 'Belum ada');
      expect(mapPickerSlot(slots, 1, 'def'), 'Lokasi Saya');
      expect(mapPickerSlot(slots, 4, 'def'), 'Cari alamat...');
      expect(mapPickerSlot(slots, 8, 'def'), 'Jaringan error');
    });

    test('sparse text (only 2 segments): out-of-range -> fallback', () {
      final input = 'Placeholder${separator[1]}GPS btn';
      final slots = diamondTextToList(input);
      expect(slots.length, 2);
      expect(mapPickerSlot(slots, 0, 'def'), 'Placeholder');
      expect(mapPickerSlot(slots, 1, 'def'), 'GPS btn');
      expect(mapPickerSlot(slots, 2, 'fallback'), 'fallback');
      expect(mapPickerSlot(slots, 8, 'fallback'), 'fallback');
    });

    test('empty text: diamondTextToList("") returns [""] -> all fallbacks',
        () {
      // diamondTextToList('') returns [''] (one empty element) because
      // global empty sentinel is '--' not ''.
      final slots = diamondTextToList('');
      expect(slots.length, 1);
      expect(slots[0], isEmpty);
      expect(mapPickerSlot(slots, 0, 'placeholder'), 'placeholder');
      expect(mapPickerSlot(slots, 1, 'fallback'), 'fallback');
    });

    test('segment present but empty -> fallback', () {
      // Simulate "FirstSeg◆◆ThirdSeg" -- middle is empty
      final input = 'First${separator[1]}${separator[1]}Third';
      final slots = diamondTextToList(input);
      expect(mapPickerSlot(slots, 0, 'def'), 'First');
      expect(mapPickerSlot(slots, 1, 'def'), 'def'); // empty -> fallback
      expect(mapPickerSlot(slots, 2, 'def'), 'Third');
    });
  });

  // ── parseLatLng ────────────────────────────────────────────────────

  group('parseLatLng', () {
    test('valid "lat,long" -> LatLng', () {
      final result = parseLatLng('-6.302154,106.653428');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.302154, 0.000001));
      expect(result.longitude, closeTo(106.653428, 0.000001));
    });

    test('with whitespace -> still parses', () {
      final result = parseLatLng(' -6.302154 , 106.653428 ');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.302154, 0.000001));
    });

    test('null -> null', () {
      expect(parseLatLng(null), isNull);
    });

    test('empty string -> null', () {
      expect(parseLatLng(''), isNull);
    });

    test('single number (no comma) -> null', () {
      expect(parseLatLng('123.456'), isNull);
    });

    test('lat out of range (>90) -> null', () {
      expect(parseLatLng('91.0,0.0'), isNull);
    });

    test('lng out of range (>180) -> null', () {
      expect(parseLatLng('0.0,181.0'), isNull);
    });

    test('non-numeric -> null', () {
      expect(parseLatLng('abc,def'), isNull);
    });

    test('round-trip: formatLatLng -> parseLatLng', () {
      final formatted = formatLatLng(-6.302154, 106.653428);
      final parsed = parseLatLng(formatted);
      expect(parsed, isNotNull);
      expect(parsed!.latitude, closeTo(-6.302154, 0.000001));
      expect(parsed.longitude, closeTo(106.653428, 0.000001));
    });
  });

  // ── extractLatLngFromText: URL shapes (spec §5.2 priority order) ───

  group('extractLatLngFromText - URL shapes', () {
    test('pattern 1: !3d/!4d beats the @viewport pair in the same URL', () {
      // @-6.316000,106.644000 is the screen centre; !3d/!4d is the shared pin.
      final result = extractLatLngFromText(
          'https://www.google.com/maps/place/Toko+Galon/'
          '@-6.316000,106.644000,17z/data=!3m1!4b1!4m6!3m5!1s0x2e69e1:0xabc'
          '!8m2!3d-6.316754!4d106.644907');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('pattern 2: ?q=lat,lng', () {
      final result = extractLatLngFromText(
          'https://maps.google.com/?q=-6.316754,106.644907');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('pattern 2: &q=loc:lat, lng with a space after the comma', () {
      final result = extractLatLngFromText(
          'https://maps.google.com/maps?hl=id&q=loc:-6.316754, 106.644907');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('pattern: /maps/search/?api=1&query= (Google Maps-URLs format)', () {
      // Google's own documented share format; the comma arrives
      // percent-encoded. Also a plausible LANDING url for an expanded short
      // link, so a miss here costs a full network round trip before the user
      // is told "no coordinates" -- the worst version of that failure.
      final result = extractLatLngFromText(
          'https://www.google.com/maps/search/?api=1'
          '&query=-6.316754%2C106.644907');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('pattern 3: /maps/place/lat,lng', () {
      final result = extractLatLngFromText(
          'https://www.google.com/maps/place/-6.316754,106.644907');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('pattern 4: @viewport only (last resort)', () {
      final result = extractLatLngFromText(
          'https://www.google.com/maps/@-6.316754,106.644907,17z');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });
  });

  // ── extractLatLngFromText: bare pasted text ────────────────────────

  group('extractLatLngFromText - bare text', () {
    test('"lat, lng" with a space', () {
      final result = extractLatLngFromText('-6.316754, 106.644907');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('"lat,lng" without a space', () {
      final result = extractLatLngFromText('-6.316754,106.644907');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('coordinates embedded in a sentence', () {
      final result =
          extractLatLngFromText('rumah saya -6.316754, 106.644907 ya');
      expect(result, isNotNull);
      expect(result!.latitude, closeTo(-6.316754, 0.000001));
      expect(result.longitude, closeTo(106.644907, 0.000001));
    });

    test('digits inside a URL path are NOT read as bare coordinates', () {
      // The (?:^|\s) prefix on the bare-text pattern is what stops this.
      expect(
          extractLatLngFromText('https://example.com/foo/-6.3,106.6'), isNull);
    });
  });

  // ── extractLatLngFromText: rejections (all surface as segment 12) ──

  group('extractLatLngFromText - rejections', () {
    test('empty string -> null', () {
      expect(extractLatLngFromText(''), isNull);
    });

    test('whitespace only -> null', () {
      expect(extractLatLngFromText('   '), isNull);
    });

    test('prose with no numbers -> null', () {
      expect(extractLatLngFromText('halo pak saya sudah di rumah'), isNull);
    });

    test('maps link with a place name but no coordinates -> null', () {
      expect(
          extractLatLngFromText(
              'https://www.google.com/maps/place/Toko+Galon+Pagedangan'),
          isNull);
    });

    test('place_id link (named place, not a pin) -> null', () {
      expect(
          extractLatLngFromText(
              'https://www.google.com/maps/place/?q=place_id:ChIJabcdef'),
          isNull);
    });

    test('unexpanded short link -> null (the caller expands it first)', () {
      expect(
          extractLatLngFromText('https://maps.app.goo.gl/AbCdEf123'), isNull);
    });

    test('outside Indonesia: Paris viewport -> null', () {
      expect(
          extractLatLngFromText(
              'https://www.google.com/maps/@48.858370,2.294481,17z'),
          isNull);
    });

    test('longitude outside Indonesia (negative) -> null', () {
      expect(extractLatLngFromText('https://maps.google.com/?q=-6.3,-77.0'),
          isNull);
    });

    test('latitude outside Indonesia (north of 6) -> null', () {
      expect(extractLatLngFromText('https://maps.google.com/?q=13.75,100.5'),
          isNull);
    });

    test('foreign high-priority match aborts; does NOT fall back to a lower '
        'priority in-range match', () {
      // !3d/!4d is Paris, @ is Jakarta. The shared pin is the !3d/!4d pair, so
      // an out-of-range hit must REJECT, never silently substitute the
      // viewport. Guards the deliberate `return null` (not `continue`) in
      // extractLatLngFromText -- see plan §2.7.
      expect(
          extractLatLngFromText('https://www.google.com/maps/'
              '@-6.316754,106.644907,17z/data=!3d48.858370!4d2.294481'),
          isNull);
      // Control: strip the foreign !3d/!4d pair and the same URL resolves to
      // the Jakarta viewport -- proving the case above aborts rather than
      // simply failing to match anything.
      final control = extractLatLngFromText(
          'https://www.google.com/maps/@-6.316754,106.644907,17z');
      expect(control, isNotNull);
      expect(control!.latitude, closeTo(-6.316754, 0.000001));
    });
  });

  // ── mapsShortLinkUri (HOST allowlist: never GET a pasted stranger) ──

  group('mapsShortLinkUri', () {
    test('maps.app.goo.gl -> uri', () {
      expect(mapsShortLinkUri('https://maps.app.goo.gl/AbCdEf123')?.host,
          'maps.app.goo.gl');
    });

    test('goo.gl/maps -> uri', () {
      expect(mapsShortLinkUri('https://goo.gl/maps/AbCdEf123')?.host, 'goo.gl');
    });

    test('case insensitive', () {
      // The URL-extraction RegExp must be case-insensitive too, not just the
      // host compare -- `https?://` alone would not match `HTTPS://`.
      expect(mapsShortLinkUri('HTTPS://MAPS.APP.GOO.GL/AbCdEf')?.host,
          'maps.app.goo.gl');
    });

    test('short link inside surrounding prose -> uri (the WhatsApp paste)',
        () {
      // The feature's primary input is a copied WhatsApp message, not a bare
      // URL. Uri.tryParse returns NULL for the whole string, so the URL has
      // to be pulled out of the text before the host can be judged.
      expect(
          mapsShortLinkUri(
                  'Ini lokasi rumah saya https://maps.app.goo.gl/AbCdEf123')
              ?.toString(),
          'https://maps.app.goo.gl/AbCdEf123');
    });

    test('long google maps url -> null (no hop needed)', () {
      expect(mapsShortLinkUri('https://www.google.com/maps/@-6.3,106.6,17z'),
          isNull);
    });

    test('allowlisted name in the QUERY of a foreign host -> null', () {
      // THE fixture for the host check. The host is evil.example.com; the
      // allowlisted name appears only as a query parameter, so a substring
      // test answers "short link" and the app then GETs an attacker-chosen
      // host. Deleting the host compare must turn this red.
      expect(mapsShortLinkUri('https://evil.example.com/x?ref=maps.app.goo.gl'),
          isNull);
    });

    test('goo.gl outside /maps -> null (general-purpose shortener)', () {
      expect(mapsShortLinkUri('https://goo.gl/AbCdEf123'), isNull);
    });

    test('bare coordinates -> null', () {
      expect(mapsShortLinkUri('-6.316754, 106.644907'), isNull);
    });

    test('prose with no url at all -> null', () {
      expect(mapsShortLinkUri('halo pak saya sudah di rumah'), isNull);
    });

    test('the redirect loop re-checks the host on EVERY hop', () {
      // The only part of the allowlist no runtime test can reach: following a
      // redirect needs a real socket, and this repo has no mock package (see
      // plan 6.3). Pinned at the source level rather than left uncovered --
      // deleting the per-hop re-check lets one response's `location` header
      // aim the next GET at any host, which is the other half of the bug the
      // host allowlist exists to close.
      final f = File('lib/widget/map_point_picker.dart');
      expect(f.existsSync(), isTrue,
          reason: 'run flutter test from the package root');
      expect(f.readAsStringSync(),
          contains('if (!_isAllowedShortLinkHost(next)) return nextUrl;'));
    });
  });

  // ── joinAddressNote: the note's only new business rule ────────────

  group('joinAddressNote', () {
    const address = 'Jl. Melati Raya, Pagedangan, Tangerang';
    const note = 'Blok A no 17, pagar hijau';

    test('address + note -> joined with an em dash', () {
      final result = joinAddressNote(address, note);
      expect(result, '$address — $note');
      // The separator must be exactly SPACE U+2014 SPACE. A hyphen or an en
      // dash would still satisfy the assertion above if it were retyped in
      // BOTH the helper and this fixture, so pin the codepoint here.
      final sep = result.substring(address.length, result.length - note.length);
      expect(sep.runes.toList(), [0x20, 0x2014, 0x20]);
    });

    test('note empty -> bare address, no dangling separator (v1 behaviour)',
        () {
      expect(joinAddressNote(address, ''), address);
    });

    test('address empty -> bare note, no leading separator', () {
      // Real case: Nominatim answers 200 with an empty display_name, so
      // _displayName is '' while the user has typed a note.
      expect(joinAddressNote('', note), note);
    });

    test('both empty -> empty string', () {
      expect(joinAddressNote('', ''), '');
    });
  });

  // ── v2 text segments 10-14 are appended AFTER the existing 9=Hapus ─

  group('mapPickerSlot - v2 segments do not disturb v1', () {
    String seg(List<String> parts) => parts.join(separator[1]);

    final v2 = diamondTextToList(seg([
      'Belum ada titik', // 0
      'Lokasi Saya', // 1
      'Cari di Peta', // 2
      'Ganti Titik', // 3
      'Cari alamat / tempat', // 4
      'Pakai Titik Ini', // 5
      'Mencari lokasi', // 6
      'GPS gagal', // 7
      'Jaringan bermasalah', // 8 (dead: never read by the renderer)
      'Hapus', // 9
      'Tempel Link Lokasi', // 10
      'Tempel link Google Maps dari WhatsApp di sini', // 11
      'Link gak ada koordinatnya', // 12
      'Catatan buat driver (opsional)', // 13
      'cth: Blok A no 17, pagar hijau', // 14
    ]));

    final v1 = diamondTextToList(seg([
      'Belum ada titik',
      'Lokasi Saya',
      'Cari di Peta',
      'Ganti Titik',
      'Cari alamat / tempat',
      'Pakai Titik Ini',
      'Mencari lokasi',
      'GPS gagal',
      'Jaringan bermasalah',
      'Hapus',
    ]));

    test('15-segment config: index 9 is STILL Hapus', () {
      expect(v2.length, 15);
      expect(mapPickerSlot(v2, 9, 'def'), 'Hapus');
    });

    test('15-segment config: new segments 10-14 resolve', () {
      expect(mapPickerSlot(v2, 10, 'def'), 'Tempel Link Lokasi');
      expect(mapPickerSlot(v2, 11, 'def'),
          'Tempel link Google Maps dari WhatsApp di sini');
      expect(mapPickerSlot(v2, 12, 'def'), 'Link gak ada koordinatnya');
      expect(mapPickerSlot(v2, 13, 'def'), 'Catatan buat driver (opsional)');
      expect(mapPickerSlot(v2, 14, 'def'), 'cth: Blok A no 17, pagar hijau');
    });

    test('10-segment v1 config: 9 is Hapus, 10-14 fall back, no RangeError',
        () {
      expect(v1.length, 10);
      expect(mapPickerSlot(v1, 9, 'def'), 'Hapus');
      expect(mapPickerSlot(v1, 10, 'fallback'), 'fallback');
      expect(mapPickerSlot(v1, 11, 'fallback'), 'fallback');
      expect(mapPickerSlot(v1, 12, 'fallback'), 'fallback');
      expect(mapPickerSlot(v1, 13, 'fallback'), 'fallback');
      expect(mapPickerSlot(v1, 14, 'fallback'), 'fallback');
    });
  });
}
