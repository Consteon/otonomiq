import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/statistic_card_support.dart';

void main() {
  Map<String, dynamic> w(dynamic ci, dynamic co) => {'ci': ci, 'co': co};

  group('workerStatus', () {
    test('ci not set -> danger', () {
      expect(workerStatus(w(-1, -1)), 'danger');
      expect(workerStatus(w('', '')), 'danger');
      expect(workerStatus(w(0, 0)), 'danger');
    });
    test('ci set, co not set -> warn', () {
      expect(workerStatus(w(1780000000000, -1)), 'warn');
    });
    test('ci set and co set -> ok', () {
      expect(workerStatus(w(1780000000000, 1780000900000)), 'ok');
    });
  });

  group('workerStatusLine', () {
    test('belum scan', () => expect(workerStatusLine(w(-1, -1)), 'Belum scan'));
    test('belum clock-out',
        () => expect(workerStatusLine(w(1, -1)), 'Belum clock-out'));
    test('ok -> empty', () => expect(workerStatusLine(w(1, 2)), ''));
  });

  group('computeKehadiranList', () {
    final workers = [
      {'ci': 1, 'co': 2}, // ok
      {'ci': 1, 'co': -1}, // belum clock-out -> perluTindak
      {'ci': -1, 'co': -1}, // belum scan -> belumScan + perluTindak
      {'ci': 1700, 'co': 1800}, // ok
    ];
    final agg = computeKehadiranList(workers.cast<Map<String, dynamic>>());

    test('total counts all', () => expect(agg.total, 4));
    test('hadir counts ci-set', () => expect(agg.hadir, 3));
    test('belumScan counts ci-not-set', () => expect(agg.belumScan, 1));
    test('perluTindak = belumScan OR (ci set & co not set)',
        () => expect(agg.perluTindak, 2));

    test('toTokens exposes the four counts', () {
      final t = agg.toTokens();
      expect(t['total'], '4');
      expect(t['hadir'], '3');
      expect(t['belumScan'], '1');
      expect(t['perluTindak'], '2');
    });
  });
}
