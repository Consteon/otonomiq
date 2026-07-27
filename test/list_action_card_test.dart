import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/list_action_card.dart';

void main() {
  // ── parseActionMeta ──────────────────────────────────────────────────────

  group('parseActionMeta', () {
    test('parses 2-action happy path with posisiNote', () {
      final metas = parseActionMeta(
          'ok\u{25FC}reward-approve'
          '\u{25C6}danger\u{25FC}reward-reject\u{25FC}5');
      expect(metas.length, 2);
      expect(metas[0].tone, 'ok');
      expect(metas[0].flag, 'reward-approve');
      expect(metas[0].notePosition, isNull);
      expect(metas[1].tone, 'danger');
      expect(metas[1].flag, 'reward-reject');
      expect(metas[1].notePosition, 5);
    });

    test('single action without posisiNote', () {
      final metas = parseActionMeta('warn\u{25FC}some-flag');
      expect(metas.length, 1);
      expect(metas[0].tone, 'warn');
      expect(metas[0].flag, 'some-flag');
      expect(metas[0].notePosition, isNull);
    });

    test('empty string returns empty list', () {
      expect(parseActionMeta(''), isEmpty);
      expect(parseActionMeta('  '), isEmpty);
    });

    test('unknown tone normalizes to neutral', () {
      final metas = parseActionMeta('banana\u{25FC}flag');
      expect(metas.length, 1);
      expect(metas[0].tone, 'neutral');
    });

    test('missing flag yields empty string', () {
      final metas = parseActionMeta('ok');
      expect(metas.length, 1);
      expect(metas[0].tone, 'ok');
      expect(metas[0].flag, '');
      expect(metas[0].notePosition, isNull);
    });

    test('trailing diamond does not produce extra entry', () {
      final metas = parseActionMeta('ok\u{25FC}f1\u{25C6}');
      expect(metas.length, 1);
    });

    test('posisiNote non-numeric is ignored (null)', () {
      final metas = parseActionMeta('ok\u{25FC}flag\u{25FC}abc');
      expect(metas.length, 1);
      expect(metas[0].notePosition, isNull);
    });
  });

  // ── parseListActionFields ─────────────────────────────────────────────────

  group('parseListActionFields', () {
    test('parses 6-segment happy path', () {
      final f = parseListActionFields(
          '<cn>\u{25C6}<pl>\u{25C6}i\u{25C6}<ts>\u{25C6}fl\u{25C6}'
          'sample\u{25FC}Sampel\u{25FC}neutral');
      expect(f.titleTpl, '<cn>');
      expect(f.subtitleTpl, '<pl>');
      expect(f.imageField, 'i');
      expect(f.metaTpl, '<ts>');
      expect(f.badgeField, 'fl');
      expect(f.rawBadgeMap, 'sample\u{25FC}Sampel\u{25FC}neutral');
    });

    test('short fields array fills defaults', () {
      final f = parseListActionFields('<cn>\u{25C6}<pl>');
      expect(f.titleTpl, '<cn>');
      expect(f.subtitleTpl, '<pl>');
      expect(f.imageField, '');
      expect(f.metaTpl, '');
      expect(f.badgeField, '');
      expect(f.rawBadgeMap, '');
    });

    test('empty string returns all-empty fields', () {
      final f = parseListActionFields('');
      // diamondTextToList('') returns [''], so seg[0] = ''
      expect(f.titleTpl, '');
      expect(f.subtitleTpl, '');
      expect(f.imageField, '');
    });
  });

  // ── resolveActionTokensOrAbort ────────────────────────────────────────────

  group('resolveActionTokensOrAbort', () {
    test('resolves all tokens from row doc', () {
      const dsl = 'table//coll\u{2B58}search\u{25FC}ck\u{2605}{ck}\u{2B58}st\u{25FC}approved';
      final doc = <String, dynamic>{'ck': 'abc-123'};
      final result = resolveActionTokensOrAbort(dsl, doc);
      expect(result, isNotNull);
      expect(result!.contains('{'), isFalse);
      expect(result.contains('abc-123'), isTrue);
    });

    test('returns null when token field is absent in doc', () {
      const dsl = 'table//coll\u{2B58}search\u{25FC}ck\u{2605}{ck}';
      final doc = <String, dynamic>{'cn': 'Dedi'};
      final result = resolveActionTokensOrAbort(dsl, doc);
      expect(result, isNull);
    });

    test('returns null when token field is empty string in doc', () {
      const dsl = 'table//coll\u{2B58}search\u{25FC}ck\u{2605}{ck}';
      final doc = <String, dynamic>{'ck': ''};
      final result = resolveActionTokensOrAbort(dsl, doc);
      expect(result, isNull);
    });

    test('DSL without tokens passes through unchanged', () {
      const dsl = 'table//coll\u{2B58}st\u{25FC}approved';
      final doc = <String, dynamic>{'ck': 'abc'};
      final result = resolveActionTokensOrAbort(dsl, doc);
      expect(result, dsl);
    });

    test('multiple tokens all resolved', () {
      const dsl = '{a}-{b}';
      final doc = <String, dynamic>{'a': 'X', 'b': 'Y'};
      final result = resolveActionTokensOrAbort(dsl, doc);
      expect(result, 'X-Y');
    });

    test('one resolved one absent returns null (ABORT)', () {
      const dsl = '{a}-{b}';
      final doc = <String, dynamic>{'a': 'X'};
      final result = resolveActionTokensOrAbort(dsl, doc);
      expect(result, isNull);
    });

    test('numeric value resolved as string', () {
      const dsl = 'v={n}';
      final doc = <String, dynamic>{'n': 42};
      final result = resolveActionTokensOrAbort(dsl, doc);
      expect(result, 'v=42');
    });
  });

  // ── parseSortConfig ───────────────────────────────────────────────────────

  group('parseSortConfig', () {
    test('parses field and asc direction', () {
      final s = parseSortConfig('t\u{25FC}asc');
      expect(s.field, 't');
      expect(s.descending, isFalse);
    });

    test('parses desc direction', () {
      final s = parseSortConfig('amount\u{25FC}desc');
      expect(s.field, 'amount');
      expect(s.descending, isTrue);
    });

    test('no separator yields field only, default asc', () {
      final s = parseSortConfig('t');
      expect(s.field, 't');
      expect(s.descending, isFalse);
    });

    test('empty string yields empty field', () {
      final s = parseSortConfig('');
      expect(s.field, '');
      expect(s.descending, isFalse);
    });
  });
}
