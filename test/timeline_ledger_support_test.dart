import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/timeline_ledger_support.dart';

void main() {
  group('parseBadgeMap', () {
    test('standard map with multiple entries', () {
      final Map<String, BadgeEntry> lookup = {};
      final List<BadgeEntry> entries = parseBadgeMap(
        'openload\u{25FC}Muat\u{2605}closeunload\u{25FC}Turun\u{2605}drop\u{25FC}Antar',
        lookup,
      );
      expect(entries.length, 3);
      expect(entries[0].value, 'openload');
      expect(entries[0].label, 'Muat');
      expect(entries[0].index, 0);
      expect(entries[1].value, 'closeunload');
      expect(entries[1].label, 'Turun');
      expect(entries[1].index, 1);
      expect(entries[2].value, 'drop');
      expect(entries[2].label, 'Antar');
      expect(entries[2].index, 2);
      expect(lookup['openload']!.label, 'Muat');
      expect(lookup['closeunload']!.label, 'Turun');
    });

    test('missing label defaults to value', () {
      final Map<String, BadgeEntry> lookup = {};
      final List<BadgeEntry> entries = parseBadgeMap('solo', lookup);
      expect(entries.length, 1);
      expect(entries[0].value, 'solo');
      expect(entries[0].label, 'solo');
    });

    test('empty raw returns empty list', () {
      final Map<String, BadgeEntry> lookup = {};
      expect(parseBadgeMap('', lookup), isEmpty);
      expect(parseBadgeMap('   ', lookup), isEmpty);
    });

    test('empty value segment skipped', () {
      final Map<String, BadgeEntry> lookup = {};
      // Leading star produces an empty first segment.
      final List<BadgeEntry> entries = parseBadgeMap(
        '\u{2605}a\u{25FC}A',
        lookup,
      );
      expect(entries.length, 1);
      expect(entries[0].value, 'a');
    });
  });

  group('badgeFgColor / badgeBgColor', () {
    test('mapped entry uses palette by index', () {
      const entry = BadgeEntry('x', 'X', 0);
      expect(badgeFgColor(entry), kCategoryColors[0]);
      expect(badgeBgColor(entry), kCategoryBgColors[0]);
    });

    test('index wraps via modulo', () {
      const entry = BadgeEntry('x', 'X', 8); // 8 % 8 = 0
      expect(badgeFgColor(entry), kCategoryColors[0]);
      const entry2 = BadgeEntry('y', 'Y', 10); // 10 % 8 = 2
      expect(badgeFgColor(entry2), kCategoryColors[2]);
    });

    test('null entry returns neutral', () {
      expect(badgeFgColor(null), const Color(0xFF6B7280));
      expect(badgeBgColor(null), const Color(0xFFF3F4F6));
    });
  });

  group('docEpoch', () {
    test('reads from configured field', () {
      expect(docEpoch({'t': 100, 'myt': 200}, 'myt'), 200);
    });

    test('falls back to eventEpoch when field empty', () {
      expect(docEpoch({'t': 100}, ''), 100);
    });

    test('falls back to eventEpoch when field missing from doc', () {
      expect(docEpoch({'t': 100}, 'missing'), 100);
    });

    test('handles string epoch', () {
      expect(docEpoch({'ts': '1234567890'}, 'ts'), 1234567890);
    });

    test('returns 0 when nothing parses', () {
      expect(docEpoch(<String, dynamic>{}, 'x'), 0);
    });
  });

  group('resolveConditionsFailClosed', () {
    test('resolves {vehicleId} from bare screenTx key', () {
      // This is the primary admin path: routeParams dispatches the tapped
      // vehicle id as screenTx['vehicleId']. resolveScreenTxTokens reads it
      // directly (no DriverHomeState involvement, no reserved switch case).
      final result = resolveConditionsFailClosed(
        '[[\u{25C0}vv\u{25B6}\u{25FC}{vehicleId}]]',
        {'vehicleId': 'abc123'},
      );
      expect(result, '[[\u{25C0}vv\u{25B6}\u{25FC}abc123]]');
    });

    test('admin path: bare vehicleId resolves with no driver session', () {
      // Simulates admin/supervisor user: screenTx has ONLY the bare
      // 'vehicleId' key from routeParams. No #has_user_login, no driver
      // session state. The resolver must read the bare key directly.
      final Map<String, dynamic> adminScreenTx = {
        'vehicleId': 'TRUCK-007',
        '#VID': 'admin-vid-123',
        '#NAME': 'Admin User',
        // Note: NO '#has_user_login', NO driver session vehicle.
        // resolveDriverCurlyTokens would read DriverHomeState.vehicleId
        // (empty for admin) and SHADOW this bare key. That's why we use
        // resolveScreenTxTokens instead.
      };
      final result = resolveConditionsFailClosed(
        '[[\u{25C0}vv\u{25B6}\u{25FC}{vehicleId}]]',
        adminScreenTx,
      );
      expect(result, '[[\u{25C0}vv\u{25B6}\u{25FC}TRUCK-007]]');
    });

    test('unresolved {key} returns null (fail-closed)', () {
      final result = resolveConditionsFailClosed(
        '[[\u{25C0}vv\u{25B6}\u{25FC}{vehicleId}]]',
        <String, dynamic>{},
      );
      expect(result, isNull);
    });

    test('empty vehicleId left as literal -> null (fail-closed)', () {
      final result = resolveConditionsFailClosed(
        '[[\u{25C0}vv\u{25B6}\u{25FC}{vehicleId}]]',
        {'vehicleId': ''},
      );
      // resolveScreenTxTokens leaves empty as literal {vehicleId}
      expect(result, isNull);
    });

    test('no tokens -> passes through', () {
      final result = resolveConditionsFailClosed(
        '[[\u{25C0}ty\u{25B6}\u{25FC}vehicle]]',
        <String, dynamic>{},
      );
      expect(result, '[[\u{25C0}ty\u{25B6}\u{25FC}vehicle]]');
    });

    test('empty conditions -> empty string', () {
      final result = resolveConditionsFailClosed('', <String, dynamic>{});
      expect(result, '');
    });

    test('multiple tokens, one resolved one not -> fail-closed', () {
      final result = resolveConditionsFailClosed(
        '[[\u{25C0}vv\u{25B6}\u{25FC}{vehicleId}\u{25C0}dt\u{25B6}\u{25FC}{today}]]',
        {'vehicleId': 'abc123'},
      );
      // {today} not in screenTx -> unresolved -> fail-closed
      expect(result, isNull);
    });

    test('multiple tokens, all resolved -> passes', () {
      final result = resolveConditionsFailClosed(
        '[[\u{25C0}vv\u{25B6}\u{25FC}{vehicleId}\u{25C0}dt\u{25B6}\u{25FC}{today}]]',
        {'vehicleId': 'abc123', 'today': '1720396800000'},
      );
      expect(result,
          '[[\u{25C0}vv\u{25B6}\u{25FC}abc123\u{25C0}dt\u{25B6}\u{25FC}1720396800000]]');
    });
  });

  group('groupDocs', () {
    final docs = [
      {'mrf': 'EVT-001', 'in': 'Aqua', 't': 3000},
      {'mrf': 'EVT-001', 'in': 'Gas', 't': 2000},
      {'mrf': 'EVT-002', 'in': 'Minyak', 't': 5000},
      {'mrf': 'EVT-002', 'in': 'Solar', 't': 4000},
      {'mrf': 'EVT-003', 'in': 'Beras', 't': 1000},
    ];

    test('groups by field, sorted by max epoch desc', () {
      final groups = groupDocs(docs, 'mrf', 't');
      expect(groups.length, 3);
      // EVT-002 has max epoch 5000 -> first
      expect(groups[0].key, 'EVT-002');
      expect(groups[0].maxEpoch, 5000);
      expect(groups[0].docs.length, 2);
      // EVT-001 has max epoch 3000 -> second
      expect(groups[1].key, 'EVT-001');
      expect(groups[1].maxEpoch, 3000);
      expect(groups[1].docs.length, 2);
      // EVT-003 has max epoch 1000 -> third
      expect(groups[2].key, 'EVT-003');
      expect(groups[2].maxEpoch, 1000);
      expect(groups[2].docs.length, 1);
    });

    test('docs within group sorted by epoch desc', () {
      final groups = groupDocs(docs, 'mrf', 't');
      final evt001 = groups.firstWhere((g) => g.key == 'EVT-001');
      expect(evt001.docs[0]['t'], 3000); // newer first
      expect(evt001.docs[1]['t'], 2000);
    });

    test('missing groupField value grouped under empty string', () {
      final mixed = [
        {'mrf': 'EVT-001', 't': 100},
        {'t': 200}, // no mrf
      ];
      final groups = groupDocs(mixed, 'mrf', 't');
      expect(groups.any((g) => g.key == ''), isTrue);
    });

    test('empty docs returns empty groups', () {
      expect(groupDocs([], 'mrf', 't'), isEmpty);
    });
  });

  group('resolveSegmentedTemplate', () {
    test('splits on diamond and resolves tokens', () {
      final doc = <String, dynamic>{'in': 'Aqua 19L', 'qt': '3', 'cd': 'penuh'};
      final segs = resolveSegmentedTemplate(
        '<in> \u{00D7}<qt>\u{25C6}<cd>',
        doc,
        const {},
      );
      expect(segs.length, 2);
      expect(segs[0], 'Aqua 19L \u{00D7}3');
      expect(segs[1], 'penuh');
    });

    test('single segment (no diamond)', () {
      final doc = <String, dynamic>{'in': 'Aqua'};
      final segs = resolveSegmentedTemplate('<in>', doc, const {});
      expect(segs.length, 1);
      expect(segs[0], 'Aqua');
    });

    test('missing field resolves to empty', () {
      final doc = <String, dynamic>{};
      final segs = resolveSegmentedTemplate(
        '<in>\u{25C6}<cd>',
        doc,
        const {},
      );
      expect(segs[0], '');
      expect(segs[1], '');
    });

    test('computed tokens resolve', () {
      final doc = <String, dynamic>{};
      final segs = resolveSegmentedTemplate(
        '{n} item',
        doc,
        {'n': '5'},
      );
      expect(segs[0], '5 item');
    });
  });

  group('palette constants', () {
    test('kCategoryColors has 8 entries', () {
      expect(kCategoryColors.length, 8);
    });

    test('kCategoryBgColors has 8 entries', () {
      expect(kCategoryBgColors.length, 8);
    });

    test('fg and bg lists have same length', () {
      expect(kCategoryColors.length, kCategoryBgColors.length);
    });
  });

  group('formatEpochHHmm', () {
    test('formats epoch as HH:mm', () {
      // 2026-07-09 09:37:00 UTC+7 = 2026-07-09 02:37:00 UTC
      // We use a known epoch and check the format matches HH:mm pattern.
      final int epoch = DateTime(2026, 7, 9, 9, 37).millisecondsSinceEpoch;
      expect(formatEpochHHmm(epoch), '09:37');
    });

    test('returns empty for zero epoch', () {
      expect(formatEpochHHmm(0), '');
    });

    test('returns empty for negative epoch', () {
      expect(formatEpochHHmm(-1), '');
    });

    test('afternoon time', () {
      final int epoch = DateTime(2026, 7, 9, 14, 5).millisecondsSinceEpoch;
      expect(formatEpochHHmm(epoch), '14:05');
    });
  });

  group('groupSections', () {
    // Test data: 2 trips (tr=trip1, tr=trip2), each with multiple events.
    final List<Map<String, dynamic>> docs = [
      {'tr': 'trip1', 'mrf': 'EVT-A', 'in': 'Aqua', 't': 1000},
      {'tr': 'trip1', 'mrf': 'EVT-A', 'in': 'Gas', 't': 2000},
      {'tr': 'trip1', 'mrf': 'EVT-B', 'in': 'Minyak', 't': 3000},
      {'tr': 'trip2', 'mrf': 'EVT-C', 'in': 'Solar', 't': 5000},
      {'tr': 'trip2', 'mrf': 'EVT-C', 'in': 'Beras', 't': 4000},
      {'tr': 'trip2', 'mrf': 'EVT-D', 'in': 'Gula', 't': 6000},
    ];

    test('buckets into sections by groupField2', () {
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      expect(sections.length, 2);
    });

    test('sections sorted by max epoch desc (newest first)', () {
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      // trip2 has max epoch 6000 -> first
      expect(sections[0].key, 'trip2');
      expect(sections[0].maxEpoch, 6000);
      // trip1 has max epoch 3000 -> second
      expect(sections[1].key, 'trip1');
      expect(sections[1].maxEpoch, 3000);
    });

    test('sectionCount = total docs in section', () {
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      final trip2 = sections.firstWhere((s) => s.key == 'trip2');
      expect(trip2.sectionCount, 3); // EVT-C(2) + EVT-D(1)
      final trip1 = sections.firstWhere((s) => s.key == 'trip1');
      expect(trip1.sectionCount, 3); // EVT-A(2) + EVT-B(1)
    });

    test('groupCount = number of event cards in section', () {
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      final trip2 = sections.firstWhere((s) => s.key == 'trip2');
      expect(trip2.groupCount, 2); // EVT-C, EVT-D
      final trip1 = sections.firstWhere((s) => s.key == 'trip1');
      expect(trip1.groupCount, 2); // EVT-A, EVT-B
    });

    test('minEpoch = earliest doc in section (trip start)', () {
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      final trip2 = sections.firstWhere((s) => s.key == 'trip2');
      expect(trip2.minEpoch, 4000);
      final trip1 = sections.firstWhere((s) => s.key == 'trip1');
      expect(trip1.minEpoch, 1000);
    });

    test('cards within section sorted by max epoch desc', () {
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      final trip2 = sections.firstWhere((s) => s.key == 'trip2');
      // EVT-D maxEpoch=6000 first, EVT-C maxEpoch=5000 second
      expect(trip2.groups[0].key, 'EVT-D');
      expect(trip2.groups[1].key, 'EVT-C');
    });

    test('docs within group sorted by epoch desc', () {
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      final trip1 = sections.firstWhere((s) => s.key == 'trip1');
      final evtA = trip1.groups.firstWhere((g) => g.key == 'EVT-A');
      expect(evtA.docs[0]['t'], 2000); // newer first
      expect(evtA.docs[1]['t'], 1000);
    });

    test('empty docs returns empty sections', () {
      expect(groupSections([], 'tr', 'mrf', 't'), isEmpty);
    });

    test('groupField empty: each doc is its own card within section', () {
      final sections = groupSections(docs, 'tr', '', 't');
      expect(sections.length, 2);
      final trip1 = sections.firstWhere((s) => s.key == 'trip1');
      // 3 docs -> 3 single-doc groups
      expect(trip1.groupCount, 3);
      expect(trip1.sectionCount, 3);
      for (final g in trip1.groups) {
        expect(g.docs.length, 1);
      }
    });

    test('groupField empty: single-doc groups sorted by epoch desc', () {
      final sections = groupSections(docs, 'tr', '', 't');
      final trip1 = sections.firstWhere((s) => s.key == 'trip1');
      // Should be sorted by maxEpoch desc: 3000, 2000, 1000
      expect(trip1.groups[0].maxEpoch, 3000);
      expect(trip1.groups[1].maxEpoch, 2000);
      expect(trip1.groups[2].maxEpoch, 1000);
    });

    test('missing groupField2 value grouped under empty string', () {
      final mixed = [
        {'tr': 'trip1', 'mrf': 'A', 't': 100},
        {'mrf': 'B', 't': 200}, // no tr
      ];
      final sections = groupSections(mixed, 'tr', 'mrf', 't');
      expect(sections.any((s) => s.key == ''), isTrue);
    });

    test('sectionTime picks min epoch (not max)', () {
      // Verify via minEpoch field that the section exposes the earliest time.
      final sections = groupSections(docs, 'tr', 'mrf', 't');
      final trip2 = sections.firstWhere((s) => s.key == 'trip2');
      // trip2 docs: t=5000, t=4000, t=6000. Min = 4000.
      expect(trip2.minEpoch, 4000);
      // Verify formatEpochHHmm would render this (integration-level).
      final String rendered = formatEpochHHmm(trip2.minEpoch);
      expect(rendered, isNotEmpty);
    });
  });

  group('applyCondMap', () {
    test('mapped value relabels cd', () {
      final Map<String, BadgeEntry> lookup = {};
      parseBadgeMap('full\u{25FC}Isi\u{2605}empty\u{25FC}Kosong', lookup);
      final Map<String, dynamic> doc = {'in': 'Aqua Galon', 'qt': '7', 'cd': 'full'};
      final Map<String, dynamic> result = applyCondMap(doc, lookup);
      expect(result['cd'], 'Isi');
      // Other fields untouched.
      expect(result['in'], 'Aqua Galon');
      expect(result['qt'], '7');
    });

    test('unmapped value returns raw (not blank)', () {
      final Map<String, BadgeEntry> lookup = {};
      parseBadgeMap('full\u{25FC}Isi\u{2605}empty\u{25FC}Kosong', lookup);
      final Map<String, dynamic> doc = {'cd': 'damaged'};
      final Map<String, dynamic> result = applyCondMap(doc, lookup);
      // Unmapped -> raw passthrough, same doc instance.
      expect(result['cd'], 'damaged');
      expect(identical(result, doc), isTrue);
    });

    test('empty lookup returns same doc instance (zero regression)', () {
      final Map<String, BadgeEntry> lookup = {};
      final Map<String, dynamic> doc = {'cd': 'full', 'in': 'Aqua'};
      final Map<String, dynamic> result = applyCondMap(doc, lookup);
      expect(identical(result, doc), isTrue);
    });

    test('original doc is NOT mutated', () {
      final Map<String, BadgeEntry> lookup = {};
      parseBadgeMap('full\u{25FC}Isi', lookup);
      final Map<String, dynamic> original = {'cd': 'full', 'in': 'Aqua'};
      applyCondMap(original, lookup);
      // original still holds the canonical raw value.
      expect(original['cd'], 'full');
    });

    test('missing cd field returns same doc instance', () {
      final Map<String, BadgeEntry> lookup = {};
      parseBadgeMap('full\u{25FC}Isi', lookup);
      final Map<String, dynamic> doc = {'in': 'Aqua'};
      final Map<String, dynamic> result = applyCondMap(doc, lookup);
      expect(identical(result, doc), isTrue);
    });

    test('end-to-end: resolveSegmentedTemplate with condMap produces correct output', () {
      // This test uses the REAL template from the spec and proves the full
      // pipeline: applyCondMap -> resolveSegmentedTemplate -> split segments.
      final Map<String, BadgeEntry> lookup = {};
      parseBadgeMap('full\u{25FC}Isi\u{2605}empty\u{25FC}Kosong', lookup);

      final Map<String, dynamic> doc = {
        'in': 'Aqua Galon 19 Liter',
        'qt': '7',
        'cd': 'empty',
      };

      final List<String> segs = resolveSegmentedTemplate(
        '<in> \u{00D7}<qt>\u{25C6}<cd>',  // "<in> x<qt>◆<cd>"
        applyCondMap(doc, lookup),
        const {},
      );

      expect(segs.length, 2);
      expect(segs[0], 'Aqua Galon 19 Liter \u{00D7}7');
      expect(segs[1], 'Kosong');
    });
  });
}
