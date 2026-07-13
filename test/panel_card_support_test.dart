import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/panel_card_support.dart';

void main() {
  group('parsePanels', () {
    test('maps each panel map to a PanelConfig', () {
      final raw = [
        {
          'icon': 'users',
          'text': 'Kehadiran◆{hadir}/<3> hadir◆{issues}',
          'status': '{ps}',
          'route': 'checkinSiteDetail',
        },
        {
          'icon': 'clipboard-check',
          'text': 'Patroli & Cleaning◆{llCount} titik◆{staleCount} titik jeda lama',
          'status': '{qs}',
          'route': 'patroliCleaningPerSite',
        },
      ];
      final panels = parsePanels(raw);
      expect(panels.length, 2);
      expect(panels[0].icon, 'users');
      expect(panels[0].route, 'checkinSiteDetail');
      expect(panels[1].status, '{qs}');
    });

    test('non-list input returns empty', () {
      expect(parsePanels(null), isEmpty);
      expect(parsePanels('oops'), isEmpty);
    });

    test('missing keys default to empty string', () {
      final panels = parsePanels([
        {'icon': 'users'}
      ]);
      expect(panels.length, 1);
      expect(panels[0].text, '');
      expect(panels[0].status, '');
      expect(panels[0].route, '');
    });
  });

  group('resolvePanelText', () {
    // replaceMarker semantics: ref = [sortKey, timestamp, field1, ...];
    // with indexStart=1, <2> -> ref[2], <3> -> ref[3].
    test('resolves <i> numeric markers and {key} computed tokens', () {
      final row = ['sortKey', '1780000000000', 'Budi', '5'];
      final computed = {'hadir': '3', 'issues': '2 belum scan'};
      final out = resolvePanelText(
        'Kehadiran◆{hadir}/<3> hadir◆{issues}',
        row,
        computed,
        1,
      );
      expect(out, 'Kehadiran◆3/5 hadir◆2 belum scan');
    });

    test('unknown {key} left literal when not in computed', () {
      final out = resolvePanelText('x◆{ps}◆y', ['s', 't'], {}, 1);
      expect(out, 'x◆{ps}◆y');
    });
  });

  group('splitPanelText', () {
    test('splits resolved string into label/headline/details', () {
      final p = splitPanelText('Kehadiran◆3/5 hadir◆2 belum scan');
      expect(p.label, 'Kehadiran');
      expect(p.headline, '3/5 hadir');
      expect(p.details, '2 belum scan');
    });

    test('missing segments default to empty', () {
      final p = splitPanelText('OnlyLabel');
      expect(p.label, 'OnlyLabel');
      expect(p.headline, '');
      expect(p.details, '');
    });
  });

  group('panelIcon', () {
    test('known names map to icons', () {
      expect(panelIcon('users'), Icons.people_alt_rounded);
      expect(panelIcon('clipboard-check'), Icons.fact_check_rounded);
    });
    test('case/whitespace tolerant', () {
      expect(panelIcon('  Users '), Icons.people_alt_rounded);
    });
    test('unknown name falls back to a default icon', () {
      expect(panelIcon('nope'), Icons.dashboard_rounded);
    });
  });

  group('worstStatus', () {
    test('danger beats warn beats ok', () {
      expect(worstStatus(['ok', 'warn', 'danger']), 'danger');
      expect(worstStatus(['ok', 'warn']), 'warn');
      expect(worstStatus(['ok', 'ok']), 'ok');
    });
    test('case insensitive, unknown ignored', () {
      expect(worstStatus(['OK', 'Warn']), 'warn');
      expect(worstStatus(['{ps}', '{qs}']), 'ok'); // unresolved -> fallback ok
    });
    test('empty list -> ok', () {
      expect(worstStatus([]), 'ok');
    });
  });

  group('groupByStatus', () {
    test('buckets items into danger/warn/ok in fixed order', () {
      final items = ['a', 'b', 'c', 'd'];
      String statusOf(String s) => {
            'a': 'danger',
            'b': 'ok',
            'c': 'warn',
            'd': 'danger',
          }[s]!;
      final g = groupByStatus<String>(items, statusOf);
      expect(g.keys.toList(), ['danger', 'warn', 'ok']);
      expect(g['danger'], ['a', 'd']);
      expect(g['warn'], ['c']);
      expect(g['ok'], ['b']);
    });
    test('unknown status falls into ok bucket', () {
      final g = groupByStatus<String>(['x'], (_) => '{ws}');
      expect(g['ok'], ['x']);
    });
  });

  group('status labels', () {
    test('group label uses Aman for ok', () {
      expect(statusGroupLabel('danger'), 'Perlu tindak');
      expect(statusGroupLabel('warn'), 'Perhatian');
      expect(statusGroupLabel('ok'), 'Aman');
    });
    test('pill label uses Beres for ok', () {
      expect(statusPillLabel('danger'), 'Perlu tindak');
      expect(statusPillLabel('warn'), 'Perhatian');
      expect(statusPillLabel('ok'), 'Beres');
      expect(statusPillLabel('{ps}'), 'Beres'); // unknown -> ok label
    });
  });

  group('summaryLine', () {
    test('formats counts per status', () {
      final groups = {
        'danger': [1, 2],
        'warn': [3],
        'ok': [4, 5, 6],
      };
      expect(summaryLine(groups), '2 perlu tindak · 1 perhatian · 3 aman');
    });
  });

  group('status colors', () {
    test('distinct colors per status', () {
      expect(statusColor('danger'), const Color(0xFFDC2626));
      expect(statusColor('warn'), const Color(0xFFD97706));
      expect(statusColor('ok'), const Color(0xFF16A34A));
      expect(statusColor('{ws}'), const Color(0xFF16A34A)); // fallback ok
    });
  });

  group('parseTablePath', () {
    test('splits "docId//subColl"', () {
      final p = parseTablePath('84214220504259//site');
      expect(p.tableDocId, '84214220504259');
      expect(p.subColl, 'site');
    });
    test('no // defaults subColl to content', () {
      final p = parseTablePath('myTable');
      expect(p.tableDocId, 'myTable');
      expect(p.subColl, 'content');
    });
    test('trailing empty subColl falls back to content', () {
      final p = parseTablePath('docId//');
      expect(p.tableDocId, 'docId');
      expect(p.subColl, 'content');
    });
  });

  group('llCount', () {
    test('counts ll array of objects', () {
      final doc = {
        'an': 'A',
        'll': [
          {'ln': 'P1'},
          {'ln': 'P2'}
        ]
      };
      expect(llCount(doc), 2);
    });
    test('missing or non-list ll -> 0', () {
      expect(llCount({'an': 'A'}), 0);
      expect(llCount({'ll': 'oops'}), 0);
    });
  });

  group('resolveMapTokens', () {
    final doc = {
      'an': 'A Product Group',
      'sn': 'S Product Group',
      'nm': 2,
      'av': 83674161979544,
    };
    test('resolves <charcode> from doc map', () {
      expect(resolveMapTokens('◆<an>◆<sn>', doc, const {}),
          '◆A Product Group◆S Product Group');
    });
    test('numeric doc values stringified', () {
      expect(resolveMapTokens('<nm> hadir', doc, const {}), '2 hadir');
    });
    test('missing charcode -> empty string', () {
      expect(resolveMapTokens('x<zz>y', doc, const {}), 'xy');
    });
    test('computed {key} substituted, unknown left literal', () {
      expect(
          resolveMapTokens(
              'Kehadiran◆{hadir}/<nm> hadir◆{issues}', doc, {'hadir': '10'}),
          'Kehadiran◆10/2 hadir◆{issues}');
    });
  });

  group('PanelConfig.okText', () {
    test('parsed when present, empty default', () {
      final panels = parsePanels([
        {'icon': 'clipboard-check', 'text': 'a◆b◆c', 'status': '{qs}',
         'route': 'r', 'okText': 'Tidak ada jeda signifikan'},
        {'icon': 'users', 'text': 'x'},
      ]);
      expect(panels[0].okText, 'Tidak ada jeda signifikan');
      expect(panels[1].okText, '');
    });
  });

  group('attendanceSet', () {
    test('-1 / empty / 0 are unset; a real epoch is set', () {
      expect(attendanceSet('-1'), isFalse);
      expect(attendanceSet(''), isFalse);
      expect(attendanceSet('0'), isFalse);
      expect(attendanceSet(null), isFalse);
      expect(attendanceSet('1780479159902'), isTrue);
      expect(attendanceSet(1780479159902), isTrue);
    });
  });

  group('groupBySv', () {
    test('buckets workers by sv, skips empty sv', () {
      final g = groupBySv([
        {'sv': '11', 'ci': '-1'},
        {'sv': '11', 'ci': '5'},
        {'sv': '22', 'ci': '-1'},
        {'ci': '5'}, // no sv -> skipped
      ]);
      expect(g['11']!.length, 2);
      expect(g['22']!.length, 1);
      expect(g.containsKey(''), isFalse);
    });
  });

  group('computeKehadiran', () {
    test('all present, clocked out -> ok / Semua beres', () {
      final r = computeKehadiran([
        {'ci': '100', 'co': '200'},
        {'ci': '100', 'co': '200'},
      ]);
      expect(r.hadir, 2);
      expect(r.issues, 'Semua beres');
      expect(r.ps, 'ok');
    });
    test('a belum-scan -> danger', () {
      final r = computeKehadiran([
        {'ci': '100', 'co': '200'},
        {'ci': '-1', 'co': '-1'},
      ]);
      expect(r.hadir, 1);
      expect(r.issues, '1 belum scan');
      expect(r.ps, 'danger');
    });
    test('only lupa-clock-out -> warn', () {
      final r = computeKehadiran([
        {'ci': '100', 'co': '-1'},
        {'ci': '100', 'co': '200'},
      ]);
      expect(r.hadir, 2);
      expect(r.issues, '1 lupa clock-out');
      expect(r.ps, 'warn');
    });
    test('both issues -> danger, combined text', () {
      final r = computeKehadiran([
        {'ci': '-1', 'co': '-1'},
        {'ci': '100', 'co': '-1'},
      ]);
      expect(r.issues, '1 belum scan, 1 lupa clock-out');
      expect(r.ps, 'danger');
    });
    test('empty list -> ok / Semua beres', () {
      final r = computeKehadiran(const []);
      expect(r.hadir, 0);
      expect(r.ps, 'ok');
      expect(r.issues, 'Semua beres');
    });
  });

  // ── ln-keyed patrol join (re-keyed 2026-06-11: location NAME, not QR id) ──
  // Merged: the Task-0 "(ln-keyed)"/"(ln-matched)" groups were folded in here
  // (W3) so every unique assertion appears exactly once.
  group('latestPatrolByPoint', () {
    test('keeps max t per ln, patrol-type only, skips empty/zero', () {
      final m = latestPatrolByPoint([
        {'ty': 'report-patrol', 'ln': 'Lobby', 'lq': 'QR-A', 't': '100'},
        {'ty': 'report-patrol', 'ln': 'Lobby', 'lq': 'QR-A', 't': '300'},
        {'ty': 'report-patrol', 'ln': 'Lobby', 'lq': 'QR-A', 't': '200'},
        {'ty': 'report-incident', 'ln': 'Lobby', 'lq': 'QR-A', 't': '999'},
        {'ty': 'report-patrol', 'ln': '', 'lq': 'QR-B', 't': '500'},
        {'ty': 'report-patrol', 'ln': 'Parkir', 'lq': 'QR-C', 't': '50'},
      ]);
      expect(m['Lobby'], 300);
      expect(m['Parkir'], 50);
      expect(m.containsKey(''), isFalse);
      expect(m.containsKey('QR-A'), isFalse); // NOT keyed by lq
      expect(m.containsKey('QR-C'), isFalse);
    });
    test('falls back to et when t missing', () {
      final m = latestPatrolByPoint([
        {'ty': 'patrol', 'ln': 'Gate', 'et': '700'},
      ]);
      expect(m['Gate'], 700);
    });
  });

  group('computePatroli', () {
    const now = 1000000000000; // fixed "now" for tests
    const stale = 43200000; // 12h
    test('recent visits -> staleCount 0, qs ok', () {
      final ll = [
        {'ln': 'Lobby', 'li': 'QR1'},
        {'ln': 'Parkir', 'li': 'QR2'}
      ];
      final last = {'Lobby': now - 1000, 'Parkir': now - 2000};
      final r = computePatroli(ll, last, now, stale);
      expect(r.llCount, 2);
      expect(r.staleCount, 0);
      expect(r.qs, 'ok');
    });
    test('one stale visit -> staleCount 1, qs warn, longestGap hours', () {
      final ll = [
        {'ln': 'Lobby'},
        {'ln': 'Parkir'}
      ];
      // Lobby 13h ago
      final last = {'Lobby': now - (stale + 3600000), 'Parkir': now - 1000};
      final r = computePatroli(ll, last, now, stale);
      expect(r.staleCount, 1);
      expect(r.qs, 'warn');
      expect(r.longestGapHours, 13);
    });
    test('never-patrolled point (ln not in map) counts as stale', () {
      final ll = [
        {'ln': 'Lobby', 'li': 'QR1'},
        {'ln': 'Parkir', 'li': 'QR2'}
      ];
      final last = {'Lobby': now - 1000}; // Parkir never visited
      final r = computePatroli(ll, last, now, stale);
      expect(r.staleCount, 1);
      expect(r.qs, 'warn');
    });
    test('non-map / missing ln tolerated', () {
      final ll = [
        'oops',
        {'ln': 'Lobby'}
      ];
      final r = computePatroli(ll, {'Lobby': now - 1000}, now, stale);
      expect(r.llCount, 1);
      expect(r.staleCount, 0);
    });
  });

  group('parseStatusLabels', () {
    test('parses ★-then-◼ separated entries', () {
      final labels = parseStatusLabels(
          'danger◼Perlu tindak◼Perlu tindak★warn◼Perhatian◼Perhatian★ok◼Aman◼Beres');
      expect(labels.length, 3);
      expect(labels[0].value, 'danger');
      expect(labels[0].groupLabel, 'Perlu tindak');
      expect(labels[0].pillLabel, 'Perlu tindak');
      expect(labels[2].value, 'ok');
      expect(labels[2].groupLabel, 'Aman');
      expect(labels[2].pillLabel, 'Beres');
    });

    test('entries with fewer than 3 segments use value as fallback', () {
      final labels = parseStatusLabels('danger◼Rusak');
      expect(labels.length, 1);
      expect(labels[0].groupLabel, 'Rusak');
      expect(labels[0].pillLabel, 'Rusak'); // fallback = groupLabel
    });

    test('empty/null returns patrol defaults', () {
      final labels = parseStatusLabels('');
      expect(labels.length, 3);
      expect(labels[0].value, 'danger');
      expect(labels[0].groupLabel, 'Perlu tindak');
      expect(labels[1].value, 'warn');
      expect(labels[2].value, 'ok');
      expect(labels[2].pillLabel, 'Beres');
    });

    test('null input returns patrol defaults', () {
      final labels = parseStatusLabels(null);
      expect(labels.length, 3);
    });

    test('single malformed entry (no ◼) returns patrol defaults', () {
      final labels = parseStatusLabels('garbage');
      expect(labels.length, 3); // fallback
    });
  });

  group('statusLabelLookup helpers', () {
    final labels = parseStatusLabels(
        'danger◼Rusak◼Rusak★warn◼Perlu servis◼Perlu servis★ok◼Sehat◼Sehat');

    test('lookupGroupLabel finds by value', () {
      expect(lookupGroupLabel(labels, 'danger'), 'Rusak');
      expect(lookupGroupLabel(labels, 'ok'), 'Sehat');
    });

    test('lookupGroupLabel unknown value falls back to value itself', () {
      expect(lookupGroupLabel(labels, 'unknown'), 'unknown');
    });

    test('lookupPillLabel finds by value', () {
      expect(lookupPillLabel(labels, 'danger'), 'Rusak');
      expect(lookupPillLabel(labels, 'ok'), 'Sehat');
    });

    test('lookupPillLabel unknown value falls back to value itself', () {
      expect(lookupPillLabel(labels, 'unknown'), 'unknown');
    });

    test('statusLabelOrder returns values in entry order', () {
      expect(statusLabelOrder(labels), ['danger', 'warn', 'ok']);
    });

    // W2: a 2-entry config (no 'ok' tier). The widget buckets unknown group
    // keys into the LAST entry of statusLabelOrder, so .last must be the
    // intended fallback bucket and the card stays counted (never vanishes).
    test('2-entry config exposes last-entry as the unknown fallback bucket', () {
      final twoTier =
          parseStatusLabels('bad◼Bermasalah◼Bermasalah★fine◼Baik◼Baik');
      final order = statusLabelOrder(twoTier);
      expect(order, ['bad', 'fine']);
      expect(order.last, 'fine'); // unknown group keys land here
    });
  });

  group('parseRouteParam', () {
    test('parses docField◼token', () {
      final rp = parseRouteParam('av◼ccVid');
      expect(rp.docField, 'av');
      expect(rp.token, 'ccVid');
    });

    test('empty/null returns default av/ccVid', () {
      expect(parseRouteParam('').docField, 'av');
      expect(parseRouteParam('').token, 'ccVid');
      expect(parseRouteParam(null).docField, 'av');
    });

    test('no ◼ separator returns default', () {
      final rp = parseRouteParam('justOneWord');
      expect(rp.docField, 'av');
      expect(rp.token, 'ccVid');
    });
  });

  group('buildSummarySpans', () {
    final labels = parseStatusLabels(
        'danger◼Perlu tindak◼Perlu tindak★warn◼Perhatian◼Perhatian★ok◼Aman◼Beres');

    test('includes only tiers with count > 0', () {
      final counts = {'danger': 3, 'warn': 0, 'ok': 5};
      final spans = buildSummarySpans(labels, counts);
      // 2 label spans + 1 separator
      expect(spans.length, 3); // '3 Perlu tindak' + ' · ' + '5 Aman'
    });

    test('all zero returns empty list', () {
      final counts = {'danger': 0, 'warn': 0, 'ok': 0};
      final spans = buildSummarySpans(labels, counts);
      expect(spans, isEmpty);
    });

    test('single tier, no separator', () {
      final counts = {'danger': 2, 'warn': 0, 'ok': 0};
      final spans = buildSummarySpans(labels, counts);
      expect(spans.length, 1);
    });
  });

  group('groupByField', () {
    test('groups docs by the given field, skips empty', () {
      final docs = <Map<String, dynamic>>[
        {'sv': '11', 'ln': 'A'},
        {'sv': '11', 'ln': 'B'},
        {'sv': '22', 'ln': 'C'},
        {'ln': 'D'}, // no sv -> skipped
        {'sv': '', 'ln': 'E'}, // empty sv -> skipped
      ];
      final g = groupByField(docs, 'sv');
      expect(g.keys.length, 2);
      expect(g['11']!.length, 2);
      expect(g['22']!.length, 1);
      expect(g.containsKey(''), isFalse);
    });

    test('missing field entirely -> skipped', () {
      final docs = <Map<String, dynamic>>[
        {'a': '1'},
        {'b': '2'},
      ];
      final g = groupByField(docs, 'sv');
      expect(g, isEmpty);
    });

    test('empty input -> empty output', () {
      final g = groupByField(const [], 'sv');
      expect(g, isEmpty);
    });

    test('numeric field values are stringified', () {
      final docs = <Map<String, dynamic>>[
        {'sv': 83674161979544, 'ln': 'X'},
      ];
      final g = groupByField(docs, 'sv');
      expect(g['83674161979544']!.length, 1);
    });
  });
}
