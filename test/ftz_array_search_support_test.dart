import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/ftz_array_search_support.dart';

void main() {
  group('parseContentLines', () {
    test('parses the live Harian content blob', () {
      // Exactly what op1Screen!B594 renders through replaceMarker.
      const String rendered =
          'Tanggal: 05 Aug 2026 10:05\n'
          'Nama: Agenia Demo-7\n'
          'Jenis Laporan: Kejadian\n'
          'Lokasi: BSD Tech Center #26\n'
          'Site: Product Group\n'
          'Keterangan: ada apa ya';

      final lines = parseContentLines(rendered);

      expect(lines.length, 6);
      expect(lines[0].label, 'Tanggal');
      // The clock ':' must NOT become a second split point.
      expect(lines[0].value, '05 Aug 2026 10:05');
      expect(lines[2].label, 'Jenis Laporan');
      expect(lines[2].value, 'Kejadian');
      expect(lines.last.label, 'Keterangan');
      expect(lines.last.value, 'ada apa ya');
    });

    test('a bare clock time is a value, not a label:value pair', () {
      final lines = parseContentLines('10:05');
      expect(lines.length, 1);
      expect(lines[0].label, '');
      expect(lines[0].value, '10:05');
    });

    test('a long leading segment is prose, not a label', () {
      const String prose =
          'Petugas melaporkan hal berikut: pagar sisi utara rusak';
      final lines = parseContentLines(prose);
      expect(lines.length, 1);
      expect(lines[0].label, '');
      expect(lines[0].value, prose);
    });

    test('a leading segment exactly at the length limit is still a label', () {
      final String label = 'A' * maxContentLabelLength;
      final lines = parseContentLines('$label: x');
      expect(lines[0].label, label);
      expect(lines[0].value, 'x');
    });

    test('one char over the limit is not a label', () {
      final String label = 'A' * (maxContentLabelLength + 1);
      final lines = parseContentLines('$label: x');
      expect(lines[0].label, '');
      expect(lines[0].value, '$label: x');
    });

    test('empty and whitespace-only lines are dropped', () {
      final lines = parseContentLines('Nama: Budi\n\n   \nSite: HQ');
      expect(lines.length, 2);
      expect(lines[0].label, 'Nama');
      expect(lines[1].label, 'Site');
    });

    test('empty input yields no lines', () {
      expect(parseContentLines('').isEmpty, isTrue);
      expect(parseContentLines('   \n  ').isEmpty, isTrue);
    });

    test('a line with no colon keeps its whole text as the value', () {
      final lines = parseContentLines('sekedar catatan bebas');
      expect(lines[0].label, '');
      expect(lines[0].value, 'sekedar catatan bebas');
    });

    test('an empty value keeps its label', () {
      final lines = parseContentLines('Site: ');
      expect(lines.length, 1);
      expect(lines[0].label, 'Site');
      expect(lines[0].value, '');
    });

    test('a leading colon is not a label', () {
      final lines = parseContentLines(': orphan');
      expect(lines[0].label, '');
      expect(lines[0].value, ': orphan');
    });

    test('label and value are trimmed around a spaced colon', () {
      final lines = parseContentLines('Lokasi :   Gudang B  ');
      expect(lines[0].label, 'Lokasi');
      expect(lines[0].value, 'Gudang B');
    });
  });

  group('indexOfLabel', () {
    final lines = parseContentLines(
      'Tanggal: 1 Jan\nNama: Budi\nJenis Laporan: Kejadian',
    );

    test('matches case-insensitively', () {
      expect(indexOfLabel(lines, 'jenis laporan'), 2);
      expect(indexOfLabel(lines, '  Nama  '), 1);
    });

    test('returns -1 for a missing label', () {
      expect(indexOfLabel(lines, 'Kondisi'), -1);
    });

    test('an empty needle never matches an unlabelled line', () {
      final unlabelled = parseContentLines('plain text');
      expect(unlabelled[0].label, '');
      expect(indexOfLabel(unlabelled, ''), -1);
      expect(indexOfLabel(unlabelled, '   '), -1);
    });
  });

  group('chipLineIndex', () {
    // The five live report screens, as authored in op1Screen.
    final daily = parseContentLines(
      'Tanggal: 1 Jan\nNama: Budi\nJenis Laporan: Kejadian\n'
      'Lokasi: BSD\nSite: PG\nKeterangan: catatan',
    );
    final routine = parseContentLines(
      'Tanggal: 1 Jan\nNama: Budi\nLokasi: BSD\nSite: PG\nKeterangan: catatan',
    );
    final patrol = parseContentLines(
      'Tanggal: 1 Jan\nNama: Budi\nLokasi: BSD\nSite: PG\n'
      'Kondisi: Aman\nKeterangan: catatan',
    );

    int chipOf(List<ContentLine> lines, [String cfg = '']) =>
        chipLineIndex(lines, cfg, from: 2, to: lines.length - 1);

    test('auto-picks the category field on the daily report', () {
      expect(chipOf(daily), 2);
      expect(daily[2].value, 'Kejadian');
    });

    test('auto-picks Kondisi even when it is not the first meta row', () {
      expect(chipOf(patrol), 4);
    });

    test('picks nothing when no field is a category', () {
      expect(chipOf(routine), -1);
    });

    test('an explicit chipLabel overrides the keyword guess', () {
      expect(chipOf(daily, 'Site'), 4);
    });

    test('an explicit chipLabel outside the meta range is refused', () {
      // Tanggal is the eyebrow and Keterangan the note — chipping either would
      // render that value twice on the card.
      expect(chipOf(daily, 'Tanggal'), -1);
      expect(chipOf(daily, 'Keterangan'), -1);
    });

    test('an explicit chipLabel that does not exist yields no chip', () {
      expect(chipOf(daily, 'Nomor Polisi'), -1);
    });

    test('a long category value is left as a meta row', () {
      final long = parseContentLines(
        'Tanggal: 1 Jan\nNama: Budi\n'
        'Jenis Laporan: ${'x' * (maxChipValueLength + 1)}\n'
        'Keterangan: catatan',
      );
      expect(chipOf(long), -1);
    });

    test('an empty category value is not chipped', () {
      final blank = parseContentLines(
        'Tanggal: 1 Jan\nNama: Budi\nJenis Laporan: \nKeterangan: catatan',
      );
      expect(chipOf(blank), -1);
    });

    test('a short list has no meta range and so no chip', () {
      final two = parseContentLines('Tanggal: 1 Jan\nJenis: X');
      expect(chipLineIndex(two, '', from: 2, to: two.length - 1), -1);
    });
  });

  group('splitContentRoles', () {
    test('maps a production vtl.report-daily row onto the card slots', () {
      // Verbatim Firestore doc MobileTable/60936087747650/tables/
      // vtl.report-daily/content/2veyV56SBAaggiYl24tt, run through the
      // op1Screen!B594 `content` template (indexStart:1 → <n> = row[n], where
      // row = [sortKey, ...c]).
      final roles = splitContentRoles(
        parseContentLines(
          'Tanggal: 05 Aug 2026 10:05\n'
          'Nama: Agenia Demo-7\n'
          'Jenis Laporan: Kejadian\n'
          'Lokasi: BSD Tech Center #26\n'
          'Site: Product Group\n'
          'Keterangan: ada apa ya',
        ),
        '', // no chipLabel authored — the keyword guess must find it
      );

      expect(roles.eyebrow!.value, '05 Aug 2026 10:05');
      expect(roles.title!.value, 'Agenia Demo-7');
      expect(roles.chip, 'Kejadian');
      expect(roles.note!.value, 'ada apa ya');
      // Jenis Laporan was lifted into the chip, so it must NOT repeat here.
      expect(roles.meta.map((l) => l.label).toList(), ['Lokasi', 'Site']);
      expect(roles.meta.map((l) => l.value).toList(), [
        'BSD Tech Center #26',
        'Product Group',
      ]);
    });

    test('a routine report (no category field) keeps all three meta rows', () {
      final roles = splitContentRoles(
        parseContentLines(
          'Tanggal: 1 Jan\nNama: Budi\nLokasi: BSD\nSite: PG\n'
          'Keterangan: catatan',
        ),
        '',
      );
      expect(roles.chip, '');
      expect(roles.meta.map((l) => l.label).toList(), ['Lokasi', 'Site']);
      expect(roles.note!.value, 'catatan');
    });

    test('three lines = eyebrow + title + note, no meta', () {
      final roles = splitContentRoles(
        parseContentLines('Tanggal: 1 Jan\nNama: Budi\nKeterangan: catatan'),
        '',
      );
      expect(roles.meta, isEmpty);
      expect(roles.note!.value, 'catatan');
      expect(roles.chip, '');
    });

    test('two lines lose the note rather than reusing the title', () {
      final roles = splitContentRoles(
        parseContentLines('Tanggal: 1 Jan\nNama: Budi'),
        '',
      );
      expect(roles.eyebrow!.value, '1 Jan');
      expect(roles.title!.value, 'Budi');
      expect(roles.note, isNull);
      expect(roles.meta, isEmpty);
    });

    test('one line is title-only — no eyebrow, no note', () {
      final roles = splitContentRoles(parseContentLines('Nama: Budi'), '');
      expect(roles.title!.value, 'Budi');
      expect(roles.eyebrow, isNull);
      expect(roles.note, isNull);
    });

    test('empty input yields empty roles', () {
      final roles = splitContentRoles(const [], '');
      expect(roles.title, isNull);
      expect(roles.eyebrow, isNull);
      expect(roles.note, isNull);
      expect(roles.meta, isEmpty);
      expect(roles.chip, '');
    });

    test('an explicit chipLabel removes that row from meta, not another', () {
      final roles = splitContentRoles(
        parseContentLines(
          'Tanggal: 1 Jan\nNama: Budi\nJenis Laporan: Kejadian\n'
          'Lokasi: BSD\nSite: PG\nKeterangan: catatan',
        ),
        'Site',
      );
      expect(roles.chip, 'PG');
      expect(roles.meta.map((l) => l.label).toList(), [
        'Jenis Laporan',
        'Lokasi',
      ]);
    });
  });

  group('rowSplit — parseContentLinesSplit', () {
    // Stand-in for the widget's per-line render callback. It substitutes the
    // markers this fixture defines and folds a literal `\n`, exactly as
    // _renderContent does. A marker with NO fixture entry survives verbatim —
    // which is precisely what replaceMarker does for a <N> past the end of the
    // row, because it only loops `i < ref.length` (global.dart:1300).
    String Function(String) renderer(Map<int, String> values) => (String line) {
      String out = line;
      values.forEach((int k, String v) {
        out = out.replaceAll('<$k>', v);
      });
      return out.replaceAll('\\n', '\n');
    };

    // op1Screen!D1619 `detail`, verbatim. The JSON \n escapes decode to real
    // line breaks; the lone " " line is the spacer the sheet author added.
    const String liveDetail =
        'Tanggal: <2>\nJenis: <30>\nLokasi: <8>\nSite: <6>\nKeterangan: <9>\n \n'
        '<11>\n<12>\n<13>\n<14>\n<15>\n<16>\n<17>\n<18>\n<19>';

    // Firestore MobileTable/60936087747650/tables/84214220504259/
    // report-checklist, doc of 25 Aug 2026 11:17. indexStart:1 -> <N> = c[N-1].
    // <16> is the CHECKLIST_DYNAMIC empty-slot sentinel; <17>..<19> are blank.
    const Map<int, String> liveRow = <int, String>{
      2: '25 Aug 2026 11:17',
      6: 'Product Group',
      8: 'BSD Tech Center #26',
      9: 'hahaha',
      11: 'Sapu halaman dan area pedestrian|Selesai',
      12: 'Buang sampah dan kosongkan tempat sampah|Selesai',
      13: 'Bersihkan asbak dan smoking area|Selesai',
      14: 'Siram/semprot area jika perlu (debu, noda)|Selesai',
      15: 'Bersihkan saluran air (jika ada)|Selesai',
      16: '*',
      17: '',
      18: '',
      19: '',
      30: 'Outdoor',
    };

    /// One bare `<11>` template line carrying [value].
    List<ContentLine> bare(String value) => parseContentLinesSplit(
          '<11>',
          '|',
          renderer(<int, String>{11: value}),
        );

    test('renders the live LogChecklist detail as stacked header/value', () {
      final lines = parseContentLinesSplit(liveDetail, '|', renderer(liveRow));

      expect(lines.map((l) => l.label).toList(), [
        'Tanggal',
        'Jenis',
        'Lokasi',
        'Site',
        'Keterangan',
        'Sapu halaman dan area pedestrian',
        'Buang sampah dan kosongkan tempat sampah',
        'Bersihkan asbak dan smoking area',
        'Siram/semprot area jika perlu (debu, noda)',
        'Bersihkan saluran air (jika ada)',
      ]);
      expect(lines.map((l) => l.value).toList(), [
        '25 Aug 2026 11:17',
        'Outdoor',
        'BSD Tech Center #26',
        'Product Group',
        'hahaha',
        'Selesai',
        'Selesai',
        'Selesai',
        'Selesai',
        'Selesai',
      ]);
      // 15 template lines -> 10 rendered: the " " spacer, the `*` slot and the
      // three blank slots are all dropped.
      expect(lines.length, 10);
    });

    test('rowSplit OFF leaves the same template exactly as it renders today', () {
      // The regression guard. This is the untouched pre-rowSplit path.
      final lines = parseContentLines(renderer(liveRow)(liveDetail));

      expect(lines.length, 11);
      // The task stays ONE unlabelled line with the raw pipe in it.
      expect(lines[5].label, '');
      expect(lines[5].value, 'Sapu halaman dan area pedestrian|Selesai');
      // And the sentinel is NOT dropped when rowSplit is off.
      expect(lines.last.label, '');
      expect(lines.last.value, '*');
    });

    test('a blank separator falls back to the untouched single-pass path', () {
      final off = parseContentLines(renderer(liveRow)(liveDetail));
      final viaFn = parseContentLinesSplit(liveDetail, '', renderer(liveRow));

      expect(viaFn.map((l) => l.label).toList(),
          off.map((l) => l.label).toList());
      expect(viaFn.map((l) => l.value).toList(),
          off.map((l) => l.value).toList());
      expect(viaFn.last.value, '*'); // skip rule must NOT apply when off
    });

    test('a whitespace-only separator is off too', () {
      final viaFn = parseContentLinesSplit(liveDetail, '   ', renderer(liveRow));
      expect(viaFn.length, 11);
      expect(viaFn.last.value, '*');
    });

    test('splits a pipe written without spaces (legacy TASKLIST writer)', () {
      final line = bare('task|status').single;
      expect(line.label, 'task');
      expect(line.value, 'status');
    });

    test('splits a pipe written with spaces (CHECKLIST_DYNAMIC writer)', () {
      final line = bare('task | status').single;
      expect(line.label, 'task');
      expect(line.value, 'status');
    });

    test('splits at the FIRST separator only', () {
      final line = bare('a|b|c').single;
      expect(line.label, 'a');
      expect(line.value, 'b|c');
    });

    test('a leading separator yields a header-less line', () {
      final line = bare('|Selesai').single;
      expect(line.label, '');
      expect(line.value, 'Selesai');
    });

    test('a trailing separator keeps the header and an empty value', () {
      final line = bare('task|').single;
      expect(line.label, 'task');
      expect(line.value, '');
    });

    test('a bare slot with no separator renders as one plain line', () {
      final line = bare('apa adanya').single;
      expect(line.label, '');
      expect(line.value, 'apa adanya');
    });

    test('a bare slot whose header contains a colon takes the rowSplit path', () {
      // The colon sits at index 10, inside maxContentLabelLength, so the plain
      // parser would have produced label 'Cek jam 08' / value '00|Selesai'.
      final line = bare('Cek jam 08:00|Selesai').single;
      expect(line.label, 'Cek jam 08:00');
      expect(line.value, 'Selesai');
    });

    test('a header longer than maxContentLabelLength is kept', () {
      const String task = 'Sapu halaman dan area pedestrian'; // 32 chars
      expect(task.length, greaterThan(maxContentLabelLength));
      final line = bare('$task|Selesai').single;
      expect(line.label, task);
      expect(line.value, 'Selesai');
    });

    test('an empty, whitespace, star or unsubstituted slot is dropped', () {
      expect(bare(''), isEmpty);
      expect(bare('   '), isEmpty);
      expect(bare(emptyRowSlotMarker), isEmpty);
      // <19> on a row that never had a 19th column survives replaceMarker as
      // the literal text '<19>' — it must not be shown as a value.
      expect(
        parseContentLinesSplit('<19>', '|', renderer(const <int, String>{})),
        isEmpty,
      );
    });

    test('a labelled line is never split, even when its value has the separator', () {
      // A date or a note that happens to contain '|' must survive intact.
      final line = parseContentLinesSplit(
        'Keterangan: <9>',
        '|',
        renderer(<int, String>{9: 'kiri|kanan'}),
      ).single;
      expect(line.label, 'Keterangan');
      expect(line.value, 'kiri|kanan');
    });

    test('a literal-text line with no colon is never split', () {
      final line = parseContentLinesSplit(
        'Catatan <9>',
        '|',
        renderer(<int, String>{9: 'kiri|kanan'}),
      ).single;
      expect(line.label, '');
      expect(line.value, 'Catatan kiri|kanan');
    });

    test('a multi-character separator works', () {
      final line = parseContentLinesSplit(
        '<11>',
        ' :: ',
        renderer(<int, String>{11: 'task :: status'}),
      ).single;
      expect(line.label, 'task');
      expect(line.value, 'status');
    });

    test('a blank template line is dropped, no spacer is rendered', () {
      final lines = parseContentLinesSplit(
        'A: <2>\n \nB: <3>',
        '|',
        renderer(<int, String>{2: 'x', 3: 'y'}),
      );
      expect(lines.length, 2);
      expect(lines.map((l) => l.label).toList(), ['A', 'B']);
    });

    test('a literal backslash-n in the template becomes two bare lines', () {
      final lines = parseContentLinesSplit(
        '<11>\\n<12>',
        '|',
        renderer(<int, String>{11: 'a|1', 12: 'b|2'}),
      );
      expect(lines.length, 2);
      expect(lines[0].label, 'a');
      expect(lines[0].value, '1');
      expect(lines[1].label, 'b');
      expect(lines[1].value, '2');
    });

    test('a labelled line with an empty or star value is still rendered', () {
      // The drop rule (empty / whitespace / '*' / unsubstituted marker) belongs
      // to BARE lines only. Hoist it above the isBareMarkerLine branch and
      // `Keterangan: <17>` silently vanishes instead of rendering as '-'.
      final lines = parseContentLinesSplit(
        'Keterangan: <9>\nCatatan: <16>',
        '|',
        renderer(<int, String>{9: '', 16: '*'}),
      );
      expect(lines.map((l) => l.label).toList(), ['Keterangan', 'Catatan']);
      expect(lines.map((l) => l.value).toList(), ['', '*']);
    });

    test('isBareMarkerLine accepts only a lone marker', () {
      expect(isBareMarkerLine('<11>'), isTrue);
      expect(isBareMarkerLine('  <11>  '), isTrue);
      expect(isBareMarkerLine('Tanggal: <2>'), isFalse);
      expect(isBareMarkerLine('Catatan <9>'), isFalse);
      expect(isBareMarkerLine('<a>'), isFalse);
      expect(isBareMarkerLine('<11><12>'), isFalse);
      expect(isBareMarkerLine(''), isFalse);
    });
  });

  group('metaIcon', () {
    test('maps the labels used by the live report screens', () {
      expect(metaIcon('Tanggal'), Icons.schedule);
      expect(metaIcon('Nama Tamu'), Icons.person_outline);
      expect(metaIcon('Lokasi'), Icons.place_outlined);
      expect(metaIcon('Site'), Icons.apartment_outlined);
      expect(metaIcon('Jenis Laporan'), Icons.sell_outlined);
      expect(metaIcon('Kondisi'), Icons.verified_outlined);
      expect(metaIcon('Hadir'), Icons.groups_outlined);
      expect(metaIcon('Tujuan'), Icons.flag_outlined);
      expect(metaIcon('Keterangan'), Icons.notes_outlined);
    });

    test('is case-insensitive', () {
      expect(metaIcon('LOKASI'), Icons.place_outlined);
    });

    test('returns null for an unmapped label so the caller can print it', () {
      expect(metaIcon('Nomor Polisi'), isNull);
      expect(metaIcon(''), isNull);
    });
  });
}
