import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/update_event_row.dart';
import 'package:otonomiq/global.dart';

void main() {
  final hollow = separator[8]; // ⭘
  final square = separator[2]; // ◼
  final star = separator[3]; // ★
  final wstar = separator[6]; // ☆

  group('parseSearchClause', () {
    test('single condition -> list of one', () {
      final c = parseSearchClause('vid${star}58111161122230');
      expect(c.length, 1);
      expect(c.first.key, 'vid');
      expect(c.first.value, '58111161122230');
    });
    test('compound AND via ☆', () {
      final c = parseSearchClause('vid${star}X${wstar}sv${star}Y');
      expect(c.length, 2);
      expect(c[0].key, 'vid');
      expect(c[0].value, 'X');
      expect(c[1].key, 'sv');
      expect(c[1].value, 'Y');
    });
    test('malformed condition (no star) skipped', () {
      final c = parseSearchClause('vid${wstar}sv${star}Y');
      expect(c.length, 1);
      expect(c.first.key, 'sv');
    });
    test('empty payload -> empty list', () {
      expect(parseSearchClause(''), isEmpty);
    });
  });

  group('parseUpdateEventRow', () {
    test('extracts collection, tablevid, conditions, sparse body', () {
      final block = '84214220504259//workforce'
          '${hollow}tablevid${square}20342033315492'
          '${hollow}search${square}vid${star}58111161122230'
          '${hollow}os${square}16:00:45'
          '${hollow}is${square}06:58:10';
      final t = parseUpdateEventRow(block);
      expect(t.collection, '84214220504259//workforce');
      expect(t.tablevid, '20342033315492');
      expect(t.conditions.length, 1);
      expect(t.conditions.first.key, 'vid');
      expect(t.conditions.first.value, '58111161122230');
      expect(t.body, {'os': '16:00:45', 'is': '06:58:10'});
      expect(t.body.containsKey('search'), false);
      expect(t.body.containsKey('tablevid'), false);
    });
    test('compound search parsed', () {
      final block = '84214220504259//workforce'
          '${hollow}tablevid${square}20342033315492'
          '${hollow}search${square}vid${star}X${wstar}sv${star}Y'
          '${hollow}st${square}on';
      final t = parseUpdateEventRow(block);
      expect(t.conditions.length, 2);
      expect(t.body, {'st': 'on'});
    });
  });
}
