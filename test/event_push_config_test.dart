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
}
