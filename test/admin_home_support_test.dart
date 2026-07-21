import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/firestore_repository/update_event_row.dart';
import 'package:otonomiq/widget/admin_home_support.dart';

void main() {
  // ── computeAge ────────────────────────────────────────────────────────
  group('computeAge', () {
    test('returns diff when anchor is in the past', () {
      final int now = 1000000;
      expect(computeAge(900000, nowMs: now), 100000);
    });

    test('returns 0 when anchor is null', () {
      expect(computeAge(null, nowMs: 1000000), 0);
    });

    test('returns 0 when anchor is 0', () {
      expect(computeAge(0, nowMs: 1000000), 0);
    });

    test('returns 0 when anchor is in the future', () {
      expect(computeAge(2000000, nowMs: 1000000), 0);
    });

    test('returns 0 when anchor is negative', () {
      expect(computeAge(-100, nowMs: 1000000), 0);
    });

    test('handles string anchor', () {
      expect(computeAge('900000', nowMs: 1000000), 100000);
    });

    test('handles empty string anchor', () {
      expect(computeAge('', nowMs: 1000000), 0);
    });

    test('handles non-numeric string anchor', () {
      expect(computeAge('abc', nowMs: 1000000), 0);
    });
  });

  // ── statusTier ────────────────────────────────────────────────────────
  group('statusTier', () {
    test('returns danger above 90min threshold', () {
      // 91 minutes in ms
      expect(statusTier(91 * 60 * 1000), 'danger');
    });

    test('returns warn above 30min threshold', () {
      // 31 minutes in ms
      expect(statusTier(31 * 60 * 1000), 'warn');
    });

    test('returns ok below 30min threshold', () {
      // 29 minutes in ms
      expect(statusTier(29 * 60 * 1000), 'ok');
    });

    test('returns danger at exactly 90min+1ms', () {
      expect(statusTier(kDangerThresholdMs + 1), 'danger');
    });

    test('returns warn at exactly 90min (boundary)', () {
      // 90 min exactly is NOT > 90 min, so warn
      expect(statusTier(kDangerThresholdMs), 'warn');
    });

    test('returns warn at exactly 30min+1ms', () {
      expect(statusTier(kWarnThresholdMs + 1), 'warn');
    });

    test('returns ok at exactly 30min (boundary)', () {
      // 30 min exactly is NOT > 30 min, so ok
      expect(statusTier(kWarnThresholdMs), 'ok');
    });

    test('returns ok at 0', () {
      expect(statusTier(0), 'ok');
    });

    test('custom thresholds override defaults', () {
      // Custom: danger > 120 min, warn > 60 min
      final int ms120 = 121 * 60 * 1000;
      final int ms61 = 61 * 60 * 1000;
      final int ms60 = 60 * 60 * 1000;
      expect(statusTier(ms120, dangerMs: 120 * 60 * 1000, warnMs: 60 * 60 * 1000), 'danger');
      expect(statusTier(ms61, dangerMs: 120 * 60 * 1000, warnMs: 60 * 60 * 1000), 'warn');
      expect(statusTier(ms60, dangerMs: 120 * 60 * 1000, warnMs: 60 * 60 * 1000), 'ok');
    });
  });

  // ── formatAge ─────────────────────────────────────────────────────────
  group('formatAge', () {
    test('formats hours and minutes', () {
      expect(formatAge(135 * 60000), '2j 15m'); // 2h 15m
    });

    test('formats hours only', () {
      expect(formatAge(120 * 60000), '2j'); // exactly 2h
    });

    test('formats minutes only', () {
      expect(formatAge(45 * 60000), '45m');
    });

    test('formats sub-minute', () {
      expect(formatAge(30000), '< 1m'); // 30 seconds
    });

    test('formats 0', () {
      expect(formatAge(0), '< 1m');
    });
  });

  // ── countBerjalan ─────────────────────────────────────────────────────
  group('countBerjalan', () {
    final List<Map<String, dynamic>> checks = [
      {'cst': 'custody_confirmed', 'cdt': '1719100800000'},
      {'cst': 'custody_confirmed', 'cdt': '1719100800000'},
      {'cst': 'awaiting_custody', 'cdt': '1719100800000'},
      {'cst': 'custody_confirmed', 'cdt': '1719014400000'}, // different day
    ];

    test('counts matching docs', () {
      expect(
        countBerjalan(checks, todayStr: '1719100800000'),
        2,
      );
    });

    test('returns 0 on empty list', () {
      expect(countBerjalan([], todayStr: '1719100800000'), 0);
    });

    test('returns 0 when no match', () {
      expect(countBerjalan(checks, todayStr: '9999999999999'), 0);
    });

    test('handles missing fields gracefully', () {
      final List<Map<String, dynamic>> partial = [
        {'cst': 'custody_confirmed'}, // no cdt
        {'cdt': '1719100800000'}, // no cst
        {}, // empty
      ];
      expect(countBerjalan(partial, todayStr: '1719100800000'), 0);
    });
  });

  // ── deriveAdminSignals ────────────────────────────────────────────────
  group('deriveAdminSignals', () {
    const int now = 1719200000000; // fixed "now" for deterministic tests
    const String today = '1719100800000';

    // Gate DSLs from spec(2) -- used across all tests
    const String uGate = 'tst\u{25FC}assigned\u{2B58}vv\u{25FC}';
    const String rGate = 'tst\u{25FC}load_rejected';
    const String nGate = 'lt\u{25FC}vehicle\u{2B58}dv\u{25FC}';
    const String bGate = 'cty\u{25FC}opening\u{2B58}cst\u{25FC}awaiting_custody';

    test('empty collections produce empty signals', () {
      final result = deriveAdminSignals(
        tasks: const [],
        stockLocations: const [],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result, isEmpty);
    });

    test('unassigned_vehicle: task assigned + vv empty', () {
      final result = deriveAdminSignals(
        tasks: [
          {
            'tst': 'assigned',
            'vv': '',
            'tnm': 'T001',
            'kn': 'Customer A',
            'al': 'Jl. Test 1',
            'tdt': today,
            't': now - 45 * 60 * 1000, // 45 min ago
          },
        ],
        stockLocations: const [],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result.length, 1);
      expect(result.first.type, 'unassigned_vehicle');
      expect(result.first.head, 'Customer A');
      expect(result.first.tier, 'warn');
      expect(result.first.taskVid, 'T001');
      expect(result.first.address, 'Jl. Test 1');
    });

    test('unassigned_vehicle: task assigned + vv null (dynamic map)', () {
      final result = deriveAdminSignals(
        tasks: [
          {
            'tst': 'assigned',
            'tnm': 'T002',
            'kn': 'Customer B',
            't': now - 100 * 60 * 1000, // 100 min ago -> danger
          },
        ],
        stockLocations: const [],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result.length, 1);
      expect(result.first.type, 'unassigned_vehicle');
      expect(result.first.tier, 'danger');
    });

    test('task_returned: load_rejected with evidence reason', () {
      final result = deriveAdminSignals(
        tasks: [
          {
            'tst': 'load_rejected',
            'tnm': 'T003',
            'kn': 'Customer C',
            't': now - 60 * 60 * 1000,
          },
        ],
        stockLocations: const [],
        vehicleChecks: const [],
        evidenceDocs: [
          {
            'ept': 'task',
            'erf': 'T003',
            'd': 'Barang rusak',
            't': now - 20 * 60 * 1000, // 20 min ago -> ok
          },
        ],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result.length, 1);
      expect(result.first.type, 'task_returned');
      expect(result.first.summary, contains('Barang rusak'));
      // Age from evidence t (20 min), not task t (60 min)
      expect(result.first.tier, 'ok');
      expect(result.first.taskVid, 'T003');
    });

    test('task_returned: no matching evidence -> fallback to task.t', () {
      final result = deriveAdminSignals(
        tasks: [
          {
            'tst': 'load_rejected',
            'tnm': 'T004',
            'kn': 'Customer D',
            't': now - 95 * 60 * 1000, // 95 min ago -> danger
          },
        ],
        stockLocations: const [],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result.length, 1);
      expect(result.first.type, 'task_returned');
      expect(result.first.tier, 'danger');
      expect(result.first.summary, contains('Dikembalikan driver'));
      // No reason suffix
      expect(result.first.summary.contains('\u{00B7}'), isFalse);
    });

    test('no_executor: vehicle without driver + assigned tasks', () {
      final result = deriveAdminSignals(
        tasks: [
          {
            'tst': 'assigned',
            'vv': 'VEH01',
            'tnm': 'T005',
            'kn': 'Cust E',
            't': now - 50 * 60 * 1000,
          },
          {
            'tst': 'assigned',
            'vv': 'VEH01',
            'tnm': 'T006',
            'kn': 'Cust F',
            't': now - 10 * 60 * 1000,
          },
        ],
        stockLocations: [
          {'lt': 'vehicle', 'lv': 'VEH01', 'ln': 'B 1234 XY', 'dv': ''},
        ],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result.length, 1);
      expect(result.first.type, 'no_executor');
      expect(result.first.head, 'B 1234 XY');
      expect(result.first.summary, contains('2 task'));
      expect(result.first.vehicleId, 'VEH01');
      // Age from oldest task t (50 min)
      expect(result.first.tier, 'warn');
    });

    test('no_executor: vehicle with driver is NOT a signal', () {
      final result = deriveAdminSignals(
        tasks: [
          {'tst': 'assigned', 'vv': 'VEH02', 'tnm': 'T007', 't': now - 50 * 60 * 1000},
        ],
        stockLocations: [
          {'lt': 'vehicle', 'lv': 'VEH02', 'ln': 'B 5678 AB', 'dv': 'DRV001'},
        ],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result, isEmpty);
    });

    test('blocked_departure: opening awaiting_custody + today task', () {
      final result = deriveAdminSignals(
        tasks: [
          {'tst': 'assigned', 'vv': 'VEH03', 'tnm': 'T008', 'tdt': today, 't': now},
        ],
        stockLocations: [
          {'lt': 'vehicle', 'lv': 'VEH03', 'ln': 'B 9999 CD', 'dv': 'DRV002'},
        ],
        vehicleChecks: [
          {
            'cty': 'opening',
            'cst': 'awaiting_custody',
            'vv': 'VEH03',
            't': now - 35 * 60 * 1000, // 35 min -> warn
          },
        ],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result.length, 1);
      expect(result.first.type, 'blocked_departure');
      expect(result.first.head, 'B 9999 CD');
      expect(result.first.tier, 'warn');
      expect(result.first.vehicleId, 'VEH03');
    });

    test('blocked_departure: no today task -> no signal', () {
      final result = deriveAdminSignals(
        tasks: [
          {'tst': 'assigned', 'vv': 'VEH04', 'tnm': 'T009', 'tdt': '9999999', 't': now},
        ],
        stockLocations: [
          {'lt': 'vehicle', 'lv': 'VEH04', 'ln': 'B 0000 EF', 'dv': 'DRV003'},
        ],
        vehicleChecks: [
          {'cty': 'opening', 'cst': 'awaiting_custody', 'vv': 'VEH04', 't': now - 35 * 60 * 1000},
        ],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result, isEmpty);
    });

    test('sort: clusters by maxAge desc, items by age desc', () {
      // 2 unassigned (ages 10m, 50m) + 1 no_executor (age 95m)
      // Expected: no_executor first (maxAge 95m), then unassigned (maxAge 50m)
      // Within unassigned: 50m first, then 10m
      final result = deriveAdminSignals(
        tasks: [
          {'tst': 'assigned', 'vv': '', 'tnm': 'A1', 'kn': 'C1', 't': now - 10 * 60 * 1000},
          {'tst': 'assigned', 'vv': '', 'tnm': 'A2', 'kn': 'C2', 't': now - 50 * 60 * 1000},
          {'tst': 'assigned', 'vv': 'VEH05', 'tnm': 'A3', 'kn': 'C3', 't': now - 95 * 60 * 1000},
        ],
        stockLocations: [
          {'lt': 'vehicle', 'lv': 'VEH05', 'ln': 'Plate X', 'dv': ''},
        ],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      expect(result.length, 3);
      // First: no_executor (maxAge 95m)
      expect(result[0].type, 'no_executor');
      // Then: unassigned, age 50m
      expect(result[1].type, 'unassigned_vehicle');
      expect(result[1].head, 'C2');
      // Then: unassigned, age 10m
      expect(result[2].type, 'unassigned_vehicle');
      expect(result[2].head, 'C1');
    });

    test('malformed map fields do not crash', () {
      final result = deriveAdminSignals(
        tasks: [
          {'tst': 123, 'vv': null, 'tnm': null, 'kn': null, 't': 'not_a_number'},
        ],
        stockLocations: [
          {'lt': 123, 'lv': null, 'dv': null},
        ],
        vehicleChecks: [
          {'cty': null, 'cst': null, 'vv': null, 't': null},
        ],
        evidenceDocs: [
          {'ept': null, 'erf': null, 'd': null, 't': null},
        ],
        todayStr: today,
        nowMs: now,
        unassignedGate: uGate,
        returnedGate: rGate,
        noExecutorGate: nGate,
        blockedGate: bGate,
      );
      // Should not throw; may produce 0 signals (all guards fail safely)
      expect(result, isA<List<Signal>>());
    });

    test('empty gates produce no signals even with matching data', () {
      final result = deriveAdminSignals(
        tasks: [
          {'tst': 'assigned', 'vv': '', 'tnm': 'T001', 'kn': 'Cust', 't': now - 45 * 60 * 1000},
        ],
        stockLocations: const [],
        vehicleChecks: const [],
        evidenceDocs: const [],
        todayStr: today,
        nowMs: now,
        // No gate params = empty = no signals
      );
      expect(result, isEmpty);
    });
  });

  // ── computeAdminStopProgress ─────────────────────────────────────────
  group('computeAdminStopProgress', () {
    test('counts completed and total for a vehicle', () {
      final tasks = [
        {'vv': 'V1', 'tst': 'completed'},
        {'vv': 'V1', 'tst': 'assigned'},
        {'vv': 'V1', 'tst': 'on_delivery'},
        {'vv': 'V2', 'tst': 'completed'}, // different vehicle
      ];
      final p = computeAdminStopProgress(tasks, 'V1');
      expect(p.completed, 1);
      expect(p.total, 3);
    });

    test('excludes load_rejected from total', () {
      final tasks = [
        {'vv': 'V1', 'tst': 'load_rejected'},
        {'vv': 'V1', 'tst': 'assigned'},
      ];
      final p = computeAdminStopProgress(tasks, 'V1');
      expect(p.completed, 0);
      expect(p.total, 1); // load_rejected excluded
    });

    test('returns 0/0 for unknown vehicle', () {
      final p = computeAdminStopProgress([], 'V1');
      expect(p.completed, 0);
      expect(p.total, 0);
    });

    test('handles done and closed as completed', () {
      final tasks = [
        {'vv': 'V1', 'tst': 'done'},
        {'vv': 'V1', 'tst': 'closed'},
        {'vv': 'V1', 'tst': 'assigned'},
      ];
      final p = computeAdminStopProgress(tasks, 'V1');
      expect(p.completed, 2);
      expect(p.total, 3);
    });

    test('handles null/missing vv gracefully', () {
      final tasks = [
        {'tst': 'assigned'}, // no vv
        {'vv': null, 'tst': 'completed'},
      ];
      final p = computeAdminStopProgress(tasks, 'V1');
      expect(p.completed, 0);
      expect(p.total, 0);
    });
  });

  // ── lastCompletedStopName ────────────────────────────────────────────
  group('lastCompletedStopName', () {
    test('finds name of most recently completed task', () {
      final tasks = [
        {'vv': 'V1', 'tst': 'completed', 'kn': 'Old Stop', 'tce': 100},
        {'vv': 'V1', 'tst': 'completed', 'kn': 'Latest Stop', 'tce': 200},
        {'vv': 'V1', 'tst': 'assigned', 'kn': 'Not Done'},
      ];
      expect(lastCompletedStopName(tasks, 'V1'), 'Latest Stop');
    });

    test('returns empty when no completed tasks', () {
      final tasks = [
        {'vv': 'V1', 'tst': 'assigned', 'kn': 'Cust'},
      ];
      expect(lastCompletedStopName(tasks, 'V1'), '');
    });

    test('returns empty for unknown vehicle', () {
      expect(lastCompletedStopName([], 'V1'), '');
    });
  });

  // ── summarizeItems ───────────────────────────────────────────────────
  group('summarizeItems', () {
    test('sums drop and pickup from item list', () {
      final items = [
        {'pd': 3, 'pp': 2},
        {'pd': '1', 'pp': '4'},
      ];
      expect(summarizeItems(items), 'Drop 4 \u{00B7} Pickup 6');
    });

    test('drop only', () {
      final items = [
        {'pd': 5, 'pp': 0}
      ];
      expect(summarizeItems(items), 'Drop 5');
    });

    test('pickup only', () {
      final items = [
        {'pd': 0, 'pp': 3}
      ];
      expect(summarizeItems(items), 'Pickup 3');
    });

    test('returns empty for non-list', () {
      expect(summarizeItems(null), '');
      expect(summarizeItems('not a list'), '');
    });

    test('returns empty when both sums are 0', () {
      final items = [
        {'pd': 0, 'pp': 0}
      ];
      expect(summarizeItems(items), '');
    });

    test('skips non-map entries', () {
      final items = [
        'not a map',
        {'pd': 2, 'pp': 0}
      ];
      expect(summarizeItems(items), 'Drop 2');
    });

    test('handles custom labels', () {
      final items = [
        {'pd': 1, 'pp': 1}
      ];
      expect(
        summarizeItems(items, dropLabel: 'Kirim', pickupLabel: 'Ambil'),
        'Kirim 1 \u{00B7} Ambil 1',
      );
    });
  });

  // ── formatTimePill ───────────────────────────────────────────────────
  group('formatTimePill', () {
    test('formats epoch-ms to HH:mm WIB', () {
      // 2024-06-23 06:00:00 UTC = 13:00 WIB
      final int utc6am = DateTime.utc(2024, 6, 23, 6, 0).millisecondsSinceEpoch;
      expect(formatTimePill(utc6am), '13:00');
    });

    test('returns empty for 0', () {
      expect(formatTimePill(0), '');
    });

    test('returns empty for null', () {
      expect(formatTimePill(null), '');
    });

    test('handles string input', () {
      final int ms = DateTime.utc(2024, 6, 23, 10, 30).millisecondsSinceEpoch;
      expect(formatTimePill('$ms'), '17:30');
    });

    test('returns empty for non-numeric string', () {
      expect(formatTimePill('abc'), '');
    });
  });

  // ── agingTierDays ────────────────────────────────────────────────────
  group('agingTierDays', () {
    test('kritis above 14 days (default)', () {
      expect(agingTierDays(15), 'kritis');
    });

    test('perhatian above 7 days (default)', () {
      expect(agingTierDays(8), 'perhatian');
    });

    test('normal at or below 7 days', () {
      expect(agingTierDays(7), 'normal');
    });

    test('normal at 0', () {
      expect(agingTierDays(0), 'normal');
    });

    test('kritis at boundary (14 is not > 14)', () {
      expect(agingTierDays(14), 'perhatian');
    });

    test('custom thresholds override defaults', () {
      // With custom thresholds: danger > 60, warn > 30
      expect(agingTierDays(61, dangerDays: 60, warnDays: 30), 'kritis');
      expect(agingTierDays(31, dangerDays: 60, warnDays: 30), 'perhatian');
      expect(agingTierDays(30, dangerDays: 60, warnDays: 30), 'normal');
    });
  });

  // ── formatAgeDays ────────────────────────────────────────────────────
  group('formatAgeDays', () {
    test('formats positive days', () {
      expect(formatAgeDays(5), '5 hari');
    });

    test('formats 0 as < 1 hari', () {
      expect(formatAgeDays(0), '< 1 hari');
    });

    test('formats negative as < 1 hari', () {
      expect(formatAgeDays(-1), '< 1 hari');
    });
  });

  // ── groupOutstanding ─────────────────────────────────────────────────
  group('groupOutstanding', () {
    const int now = 1719200000000;

    test('groups by client, sums qty, computes aging', () {
      final acDocs = [
        {
          'lv': 'C1',
          'lt': 'client',
          'ii': 'Gas',
          'qt': 3,
          't': now - 20 * 86400000
        }, // 20 days
        {
          'lv': 'C1',
          'lt': 'client',
          'ii': 'Tabung',
          'qt': 5,
          't': now - 10 * 86400000
        }, // 10 days
      ];
      final slDocs = [
        {'lv': 'C1', 'lt': 'client', 'ln': 'Toko Berkah'},
      ];
      final groups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: slDocs,
        nowMs: now,
      );
      expect(groups.length, 1);
      expect(groups.first.clientName, 'Toko Berkah');
      expect(groups.first.totalQty, 8);
      expect(groups.first.agingDays, 20);
      expect(groups.first.tier, 'kritis'); // 20 > 14 (new default)
      expect(groups.first.itemSummary, startsWith('Gas'));
    });

    test('hideZero: skips groups with total qty <= 0', () {
      final acDocs = [
        {'lv': 'C2', 'lt': 'client', 'ii': 'Gas', 'qt': 0, 't': now},
      ];
      final groups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: [],
        nowMs: now,
      );
      expect(groups, isEmpty);
    });

    test('skips non-client docs', () {
      final acDocs = [
        {'lv': 'W1', 'lt': 'warehouse', 'ii': 'Gas', 'qt': 5, 't': now},
      ];
      final groups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: [],
        nowMs: now,
      );
      expect(groups, isEmpty);
    });

    test('sorts by aging desc (oldest first)', () {
      final acDocs = [
        {
          'lv': 'C1',
          'lt': 'client',
          'ii': 'A',
          'qt': 1,
          't': now - 5 * 86400000
        }, // 5 days
        {
          'lv': 'C2',
          'lt': 'client',
          'ii': 'B',
          'qt': 2,
          't': now - 40 * 86400000
        }, // 40 days
      ];
      final groups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: [],
        nowMs: now,
      );
      expect(groups.length, 2);
      expect(groups.first.clientId, 'C2'); // 40 days first
      expect(groups.first.tier, 'kritis');
      expect(groups.last.clientId, 'C1');
    });

    test('empty docs produce empty groups', () {
      final groups = groupOutstanding(
        assetCacheDocs: [],
        stockLocations: [],
        nowMs: now,
      );
      expect(groups, isEmpty);
    });

    test('falls back to lv when client name missing', () {
      final acDocs = [
        {'lv': 'C3', 'lt': 'client', 'ii': 'X', 'qt': 1, 't': now},
      ];
      final groups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: [], // no matching sl
        nowMs: now,
      );
      expect(groups.first.clientName, 'C3');
    });

    test('custom threshold overrides change tier assignment', () {
      final acDocs = [
        {
          'lv': 'C1',
          'lt': 'client',
          'ii': 'Gas',
          'qt': 3,
          't': now - 10 * 86400000
        }, // 10 days
      ];
      final slDocs = [
        {'lv': 'C1', 'lt': 'client', 'ln': 'Toko'},
      ];
      // Default thresholds (14/7): 10 days > 7 = perhatian
      final defaultGroups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: slDocs,
        nowMs: now,
      );
      expect(defaultGroups.first.tier, 'perhatian');

      // Custom thresholds (5/3): 10 days > 5 = kritis
      final customGroups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: slDocs,
        nowMs: now,
        dangerDays: 5,
        warnDays: 3,
      );
      expect(customGroups.first.tier, 'kritis');
    });

    test('itemSummary includes first item name', () {
      final acDocs = [
        {
          'lv': 'C1',
          'lt': 'client',
          'ii': 'Gas 12kg',
          'qt': 8,
          't': now - 18 * 86400000
        },
        {
          'lv': 'C1',
          'lt': 'client',
          'ii': 'Tabung 3kg',
          'qt': 4,
          't': now - 5 * 86400000
        },
      ];
      final slDocs = [
        {'lv': 'C1', 'lt': 'client', 'ln': 'Toko Gas'},
      ];
      final groups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: slDocs,
        nowMs: now,
      );
      expect(groups.length, 1);
      // Summary starts with first item name
      expect(groups.first.itemSummary, startsWith('Gas 12kg'));
      // Contains total qty
      expect(groups.first.itemSummary, contains('12 pcs'));
      // Contains aging
      expect(groups.first.itemSummary, contains('18 hari'));
    });

    test('itemSummary falls back when item name empty', () {
      final acDocs = [
        {
          'lv': 'C1',
          'lt': 'client',
          'ii': '',
          'qt': 5,
          't': now - 3 * 86400000
        },
      ];
      final groups = groupOutstanding(
        assetCacheDocs: acDocs,
        stockLocations: [],
        nowMs: now,
      );
      expect(groups.first.itemSummary, startsWith('5 pcs'));
    });
  });

  // ── AdminTierColors ──────────────────────────────────────────────────
  group('AdminTierColors', () {
    test('outstandingBadge returns correct colors for kritis', () {
      final (bg, fg) = AdminTierColors.outstandingBadge('kritis');
      expect(bg, const Color(0xFFFEF3C7));
      expect(fg, const Color(0xFFB45309));
    });

    test('outstandingBadge returns correct colors for perhatian', () {
      final (bg, fg) = AdminTierColors.outstandingBadge('perhatian');
      expect(bg, const Color(0xFFEDE9FE));
      expect(fg, const Color(0xFF7C3AED));
    });

    test('outstandingBadge returns correct colors for normal', () {
      final (bg, fg) = AdminTierColors.outstandingBadge('normal');
      expect(bg, const Color(0xFFF1F5F9));
      expect(fg, const Color(0xFF475569));
    });

    test('signalAgePill returns amber for danger', () {
      final (bg, fg) = AdminTierColors.signalAgePill('danger');
      expect(bg, const Color(0xFFFEF3C7));
      expect(fg, const Color(0xFFB45309));
    });

    test('signalAgePill returns neutral for non-danger', () {
      final (bg, fg) = AdminTierColors.signalAgePill('ok');
      expect(bg, const Color(0xFFF1F5F9));
      expect(fg, const Color(0xFF64748B));
    });

    test('signalCard returns danger style when isDanger', () {
      final (bg, border, width) = AdminTierColors.signalCard(true);
      expect(bg, const Color(0xFFFFF7E6));
      expect(border, const Color(0xFFF59E0B));
      expect(width, 1.5);
    });

    test('signalCard returns normal style when not isDanger', () {
      final (bg, border, width) = AdminTierColors.signalCard(false);
      expect(bg, Colors.white);
      expect(border, const Color(0xFFE5E7EB));
      expect(width, 1.0);
    });

    test('signalButton returns outline blue for soft', () {
      final (bg, fg, isOutline) = AdminTierColors.signalButton(
        isSoft: true, isDanger: false, isCross: true,
      );
      expect(bg, Colors.transparent);
      expect(fg, const Color(0xFF2563EB));
      expect(isOutline, true);
    });

    test('signalButton returns solid amber for danger/cross', () {
      final (bg, fg, isOutline) = AdminTierColors.signalButton(
        isSoft: false, isDanger: true, isCross: false,
      );
      expect(bg, const Color(0xFFF59E0B));
      expect(fg, Colors.white);
      expect(isOutline, false);
    });

    test('signalButton returns solid blue for normal admin', () {
      final (bg, fg, isOutline) = AdminTierColors.signalButton(
        isSoft: false, isDanger: false, isCross: false,
      );
      expect(bg, const Color(0xFF2563EB));
      expect(fg, Colors.white);
      expect(isOutline, false);
    });

    test('signalButton returns solid green for invoice tier', () {
      final (bg, fg, isOutline) = AdminTierColors.signalButton(
        isSoft: false, isDanger: false, isCross: false, isOk: true,
      );
      expect(bg, const Color(0xFF15803D));
      expect(fg, Colors.white);
      expect(isOutline, false);
    });

    test('signalButton keeps danger amber even when isOk', () {
      final (bg, _, _) = AdminTierColors.signalButton(
        isSoft: false, isDanger: true, isCross: false, isOk: true,
      );
      expect(bg, const Color(0xFFF59E0B));
    });

    test('signalAgePill returns green when green: true', () {
      final (bg, fg) = AdminTierColors.signalAgePill('ok', green: true);
      expect(bg, const Color(0xFFDCFCE7));
      expect(fg, const Color(0xFF16A34A));
    });

    test('signalAgePill keeps danger amber even when green: true', () {
      final (bg, fg) = AdminTierColors.signalAgePill('danger', green: true);
      expect(bg, const Color(0xFFFEF3C7));
      expect(fg, const Color(0xFFB45309));
    });
  });

  // ── evaluateGate ────────────────────────────────────────────────────
  group('evaluateGate', () {
    test('matches single clause with non-empty value', () {
      final doc = {'tst': 'load_rejected', 'vv': 'V1'};
      expect(evaluateGate(doc, 'tst\u{25FC}load_rejected'), true);
    });

    test('rejects single clause mismatch', () {
      final doc = {'tst': 'assigned', 'vv': 'V1'};
      expect(evaluateGate(doc, 'tst\u{25FC}load_rejected'), false);
    });

    test('matches empty-value clause (field must be empty)', () {
      final doc = {'tst': 'assigned', 'vv': ''};
      expect(evaluateGate(doc, 'tst\u{25FC}assigned\u{2B58}vv\u{25FC}'), true);
    });

    test('rejects empty-value clause when field is non-empty', () {
      final doc = {'tst': 'assigned', 'vv': 'V1'};
      expect(evaluateGate(doc, 'tst\u{25FC}assigned\u{2B58}vv\u{25FC}'), false);
    });

    test('AND: all clauses must match', () {
      final doc = {'cty': 'opening', 'cst': 'awaiting_custody'};
      expect(
        evaluateGate(doc, 'cty\u{25FC}opening\u{2B58}cst\u{25FC}awaiting_custody'),
        true,
      );
    });

    test('AND: partial match returns false', () {
      final doc = {'cty': 'opening', 'cst': 'custody_confirmed'};
      expect(
        evaluateGate(doc, 'cty\u{25FC}opening\u{2B58}cst\u{25FC}awaiting_custody'),
        false,
      );
    });

    test('empty gate returns false', () {
      expect(evaluateGate({'tst': 'assigned'}, ''), false);
    });

    test('null field in doc treated as empty string', () {
      final doc = <String, dynamic>{'tst': 'assigned', 'vv': null};
      expect(evaluateGate(doc, 'tst\u{25FC}assigned\u{2B58}vv\u{25FC}'), true);
    });

    test('missing field in doc treated as empty string', () {
      final doc = <String, dynamic>{'tst': 'assigned'};
      // vv missing = treated as empty
      expect(evaluateGate(doc, 'tst\u{25FC}assigned\u{2B58}vv\u{25FC}'), true);
    });

    test('handles stock_location gate: lt=vehicle AND dv empty', () {
      final doc = {'lt': 'vehicle', 'dv': '', 'ln': 'B 1234'};
      expect(
        evaluateGate(doc, 'lt\u{25FC}vehicle\u{2B58}dv\u{25FC}'),
        true,
      );
    });

    test('stock_location gate rejects when dv present', () {
      final doc = {'lt': 'vehicle', 'dv': 'DRV001', 'ln': 'B 1234'};
      expect(
        evaluateGate(doc, 'lt\u{25FC}vehicle\u{2B58}dv\u{25FC}'),
        false,
      );
    });
  });

  // ── progressFromItems ───────────────────────────────────────────────
  group('progressFromItems', () {
    test('counts done lines by ad or ap markers', () {
      final task = {
        'it': [
          {'pd': 3, 'ad': '3'},    // done (ad present)
          {'pd': 2, 'ap': '2'},    // done (ap present)
          {'pd': 1},               // not done
          {'pd': 4, 'ad': '', 'ap': ''}, // not done (both empty)
        ],
      };
      final (done, total) = progressFromItems(task);
      expect(done, 2);
      expect(total, 4);
    });

    test('returns 0/0 for non-list items', () {
      final (done, total) = progressFromItems({'it': 'not a list'});
      expect(done, 0);
      expect(total, 0);
    });

    test('returns 0/0 for null items', () {
      final (done, total) = progressFromItems({});
      expect(done, 0);
      expect(total, 0);
    });

    test('returns 0/N for empty markers', () {
      final task = {
        'it': [{'pd': 1}, {'pd': 2}],
      };
      final (done, total) = progressFromItems(task, doneMarker: '');
      expect(done, 0);
      expect(total, 2);
    });

    test('custom itemsField', () {
      final task = {
        'items': [
          {'ad': '1'},
          {'pd': 2},
        ],
      };
      final (done, total) = progressFromItems(task, itemsField: 'items');
      expect(done, 1);
      expect(total, 2);
    });

    test('all done', () {
      final task = {
        'it': [
          {'ad': '1', 'ap': '2'},
          {'ad': '3'},
        ],
      };
      final (done, total) = progressFromItems(task);
      expect(done, 2);
      expect(total, 2);
    });

    test('empty list', () {
      final (done, total) = progressFromItems({'it': []});
      expect(done, 0);
      expect(total, 0);
    });
  });

  // ── updateEventRow DSL parsing (parse-level) ────────────────────────
  group('updateEventRow DSL parsing', () {
    test('parseUpdateEventRow extracts collection, tablevid, search, body', () {
      // Spec(2) DSL with resolved tokens
      const String resolved =
          '84214220504259//task\u{2B58}tablevid\u{25FC}20342033315492'
          '\u{2B58}search\u{25FC}tnm\u{2605}T001'
          '\u{2B58}vv\u{25FC}VEH01\u{2B58}tst\u{25FC}assigned';
      final target = parseUpdateEventRow(resolved);
      expect(target.collection, '84214220504259//task');
      expect(target.tablevid, '20342033315492');
      expect(target.conditions.length, 1);
      expect(target.conditions.first.key, 'tnm');
      expect(target.conditions.first.value, 'T001');
      expect(target.body['vv'], 'VEH01');
      expect(target.body['tst'], 'assigned');
    });
  });
}
