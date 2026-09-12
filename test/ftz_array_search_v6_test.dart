import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/ftz_array_search_support.dart';

/// Friday 11 Sep 2026, 11:42 local — the clock the v6 mock draws.
final DateTime _now = DateTime(2026, 9, 11, 11, 42);

int _msAt(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime(y, m, d, h, min).millisecondsSinceEpoch;

void main() {
  group('reportTone — three levels, not one indigo chip', () {
    test('the values the patrol form actually writes', () {
      expect(reportTone('Aman kondusif'), ReportTone.ok);
      expect(reportTone('Perlu tindak lanjut'), ReportTone.warn);
    });

    test('the three levels the v6 mock draws', () {
      expect(reportTone('Aman kondusif'), ReportTone.ok);
      expect(reportTone('Perlu perhatian'), ReportTone.warn);
      expect(reportTone('Insiden'), ReportTone.err);
    });

    test('danger words beat the ok words they contain', () {
      // "Tidak aman" contains "aman". Reversing the two loops turns a red chip
      // green, which is the one mistake this screen must not make.
      expect(reportTone('Tidak aman'), ReportTone.err);
      expect(reportTone('Kondisi tidak aman di lobi'), ReportTone.err);
    });

    test('"ok" only counts as the whole value', () {
      expect(reportTone('ok'), ReportTone.ok);
      expect(reportTone('OKE'), ReportTone.ok);
      // Would be green on a naive `contains('ok')`.
      expect(reportTone('Lokasi baru'), ReportTone.neutral);
      expect(reportTone('Diblokir portal'), ReportTone.neutral);
    });

    test('unknown and empty are neutral, never coloured by accident', () {
      expect(reportTone(''), ReportTone.neutral);
      expect(reportTone('   '), ReportTone.neutral);
      expect(reportTone('Kunjungan rutin'), ReportTone.neutral);
    });
  });

  group('reportEpoch — row[0] is a stamp, or it is nothing', () {
    test('a real addContent stamp parses', () {
      final int ms = _msAt(2026, 9, 11, 11, 47);
      expect(reportEpoch(<dynamic>['$ms', 'x'], _now), ms);
    });

    test('an int, not just a String, is accepted', () {
      final int ms = _msAt(2026, 9, 11, 9, 22);
      expect(reportEpoch(<dynamic>[ms], _now), ms);
    });

    test('a 14-digit yyyyMMddHHmmss id is NOT read as epoch ms', () {
      // 20260911114700 ms lands in the year 2612. Without the upper bound it
      // clears the 2010 floor and every row groups under one absurd day.
      expect(reportEpoch(<dynamic>['20260911114700'], _now), isNull);
    });

    test('values below the 2010 floor are sequence numbers, not stamps', () {
      expect(reportEpoch(<dynamic>['1'], _now), isNull);
      expect(reportEpoch(<dynamic>['${kMinReportEpochMs - 1}'], _now), isNull);
      expect(
        reportEpoch(<dynamic>['$kMinReportEpochMs'], _now),
        kMinReportEpochMs,
      );
    });

    test('a clock-skewed device is still trusted up to a year ahead', () {
      final int soon = _now.millisecondsSinceEpoch + 86400000;
      expect(reportEpoch(<dynamic>['$soon'], _now), soon);
    });

    test('non-numeric keys and empty rows give up quietly', () {
      expect(reportEpoch(<dynamic>['abc'], _now), isNull);
      expect(reportEpoch(<dynamic>[], _now), isNull);
      expect(reportEpoch(<dynamic>[''], _now), isNull);
    });
  });

  group('day headers read like the Log tab', () {
    test('today, yesterday, and anything older', () {
      expect(
        reportDayHeader(DateTime(2026, 9, 11, 23, 59), _now),
        'Hari ini · Jumat, 11 Sep',
      );
      expect(
        reportDayHeader(DateTime(2026, 9, 10, 0, 1), _now),
        'Kemarin · Kamis, 10 Sep',
      );
      expect(reportDayHeader(DateTime(2026, 9, 9), _now), 'Rabu, 9 Sep');
    });

    test('the clock never decides the day', () {
      // 00:01 today is still today even though it is 11h before `now`.
      expect(
        reportDayHeader(DateTime(2026, 9, 11, 0, 1), _now),
        startsWith('Hari ini'),
      );
    });

    test('month names are Indonesian', () {
      expect(reportDayHeader(DateTime(2026, 8, 5), _now), 'Rabu, 5 Agu');
      expect(reportDayHeader(DateTime(2026, 5, 1), _now), 'Jumat, 1 Mei');
      expect(reportDayHeader(DateTime(2026, 12, 25), _now), 'Jumat, 25 Des');
    });
  });

  test('reportClock pads both fields', () {
    expect(reportClock(DateTime(2026, 9, 11, 9, 5)), '09:05');
    expect(reportClock(DateTime(2026, 9, 11, 16, 5)), '16:05');
    expect(reportClock(DateTime(2026, 9, 11, 0, 0)), '00:00');
  });

  group('inReportRange — the chips are a view, never a gate', () {
    test('Hari ini is the calendar day, not 24 hours', () {
      expect(inReportRange(_msAt(2026, 9, 11, 0, 1), ReportRange.today, _now),
          isTrue);
      expect(inReportRange(_msAt(2026, 9, 10, 23, 59), ReportRange.today, _now),
          isFalse);
    });

    test('7 hari and 30 hari at their edges', () {
      expect(
          inReportRange(_msAt(2026, 9, 5), ReportRange.week, _now), isTrue); // 6
      expect(inReportRange(_msAt(2026, 9, 4), ReportRange.week, _now),
          isFalse); // 7
      expect(inReportRange(_msAt(2026, 8, 13), ReportRange.month, _now),
          isTrue); // 29
      expect(inReportRange(_msAt(2026, 8, 12), ReportRange.month, _now),
          isFalse); // 30
    });

    test('Semua keeps everything', () {
      expect(inReportRange(_msAt(2020, 1, 1), ReportRange.all, _now), isTrue);
      expect(inReportRange(null, ReportRange.all, _now), isTrue);
    });

    test('an undatable row is never hidden by a range', () {
      for (final ReportRange r in ReportRange.values) {
        expect(inReportRange(null, r, _now), isTrue, reason: '$r');
      }
    });

    test('a future stamp is never hidden either', () {
      expect(inReportRange(_msAt(2027, 1, 1), ReportRange.today, _now), isTrue);
    });

    test('every chip has a label and a sentence form', () {
      expect(kReportRangeChips.length, ReportRange.values.length);
      expect(kReportRangeSummary.length, ReportRange.values.length);
    });
  });

  group('highlightSpans', () {
    test('no query leaves one plain run', () {
      final List<HighlightSpan> s = highlightSpans('Lampu koridor', '');
      expect(s.length, 1);
      expect(s.first.hit, isFalse);
      expect(s.first.text, 'Lampu koridor');
    });

    test('marks the match and keeps the original casing', () {
      final List<HighlightSpan> s =
          highlightSpans('Lampu koridor lantai 2 mati', 'lampu');
      expect(s.map((HighlightSpan e) => e.text).join(),
          'Lampu koridor lantai 2 mati');
      expect(s.first.text, 'Lampu');
      expect(s.first.hit, isTrue);
    });

    test('every occurrence is marked, not just the first', () {
      final List<HighlightSpan> s = highlightSpans('mati, lalu mati lagi', 'mati');
      expect(s.where((HighlightSpan e) => e.hit).length, 2);
      expect(s.map((HighlightSpan e) => e.text).join(), 'mati, lalu mati lagi');
    });

    test('no match still renders the whole string once', () {
      final List<HighlightSpan> s = highlightSpans('Aman kondusif', 'xyz');
      expect(s.length, 1);
      expect(s.first.hit, isFalse);
    });

    test('an empty value does not crash the row', () {
      expect(highlightSpans('', 'lampu').single.text, '');
    });
  });

  group('reportSubline', () {
    ContentRoles roles(List<String> values) => ContentRoles(
          eyebrow: const ContentLine('Tanggal', '11 Sep 2026 11:47'),
          title: ContentLine('Nama', values[0]),
          meta: <ContentLine>[
            for (int i = 1; i < values.length; i++)
              ContentLine('F$i', values[i]),
          ],
          note: const ContentLine('Keterangan', 'catatan'),
        );

    test('joins the name and every meta field in template order', () {
      expect(
        reportSubline(roles(<String>['Agenia Demo-7', 'BSD #26', 'Product Group'])),
        'Agenia Demo-7 · BSD #26 · Product Group',
      );
    });

    test('drops blanks instead of printing empty separators', () {
      expect(
        reportSubline(roles(<String>['', 'BSD #26', '  '])),
        'BSD #26',
      );
    });

    test('an empty role set gives an empty line, not " · "', () {
      expect(reportSubline(const ContentRoles()), '');
    });
  });

  group('isPlaceLabel', () {
    test('place and building words go to the head line', () {
      for (final String l in <String>[
        'Lokasi',
        'Alamat',
        'Posisi',
        'Site',
        'Area',
        'Gedung',
        'SITE KERJA',
      ]) {
        expect(isPlaceLabel(l), isTrue, reason: l);
      }
    });

    test('everything else stays in the metadata table', () {
      for (final String l in <String>[
        'Nama',
        'Jenis',
        'Kondisi',
        'Keterangan',
        'Tanggal',
        '',
      ]) {
        expect(isPlaceLabel(l), isFalse, reason: l);
      }
    });
  });

  group('splitDetailRoles — the live patrol detail template', () {
    // Tanggal / Nama / Lokasi / Site / Kondisi / Keterangan, as op1Screen!N574
    // authors it today.
    final List<ContentLine> patrol = parseContentLines(
      'Tanggal: 11 Sep 2026 11:47\n'
      'Nama: Agenia Demo-7\n'
      'Lokasi: BSD Tech Center #26\n'
      'Site: Product Group\n'
      'Kondisi: Aman kondusif\n'
      'Keterangan: Pengecekan area parkir dan lobi.',
    );

    test('the condition becomes the chip and leaves the table', () {
      final DetailRoles r = splitDetailRoles(patrol, '');
      expect(r.chip, 'Aman kondusif');
      expect(r.meta.map((ContentLine l) => l.label), isNot(contains('Kondisi')));
    });

    test('place fields go to the head, the rest to the table', () {
      final DetailRoles r = splitDetailRoles(patrol, '');
      expect(r.place.map((ContentLine l) => l.label), <String>['Lokasi', 'Site']);
      expect(r.meta.map((ContentLine l) => l.label), <String>['Nama']);
    });

    test('first line is the stamp, last line is the note', () {
      final DetailRoles r = splitDetailRoles(patrol, '');
      expect(r.stampText, '11 Sep 2026 11:47');
      expect(r.note!.label, 'Keterangan');
      expect(r.note!.value, 'Pengecekan area parkir dan lobi.');
    });

    test('nothing is dropped: every middle line lands somewhere', () {
      final DetailRoles r = splitDetailRoles(patrol, '');
      final Set<String> placed = <String>{
        ...r.place.map((ContentLine l) => l.label),
        ...r.meta.map((ContentLine l) => l.label),
        if (r.chip.isNotEmpty) 'Kondisi',
      };
      expect(placed, <String>{'Nama', 'Lokasi', 'Site', 'Kondisi'});
    });

    test('an explicit chipLabel wins over the keyword guess', () {
      final DetailRoles r = splitDetailRoles(patrol, 'Nama');
      expect(r.chip, 'Agenia Demo-7');
      // The condition then falls back into the table rather than vanishing.
      expect(r.meta.map((ContentLine l) => l.label), contains('Kondisi'));
    });

    test('an unmapped label lands in the table, never nowhere', () {
      final DetailRoles r = splitDetailRoles(
        parseContentLines(
          'Tanggal: x\nShift: Malam\nKondisi: Insiden\nKeterangan: y',
        ),
        '',
      );
      expect(r.meta.map((ContentLine l) => l.label), <String>['Shift']);
      expect(r.chip, 'Insiden');
    });

    test('degenerate blobs do not throw', () {
      expect(splitDetailRoles(const <ContentLine>[], '').note, isNull);
      final DetailRoles one =
          splitDetailRoles(parseContentLines('cuma satu baris'), '');
      expect(one.note!.value, 'cuma satu baris');
      expect(one.stampText, 'cuma satu baris');
      final DetailRoles two =
          splitDetailRoles(parseContentLines('Tanggal: a\nKeterangan: b'), '');
      expect(two.stampText, 'a');
      expect(two.note!.value, 'b');
      expect(two.place, isEmpty);
      expect(two.meta, isEmpty);
    });
  });

  group('detail head and photo caption', () {
    final List<ContentLine> patrol = parseContentLines(
      'Tanggal: 11 Sep 2026 11:47\n'
      'Nama: Agenia Demo-7\n'
      'Lokasi: BSD Tech Center #26\n'
      'Site: Product Group\n'
      'Kondisi: Aman kondusif\n'
      'Keterangan: catatan',
    );

    test('reportLongDate carries the year the list header omits', () {
      expect(reportLongDate(DateTime(2026, 9, 11)), 'Jumat, 11 Sep 2026');
      expect(reportLongDate(DateTime(2026, 8, 5)), 'Rabu, 5 Agu 2026');
    });

    test('the head line is long date then every place value', () {
      final DetailRoles r = splitDetailRoles(patrol, '');
      expect(
        detailHeadSubline(r, _msAt(2026, 9, 11, 11, 47)),
        'Jumat, 11 Sep 2026 · BSD Tech Center #26 · Product Group',
      );
    });

    test('no epoch falls back to the template text, never to a blank', () {
      final DetailRoles r = splitDetailRoles(patrol, '');
      expect(
        detailHeadSubline(r, null),
        '11 Sep 2026 11:47 · BSD Tech Center #26 · Product Group',
      );
    });

    test('the caption adds the clock and stays place-suffixed', () {
      final DetailRoles r = splitDetailRoles(patrol, '');
      expect(
        photoCaption(r, _msAt(2026, 9, 11, 11, 47)),
        'Jumat, 11 Sep 2026 · 11:47 · BSD Tech Center #26 · Product Group',
      );
      expect(photoCaption(r, null), startsWith('11 Sep 2026 11:47 · '));
    });

    test('no place fields still yields a clean line, not a trailing dot', () {
      final DetailRoles r = splitDetailRoles(
        parseContentLines('Tanggal: a\nNama: b\nKeterangan: c'),
        '',
      );
      expect(detailHeadSubline(r, _msAt(2026, 9, 11)), 'Jumat, 11 Sep 2026');
    });
  });

  group('a template with no condition field — LogReportRoutine', () {
    // op1Screen!N1284, page vertikaTeknoLokaciptaLogReportRoutine. Five lines,
    // no `Kondisi`: the routine report simply has no condition to state.
    final List<ContentLine> routine = parseContentLines(
      'Tanggal: 11 Sep 2026 10:00\n'
      'Nama: Agenia Demo-7\n'
      'Lokasi: BSD Tech Center #26\n'
      'Site: Product Group\n'
      'Keterangan: kontrol rutin selesai',
    );

    test('the card draws no chip rather than inventing one', () {
      final ContentRoles r = splitContentRoles(routine, '');
      expect(r.chip, '');
      expect(r.eyebrow!.label, 'Tanggal');
      expect(r.title!.label, 'Nama');
      expect(r.note!.value, 'kontrol rutin selesai');
      expect(r.meta.map((ContentLine l) => l.label), <String>['Lokasi', 'Site']);
    });

    test('the card subline still carries every field', () {
      expect(
        reportSubline(splitContentRoles(routine, '')),
        'Agenia Demo-7 · BSD Tech Center #26 · Product Group',
      );
    });

    test('the sheet head has no chip and loses nothing', () {
      final DetailRoles r = splitDetailRoles(routine, '');
      expect(r.chip, '');
      expect(r.place.map((ContentLine l) => l.label), <String>['Lokasi', 'Site']);
      expect(r.meta.map((ContentLine l) => l.label), <String>['Nama']);
      expect(r.note!.value, 'kontrol rutin selesai');
      expect(
        detailHeadSubline(r, _msAt(2026, 9, 11, 10, 0)),
        'Jumat, 11 Sep 2026 · BSD Tech Center #26 · Product Group',
      );
    });

    test('an absent condition is not confused with a neutral one', () {
      // `reportTone('')` is neutral, but the row must not draw a neutral chip
      // for a field the template never had — chip stays the empty string.
      expect(splitContentRoles(routine, '').chip, isEmpty);
      expect(reportTone(''), ReportTone.neutral);
    });
  });
}
