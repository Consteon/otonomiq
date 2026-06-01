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
    final body = 'col${hollow}xx${square}hi${hollow}broken${hollow}d${square}desc';
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

  test('buildEventDoc: only DSL fields (no blank-prefill), tokens resolved', () {
    final hollow = separator[8], square = separator[2];
    final ro = forbiddenCharacter[8], rc = forbiddenCharacter[10];
    // ref[1] = form fields; ◁1▷ -> ref[1][0]
    final ref = [<String>[], ['Lift macet']];
    final block = 'vtl.event-report-incident'
        '${hollow}ty${square}report-incident'
        '${hollow}d${square}${ro}1${rc}';
    final built = buildEventDoc(block, ref,
        tableVid: 1, appVid: 2, timeReceived: 0, receivingPage: 'pg');
    expect(built.collection, 'vtl.event-report-incident');
    expect(built.doc['ty'], 'report-incident');
    expect(built.doc['d'], 'Lift macet'); // ◁1▷ resolved
    // no blank-prefill: codes not in the DSL are absent (not '')
    expect(built.doc.containsKey('r'), false);
    expect(built.doc.containsKey('rf'), false);
    expect(built.doc.containsKey('VID'), false);
    expect(built.doc.containsKey('_collection'), false);
    expect(built.doc.keys.length, 2); // exactly ty + d
  });
}
