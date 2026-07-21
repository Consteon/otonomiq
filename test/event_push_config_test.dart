// Characterization guard for the Event Push (Flutter side) feature.
//
// The feature is PURE CONFIG (no production Dart). Its correctness rests on
// three committed Dart guarantees this file locks, so a future refactor that
// adds an event-field whitelist or shifts the position offset fails LOUDLY
// instead of silently killing push:
//   1. addToEvent passes arbitrary literal fields (ntf, cv, sv, ty) through
//      untouched -- no whitelist -- so the CF gate field `ntf` survives.
//   2. Numeric-ID fields (cv, sv) stay String (no precision loss); CF normalizes.
//   3. Typed form values reach nm/dp via the token pipeline, at the VERIFIED
//      offset: form position P -> ref[1][P] -> {{POS(P)}} == the-N+1 form token.
//      (sheetSystemLength = 15 puts an unused boundary slot at ref[1][0].)
//
// Pure unit test -- models test/add_to_event_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart';
import 'package:otonomiq/firestore_repository/add_to_event.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';
import 'package:otonomiq/global.dart';

void main() {
  final hollow = separator[8]; // ⭘ field separator
  final square = separator[2]; // ◼ key/value separator
  final ro = forbiddenCharacter[8]; // ◁ form-position token open
  final rc = forbiddenCharacter[10]; // ▷ form-position token close

  // §4 broadcast: the DSL AFTER saveSend resolved {userVid}+{{POS(n)}} to
  // literals -- this is what writeToEvent -> buildEventDoc sees at sync time.
  group('event-push §4 broadcast — literal fields survive parse + build', () {
    final broadcastLiteral = '84214220504259//event'
        '${hollow}ntf${square}broadcast'
        '${hollow}cv${square}83674161979544'
        '${hollow}sv${square}20342033315492'
        '${hollow}nm${square}Apel Pagi'
        '${hollow}dp${square}Halo semua, apel jam 7'
        '${hollow}ty${square}announcement';

    test('parseAddToEvent keeps ntf/cv/sv/nm/dp/ty (no whitelist)', () {
      final m = parseAddToEvent(broadcastLiteral);
      expect(m['_collection'], '84214220504259//event');
      expect(m['ntf'], 'broadcast');
      expect(m['cv'], '83674161979544');
      expect(m['sv'], '20342033315492');
      expect(m['nm'], 'Apel Pagi');
      expect(m['dp'], 'Halo semua, apel jam 7');
      expect(m['ty'], 'announcement');
    });

    test('buildEventDoc emits the broadcast doc; cv/sv stay String', () {
      final built = buildEventDoc(broadcastLiteral, [<String>[], <String>[]],
          tableVid: 1,
          appVid: 2,
          timeReceived: 1780323812536,
          receivingPage: 'vtlBroadcast',
          eventData: 'rawBlob');
      expect(built.collection, '84214220504259//event');
      expect(built.doc['ntf'], 'broadcast'); // GATE preserved
      expect(built.doc['cv'], '83674161979544');
      expect(built.doc['cv'], isA<String>()); // no precision loss
      expect(built.doc['sv'], '20342033315492');
      expect(built.doc['sv'], isA<String>());
      expect(built.doc['nm'], 'Apel Pagi');
      expect(built.doc['dp'], 'Halo semua, apel jam 7');
      expect(built.doc['ty'], 'announcement');
      expect(built.doc['et'], '1780323812536'); // auto A: Time
      expect(built.doc['p'], 'vtlBroadcast'); // auto B: Route
      expect(built.doc['ev'], 'rawBlob'); // auto C: Data blob
    });

    test('eventCollectionPath lands on the CF-watched //event path', () {
      final p = eventCollectionPath('84214220504259//event', 20342033315492);
      // CF onEventCreated trigger: MobileTable/{db}/tables/{tid}/event/{eid}
      expect(p, 'MobileTable/20342033315492/tables/84214220504259/event');
      expect(p.split('/').length.isOdd, isTrue); // valid Firestore collection
    });
  });

  // Capture-time: saveSend runs replacePlaceholders over the addToEvent string.
  // VERIFIED offset: ref[1][0] is the unused boundary slot (row[14]); form
  // position 1 -> ref[1][1] -> {{POS(1)}}, position 2 -> ref[1][2] -> {{POS(2)}}.
  group('event-push §4 broadcast — {{POS(n)}} pulls typed title/body', () {
    test('{{POS(1)}}/{{POS(2)}} resolve to form positions 1/2', () {
      final ref = <List<dynamic>>[
        <dynamic>[], // ref[0] = system cols (unused by POS tokens)
        <dynamic>['', 'Apel Pagi', 'Halo semua'], // [0]=boundary,[1]=pos1,[2]=pos2
      ];
      final out = replacePlaceholders('nm={{POS(1)}} dp={{POS(2)}}', ref);
      expect(out, 'nm=Apel Pagi dp=Halo semua');
    });
  });

  // Sync-time equivalent: ◁N▷ resolves against ref[1] inside buildEventDoc, so a
  // template MAY author nm/dp as ◁2▷/◁3▷ instead of {{POS(1)}}/{{POS(2)}}.
  group('event-push §4 broadcast — ◁N▷ form token (sync-time equivalent)', () {
    test('◁2▷/◁3▷ resolve to form positions 1/2 in buildEventDoc', () {
      final ref = <dynamic>[
        <String>[],
        <String>['', 'Apel Pagi', 'Halo semua'], // [1]=pos1, [2]=pos2
      ];
      final block = '84214220504259//event'
          '${hollow}ntf${square}broadcast'
          '${hollow}nm$square${ro}2$rc'
          '${hollow}dp$square${ro}3$rc';
      final built = buildEventDoc(block, ref,
          tableVid: 1,
          appVid: 2,
          timeReceived: 0,
          receivingPage: 'pg',
          eventData: 'blob');
      expect(built.doc['ntf'], 'broadcast');
      expect(built.doc['nm'], 'Apel Pagi'); // ◁2▷ -> ref[1][1]
      expect(built.doc['dp'], 'Halo semua'); // ◁3▷ -> ref[1][2]
    });
  });

  // §3 single: adding ntf◼single to a report form's existing addToEvent DSL
  // must not disturb the fields it already writes (cv/av/nm/ty).
  group('event-push §3 single — ntf◼single passes through report DSL', () {
    test('ntf added alongside existing report fields; all survive', () {
      final body = '84214220504259//event'
          '${hollow}ntf${square}single'
          '${hollow}cv${square}83674161979544'
          '${hollow}av${square}20342033315492'
          '${hollow}nm${square}Laporan Insiden'
          '${hollow}ty${square}report-incident';
      final m = parseAddToEvent(body);
      expect(m['ntf'], 'single');
      expect(m['cv'], '83674161979544');
      expect(m['av'], '20342033315492');
      expect(m['nm'], 'Laporan Insiden');
      expect(m['ty'], 'report-incident');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // v3: notification prop → buildNotificationSuffix
  // ─────────────────────────────────────────────────────────────────────
  group('v3 buildNotificationSuffix — notification prop injection', () {
    // Identity resolver for tests that don't need token substitution.
    String identity(String s) => s;

    test('single mode: emits ntf+nm+dp, no bcc', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': 'Patroli',
        'message': 'Selesai patroli',
      };
      final result = buildNotificationSuffix(ntf, identity);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['ntf'], 'single');
      expect(parsed['nm'], 'Patroli');
      expect(parsed['dp'], 'Selesai patroli');
      expect(parsed.containsKey('bcc'), false);
    });

    test('broadcast with literal diamond target: sanitized to comma, '
        'single DSL block', () {
      final ntf = <String, dynamic>{
        'mode': 'broadcast',
        'target': '32639062303108${separator[1]}32639062303102',
        'title': 'Pengumuman',
        'message': 'Halo semua',
      };
      final suffix = buildNotificationSuffix(ntf, identity);
      // Regression guard: prefix with collection header, split by ◆
      final block = '84214220504259//event$suffix';
      final blocks = block
          .split(separator[1])
          .where((b) => b.trim().isNotEmpty)
          .toList();
      expect(blocks.length, 1,
          reason: 'literal diamond in bcc must not split block');
      final parsed = parseAddToEvent(blocks[0]);
      expect(parsed['ntf'], 'broadcast');
      expect(parsed['bcc'], '32639062303108,32639062303102');
      expect(parsed['nm'], 'Pengumuman');
      expect(parsed['dp'], 'Halo semua');
    });

    test('token target survives compose-time; diamond from sync-time '
        'resolveValueTokens stays intact in Firestore', () {
      // This is the spec §3.1 path: target is a cell-reference token like
      // ◁2▷, resolved at sync-time by resolveValueTokens AFTER the ◆-split.
      final ntf = <String, dynamic>{
        'mode': 'broadcast',
        'target': '${ro}2$rc', // ◁2▷
        'title': 'Pengumuman',
        'message': 'Halo {nama}',
      };
      final suffix = buildNotificationSuffix(ntf, identity);
      // Full DSL block: collection header + notification fields
      final fullBlock = '84214220504259//event$suffix';
      // Split by ◆ must yield 1 block — token is opaque at compose time
      final blocks = fullBlock
          .split(separator[1])
          .where((b) => b.trim().isNotEmpty)
          .toList();
      expect(blocks.length, 1,
          reason: 'token target has no diamond at compose time');
      // Sync-time: buildEventDoc resolves ◁2▷ → ref[1][1]
      final ref = <dynamic>[
        <String>[],
        <String>['', '32639062303108${separator[1]}32639062303102'],
      ];
      final built = buildEventDoc(blocks[0], ref,
          tableVid: 1,
          appVid: 2,
          timeReceived: 0,
          receivingPage: 'pg',
          eventData: 'blob');
      expect(built.doc['ntf'], 'broadcast');
      expect(built.doc['bcc'],
          '32639062303108${separator[1]}32639062303102',
          reason: 'diamond in bcc must survive — CF native format');
      expect(built.doc['dp'], 'Halo {nama}',
          reason: '{nama} literal for CF per-recipient personalization');
      expect(built.doc['nm'], 'Pengumuman');
    });

    test('encoded _u25C6_ in literal target: decoded then comma-sanitized',
        () {
      final ntf = <String, dynamic>{
        'mode': 'broadcast',
        'target': '32639062303108_u25C6_32639062303102',
        'title': 'Test',
        'message': 'Msg',
      };
      final suffix = buildNotificationSuffix(ntf, identity);
      expect(suffix.contains(separator[1]), false,
          reason: 'decoded diamond must be sanitized');
      final parsed = parseAddToEvent('col$suffix');
      expect(parsed['bcc'], '32639062303108,32639062303102');
    });

    test('null notification returns empty string', () {
      expect(buildNotificationSuffix(null, identity), '');
    });

    test('malformed notification (String) returns empty string', () {
      expect(buildNotificationSuffix('not a map', identity), '');
    });

    test('malformed notification (List) returns empty string', () {
      expect(buildNotificationSuffix(['single'], identity), '');
    });

    test('empty title and message: fields omitted (CF fallback)', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': '',
        'message': '',
      };
      final result = buildNotificationSuffix(ntf, identity);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['ntf'], 'single');
      expect(parsed.containsKey('nm'), false);
      expect(parsed.containsKey('dp'), false);
    });

    test('resolver returning No-DATA: nm/dp omitted for CF fallback', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': 'MARKER',
        'message': 'MARKER',
      };
      // Simulates replacePlaceholders on an out-of-bounds {{POS(99)}}
      String noDataResolver(String s) => s == 'MARKER' ? 'No-DATA' : s;
      final result = buildNotificationSuffix(ntf, noDataResolver);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['ntf'], 'single');
      expect(parsed.containsKey('nm'), false,
          reason: 'No-DATA title must be omitted for CF fallback');
      expect(parsed.containsKey('dp'), false,
          reason: 'No-DATA message must be omitted for CF fallback');
    });

    test('resolver returning NO-DATA: nm/dp omitted for CF fallback', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': 'MARKER',
        'message': 'MARKER',
      };
      // Simulates replacePlaceholders on an OUT-OF-BOUNDS index, which returns
      // uppercase 'NO-DATA' (api.dart:4227) — distinct from the null-ref
      // lowercase 'No-DATA' (api.dart:4217) covered above.
      String noDataResolver(String s) => s == 'MARKER' ? 'NO-DATA' : s;
      final result = buildNotificationSuffix(ntf, noDataResolver);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['ntf'], 'single');
      expect(parsed.containsKey('nm'), false,
          reason: 'NO-DATA title must be omitted for CF fallback');
      expect(parsed.containsKey('dp'), false,
          reason: 'NO-DATA message must be omitted for CF fallback');
    });

    test('black circle in title sanitized — outer tb segment frame intact', () {
      // saveSend joins tableString⬤update⬤delete⬤event⬤updateEvent with
      // separator[0]. A ⬤ surviving into the event segment would shift every
      // later segment and silently drop the updateEventRow payload.
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': 'Patroli${separator[0]}Malam',
        'message': 'OK',
      };
      final suffix = buildNotificationSuffix(ntf, identity);
      expect(suffix.contains(separator[0]), false,
          reason: 'black circle must not survive into the event segment');
      // Frame round-trip: event segment stays at index 3, updateEvent at 4.
      final tb = 'tbl${separator[0]}upd${separator[0]}del'
          '${separator[0]}col$suffix${separator[0]}updEvent';
      final segments = tb.split(separator[0]);
      expect(segments.length, 5, reason: 'tb frame must stay 5 segments');
      expect(segments[4], 'updEvent',
          reason: 'updateEventRow payload must not be shifted out');
      expect(parseAddToEvent(segments[3])['nm'], 'Patroli Malam');
    });

    test('black circle in mode stripped; ⬤-only mode returns empty', () {
      // mode skips clean(), but ⬤ is U+2B24 (category So, not whitespace) so
      // trim() cannot remove it — a raw typed ⬤ would still shift the tb frame.
      final ntf = <String, dynamic>{
        'mode': 'sing${separator[0]}le',
        'title': 'Patroli',
        'message': 'OK',
      };
      final suffix = buildNotificationSuffix(ntf, identity);
      expect(suffix.contains(separator[0]), false,
          reason: 'black circle must not reach the event segment via mode');
      expect(parseAddToEvent('col$suffix')['ntf'], 'single',
          reason: 'stripped, not spaced — mode is an identifier-like token');
      // A mode consisting only of ⬤ collapses to empty and early-returns.
      expect(
          buildNotificationSuffix(
              <String, dynamic>{'mode': separator[0], 'title': 'x'}, identity),
          '');
    });

    test('whitespace-only title: nm omitted (CF falls back to cn)', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': '   ',
        'message': 'OK',
      };
      final result = buildNotificationSuffix(ntf, identity);
      final parsed = parseAddToEvent('col$result');
      expect(parsed.containsKey('nm'), false);
      expect(parsed['dp'], 'OK');
    });

    test('{nama} in message survives literally', () {
      final ntf = <String, dynamic>{
        'mode': 'broadcast',
        'target': '32639062303108',
        'title': 'Pengumuman',
        'message': 'Halo {nama}, pesan penting',
      };
      final result = buildNotificationSuffix(ntf, identity);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['dp'], 'Halo {nama}, pesan penting');
    });

    test('single mode ignores target — no bcc field', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': 'Laporan',
        'message': 'Isi laporan',
        'target': '12345',
      };
      final result = buildNotificationSuffix(ntf, identity);
      expect(result.contains('bcc'), false);
    });

    test('separator glyphs in title replaced (no DSL corruption)', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': 'Patroli${separator[8]}Rutin${separator[2]}Malam',
        'message': 'OK',
      };
      final result = buildNotificationSuffix(ntf, identity);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['nm'], 'Patroli Rutin Malam');
    });

    test('empty mode: skip entirely', () {
      final ntf = <String, dynamic>{
        'mode': '',
        'title': 'Test',
        'message': 'Test',
      };
      expect(buildNotificationSuffix(ntf, identity), '');
    });

    test('unknown mode: written as-is (CF ignores)', () {
      final ntf = <String, dynamic>{
        'mode': 'priority',
        'title': 'Urgent',
        'message': 'Something',
      };
      final result = buildNotificationSuffix(ntf, identity);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['ntf'], 'priority');
      expect(parsed.containsKey('bcc'), false,
          reason: 'bcc only for broadcast');
    });

    test('broadcast with empty target: bcc still written', () {
      final ntf = <String, dynamic>{
        'mode': 'broadcast',
        'title': 'Pengumuman',
        'message': 'Halo',
        'target': '',
      };
      final result = buildNotificationSuffix(ntf, identity);
      final parsed = parseAddToEvent('col$result');
      expect(parsed.containsKey('bcc'), true);
      expect(parsed['bcc'], '');
    });

    test('resolver callback is applied to values', () {
      final ntf = <String, dynamic>{
        'mode': 'single',
        'title': 'MARKER_A',
        'message': 'MARKER_B',
      };
      String testResolver(String s) =>
          s.replaceAll('MARKER_A', 'Resolved Title')
           .replaceAll('MARKER_B', 'Resolved Body');
      final result = buildNotificationSuffix(ntf, testResolver);
      final parsed = parseAddToEvent('col$result');
      expect(parsed['nm'], 'Resolved Title');
      expect(parsed['dp'], 'Resolved Body');
    });
  });
}
