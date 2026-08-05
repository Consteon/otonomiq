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
