import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/add_to_event.dart';
import 'package:otonomiq/firestore_repository/table_repository.dart';
import 'package:otonomiq/global.dart';

void main() {
  final hollow = separator[8]; // ⭘
  final square = separator[2]; // ◼

  test('parses collection name + key/value pairs', () {
    final body = 'vtl.event-report-incident'
        '${hollow}r${square}4320'
        '${hollow}ty${square}report-incident';
    final m = parseAddToEvent(body);
    expect(m['_collection'], 'vtl.event-report-incident');
    expect(m['r'], '4320');
    expect(m['ty'], 'report-incident');
  });

  test('unknown char-codes pass through, malformed parts skipped', () {
    final body =
        'col${hollow}xx${square}hi${hollow}broken${hollow}d${square}desc';
    final m = parseAddToEvent(body);
    expect(m['xx'], 'hi');
    expect(m['d'], 'desc');
    expect(m.containsKey('broken'), false);
  });

  test('value containing ◼ keeps everything after the first ◼', () {
    final body = 'col${hollow}d${square}a${square}b';
    final m = parseAddToEvent(body);
    expect(m['d'], 'a${square}b');
  });

  test(
      'buildEventDoc: auto et/p/ev + DSL fields (no other blank-prefill), '
      'tokens resolved', () {
    final hollow = separator[8], square = separator[2];
    final ro = forbiddenCharacter[8], rc = forbiddenCharacter[10];
    // ref[1] = form fields; ◁1▷ -> ref[1][0]
    final ref = [
      <String>[],
      ['Lift macet'],
    ];
    final block = 'vtl.event-report-incident'
        '${hollow}ty${square}report-incident'
        '${hollow}d$square${ro}1$rc';
    final built = buildEventDoc(block, ref,
        tableVid: 1,
        appVid: 2,
        timeReceived: 1780323812536,
        receivingPage: 'pg',
        eventData: 'rawBlob');
    expect(built.collection, 'vtl.event-report-incident');
    expect(built.doc['ty'], 'report-incident');
    expect(built.doc['d'], 'Lift macet'); // ◁1▷ resolved
    // auto-injected Event-tab cols A/B/C
    expect(built.doc['et'], '1780323812536'); // A: Time
    expect(built.doc['p'], 'pg'); // B: Route
    expect(built.doc['ev'], 'rawBlob'); // C: Data blob
    // beyond et/p/ev + DSL there is no blank-prefill: absent (not '')
    expect(built.doc.containsKey('r'), false);
    expect(built.doc.containsKey('rf'), false);
    expect(built.doc.containsKey('VID'), false);
    expect(built.doc.containsKey('_collection'), false);
    expect(built.doc.keys.length, 5); // et + p + ev + ty + d
  });

  test('buildEventDoc: r coerced to int when numeric, others stay String', () {
    final hollow = separator[8], square = separator[2];
    final ref = [<String>[], <String>[]];
    final block = 'vtl.event-x'
        '${hollow}r${square}4320'
        '${hollow}an${square}83674161979544'; // numeric ID stays String
    final built = buildEventDoc(block, ref,
        tableVid: 1,
        appVid: 2,
        timeReceived: 0,
        receivingPage: 'pg',
        eventData: 'blob');
    expect(built.doc['r'], 4320); // int, not '4320'
    expect(built.doc['r'], isA<int>());
    expect(built.doc['an'], '83674161979544'); // ID stays String
    expect(built.doc['an'], isA<String>());
  });

  test('buildEventDoc: non-numeric r left as String', () {
    final hollow = separator[8], square = separator[2];
    final ref = [<String>[], <String>[]];
    final block = 'vtl.event-x${hollow}r${square}abc';
    final built = buildEventDoc(block, ref,
        tableVid: 1,
        appVid: 2,
        timeReceived: 0,
        receivingPage: 'pg',
        eventData: 'blob');
    expect(built.doc['r'], 'abc'); // untouched
  });

  test('buildEventDoc: DSL field of same key overrides auto et/p/ev', () {
    final hollow = separator[8], square = separator[2];
    final ref = [<String>[], <String>[]];
    // DSL declares p explicitly -> must win over auto receivingPage
    final block = 'vtl.event-x${hollow}p${square}dslRoute';
    final built = buildEventDoc(block, ref,
        tableVid: 1,
        appVid: 2,
        timeReceived: 99,
        receivingPage: 'autoRoute',
        eventData: 'blob');
    expect(built.doc['p'], 'dslRoute'); // DSL wins
    expect(built.doc['et'], '99'); // auto still present
    expect(built.doc['ev'], 'blob');
  });

  group('eventCollectionPath', () {
    test('new <docId>//<subColl> form: no trailing /content, odd segments', () {
      final p = eventCollectionPath('84214220504259//event', 20342033315492);
      expect(p, 'MobileTable/20342033315492/tables/84214220504259/event');
      expect(p.endsWith('/content'), isFalse);
      expect(p.split('/').length.isOdd, isTrue); // valid Firestore collection
    });
    test('legacy plain name keeps /content', () {
      final p = eventCollectionPath('vtl.report-incident', 20342033315492);
      expect(
          p, 'MobileTable/20342033315492/tables/vtl.report-incident/content');
      expect(p.split('/').length.isOdd, isTrue);
    });
    test('empty subColl after // defaults to content', () {
      final p = eventCollectionPath('84214220504259//', 5);
      expect(p, 'MobileTable/5/tables/84214220504259/content');
    });
    test('empty docId -> empty (caller skips)', () {
      expect(eventCollectionPath('//event', 5), '');
    });
  });
}
