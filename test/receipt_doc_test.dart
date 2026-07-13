import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/receipt_doc.dart';

void main() {
  // 2026-07-08 09:39 WIB == 2026-07-08 02:39:00 UTC. Derived, not a magic
  // constant, so the assertion can't drift from the intended wall-clock time.
  final int notaEpochMs =
      DateTime.utc(2026, 7, 8, 2, 39, 0).millisecondsSinceEpoch;

  // ── formatThousands ─────────────────────────────────────────────────
  group('formatThousands', () {
    test('zero', () {
      expect(formatThousands(0), '0');
    });

    test('small number no grouping', () {
      expect(formatThousands(999), '999');
    });

    test('exactly 1000', () {
      expect(formatThousands(1000), '1.000');
    });

    test('71000 -> 71.000', () {
      expect(formatThousands(71000), '71.000');
    });

    test('1250000 -> 1.250.000', () {
      expect(formatThousands(1250000), '1.250.000');
    });

    test('negative -5000 -> -5.000', () {
      expect(formatThousands(-5000), '-5.000');
    });

    test('negative -1250000 -> -1.250.000', () {
      expect(formatThousands(-1250000), '-1.250.000');
    });
  });

  // ── formatReceiptDate ───────────────────────────────────────────────
  group('formatReceiptDate', () {
    test('epoch ms -> dd Mon yyyy HH:mm (WIB)', () {
      expect(formatReceiptDate(notaEpochMs), '08 Jul 2026 09:39');
    });

    test('zero epoch', () {
      // 01 Jan 1970 07:00 WIB
      expect(formatReceiptDate(0), '01 Jan 1970 07:00');
    });
  });

  // ── extractReceiptData ──────────────────────────────────────────────
  group('extractReceiptData', () {
    final Map<String, dynamic> sampleDoc = {
      'nno': 'NOTA-2026-000001',
      't': notaEpochMs,               // epoch-ms (dateField points here)
      'ts': '2026-07-08 09:39',       // preformatted string (tolerance path)
      'by': 'Angga',
      'bym': 'Tunai',
      'st': 'LUNAS',
      'tot': 71000,
      'gl': 'depo-bintaro',
      'li': [
        {'ii': 'galon19', 'in': 'Amidis Galon 19 Liter', 'qt': 1, 'hg': 21000, 'sub': 21000},
        {'ii': 'lpg3', 'in': 'LPG 3kg', 'qt': 2, 'hg': 25000, 'sub': 50000},
      ],
    };

    final Map<String, String> fieldConfig = {
      'noField': 'nno',
      'buyerField': 'by',
      'buyerEmpty': 'Umum',
      'dateField': 't',
      'paymentField': 'bym',
      'statusField': 'st',
      'totalField': 'tot',
      'linesField': 'li',
      'lineNameField': 'in',
      'lineQtyField': 'qt',
      'linePriceField': 'hg',
      'lineSubField': 'sub',
    };

    test('extracts scalar fields by config name', () {
      final data = extractReceiptData(sampleDoc, fieldConfig);
      expect(data.no, 'NOTA-2026-000001');
      expect(data.buyer, 'Angga');
      expect(data.payment, 'Tunai');
      expect(data.status, 'LUNAS');
      expect(data.total, 71000);
      expect(data.gl, 'depo-bintaro');
    });

    test('date formatted from epoch field (t)', () {
      final data = extractReceiptData(sampleDoc, fieldConfig);
      expect(data.dateFormatted, '08 Jul 2026 09:39');
    });

    test('dateField pointing at a preformatted string shows it verbatim', () {
      // Tolerance: if the config points dateField at `ts` (a non-numeric
      // string), render it as-is instead of the 1970 epoch.
      final cfg = Map<String, String>.from(fieldConfig)..['dateField'] = 'ts';
      final data = extractReceiptData(sampleDoc, cfg);
      expect(data.dateFormatted, '2026-07-08 09:39');
    });

    test('lines extracted from li array', () {
      final data = extractReceiptData(sampleDoc, fieldConfig);
      expect(data.lines.length, 2);
      expect(data.lines[0].name, 'Amidis Galon 19 Liter');
      expect(data.lines[0].qty, 1);
      expect(data.lines[0].price, 21000);
      expect(data.lines[0].sub, 21000);
      expect(data.lines[1].name, 'LPG 3kg');
      expect(data.lines[1].qty, 2);
      expect(data.lines[1].price, 25000);
      expect(data.lines[1].sub, 50000);
    });

    test('buyerEmpty fallback when buyer is empty string', () {
      final doc = Map<String, dynamic>.from(sampleDoc);
      doc['by'] = '';
      final data = extractReceiptData(doc, fieldConfig);
      expect(data.buyer, 'Umum');
    });

    test('buyerEmpty fallback when buyer field is null', () {
      final doc = Map<String, dynamic>.from(sampleDoc);
      doc.remove('by');
      final data = extractReceiptData(doc, fieldConfig);
      expect(data.buyer, 'Umum');
    });

    test('empty li array -> zero lines', () {
      final doc = Map<String, dynamic>.from(sampleDoc);
      doc['li'] = [];
      final data = extractReceiptData(doc, fieldConfig);
      expect(data.lines.length, 0);
      expect(data.total, 71000);
    });

    test('missing li field -> zero lines', () {
      final doc = Map<String, dynamic>.from(sampleDoc);
      doc.remove('li');
      final data = extractReceiptData(doc, fieldConfig);
      expect(data.lines.length, 0);
    });

    test('total as string parses to int', () {
      final doc = Map<String, dynamic>.from(sampleDoc);
      doc['tot'] = '71000';
      final data = extractReceiptData(doc, fieldConfig);
      expect(data.total, 71000);
    });

    test('total missing -> 0', () {
      final doc = Map<String, dynamic>.from(sampleDoc);
      doc.remove('tot');
      final data = extractReceiptData(doc, fieldConfig);
      expect(data.total, 0);
    });
  });
}
