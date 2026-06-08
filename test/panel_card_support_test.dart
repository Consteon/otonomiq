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

  group('latestPatrolByPoint', () {
    test('keeps max t per lq, patrol-type only, skips empty/zero', () {
      final m = latestPatrolByPoint([
        {'ty': 'report-patrol', 'lq': 'A', 't': '100'},
        {'ty': 'report-patrol', 'lq': 'A', 't': '300'}, // newer wins
        {'ty': 'report-patrol', 'lq': 'A', 't': '200'},
        {'ty': 'report-incident', 'lq': 'A', 't': '999'}, // not patrol -> ignored
        {'ty': 'report-patrol', 'lq': '', 't': '500'}, // empty lq -> ignored
        {'ty': 'report-patrol', 'lq': 'B', 't': '50'},
      ]);
      expect(m['A'], 300);
      expect(m['B'], 50);
      expect(m.containsKey(''), isFalse);
    });
    test('falls back to et when t missing', () {
      final m = latestPatrolByPoint([
        {'ty': 'patrol', 'lq': 'A', 'et': '700'},
      ]);
      expect(m['A'], 700);
    });
  });

  group('computePatroli', () {
    const now = 1000000000000; // fixed "now" for tests
    const stale = 43200000; // 12h
    test('recent visits -> staleCount 0, qs ok', () {
      final ll = [
        {'li': 'A'},
        {'li': 'B'}
      ];
      final last = {'A': now - 1000, 'B': now - 2000};
      final r = computePatroli(ll, last, now, stale);
      expect(r.llCount, 2);
      expect(r.staleCount, 0);
      expect(r.qs, 'ok');
    });
    test('one stale visit -> staleCount 1, qs warn, longestGap hours', () {
      final ll = [
        {'li': 'A'},
        {'li': 'B'}
      ];
      final last = {'A': now - (stale + 3600000), 'B': now - 1000}; // A 13h ago
      final r = computePatroli(ll, last, now, stale);
      expect(r.staleCount, 1);
      expect(r.qs, 'warn');
      expect(r.longestGapHours, 13);
    });
    test('never-patrolled point counts as stale', () {
      final ll = [
        {'li': 'A'},
        {'li': 'B'}
      ];
      final last = {'A': now - 1000}; // B never visited
      final r = computePatroli(ll, last, now, stale);
      expect(r.staleCount, 1);
      expect(r.qs, 'warn');
    });
    test('non-map / missing li tolerated', () {
      final ll = [
        'oops',
        {'li': 'A'}
      ];
      final r = computePatroli(ll, {'A': now - 1000}, now, stale);
      expect(r.llCount, 1);
      expect(r.staleCount, 0);
    });
  });
}
