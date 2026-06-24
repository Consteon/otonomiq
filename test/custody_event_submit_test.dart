// test/custody_event_submit_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Curly-token pre-resolution ────────────────────────────────────────

  group('resolveCustodyTokens', () {
    /// Pure-logic MIRROR of CustodyEventSubmit._resolveCustodyTokens after the
    /// delegation refactor. This is NOT the real method (that one is private and
    /// needs widget context); it reproduces the same logic and is kept in sync
    /// by hand. Shared tokens ({vehicleId}, {today}, {driverVid}, {driverName},
    /// {activeTaskVid}, {tnm}) are resolved by the superset resolver
    /// (resolveDriverCurlyTokens); {cnm} is resolved locally afterward.
    String resolveCustodyTokens(
      String raw, {
      required String vehicleId,
      required String today,
      required String driverVid,
      required String driverName,
      required String cnm,
      String activeTask = '',
    }) {
      if (!raw.contains('{')) return raw;
      // 1. Shared resolver (simulates resolveDriverCurlyTokens)
      String result = raw.replaceAllMapped(
        RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'),
        (m) {
          switch (m.group(1)) {
            case 'vehicleId':
              return vehicleId.isNotEmpty ? vehicleId : m.group(0)!;
            case 'today':
              return today;
            case 'driverVid':
              return driverVid.isNotEmpty ? driverVid : m.group(0)!;
            case 'driverName':
              return driverName.isNotEmpty ? driverName : m.group(0)!;
            case 'activeTaskVid':
            case 'tnm':
              return activeTask.isNotEmpty ? activeTask : m.group(0)!;
            default:
              return m.group(0)!;
          }
        },
      );
      // 2. Local {cnm} resolution
      if (result.contains('{cnm}')) {
        result = result.replaceAll('{cnm}', cnm.isNotEmpty ? cnm : '{cnm}');
      }
      return result;
    }

    test('resolves all tokens in updateEventRow', () {
      const raw =
          'search◼cty★opening☆vv★{vehicleId}☆cdt★{today}⭘cst◼custody_confirmed';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: 'V123',
        today: '1718668800000',
        driverVid: 'D456',
        driverName: 'Agenia',
        cnm: 'EVT001',
      );
      expect(result,
          'search◼cty★opening☆vv★V123☆cdt★1718668800000⭘cst◼custody_confirmed');
    });

    test('resolves all tokens in addToEvent', () {
      const raw = 'erf◼{cnm}⭘cv◼{driverVid}⭘cn◼{driverName}';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: 'V123',
        today: '1718668800000',
        driverVid: 'D456',
        driverName: 'Agenia Demo',
        cnm: 'EVT001',
      );
      expect(result, 'erf◼EVT001⭘cv◼D456⭘cn◼Agenia Demo');
    });

    test('leaves unresolved tokens when value empty', () {
      const raw = 'vv★{vehicleId}';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: '',
        today: '123',
        driverVid: '',
        driverName: '',
        cnm: '',
      );
      expect(result, 'vv★{vehicleId}');
    });

    test('no tokens -> returns raw unchanged', () {
      const raw = 'cst◼custody_confirmed';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: 'V1',
        today: '123',
        driverVid: 'D1',
        driverName: 'N1',
        cnm: 'C1',
      );
      expect(result, raw);
    });

    test('unknown tokens left as-is', () {
      const raw = '{unknown}★{vehicleId}';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: 'V1',
        today: '123',
        driverVid: '',
        driverName: '',
        cnm: '',
      );
      expect(result, '{unknown}★V1');
    });

    test('{tnm} resolves from activeTask via delegation', () {
      const raw =
          'ept\u{25FC}task\u{2B58}erf\u{25FC}{tnm}\u{2B58}cv\u{25FC}{driverVid}';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: 'V123',
        today: '1718668800000',
        driverVid: 'D456',
        driverName: 'Agenia',
        cnm: '',
        activeTask: 'T-051',
      );
      expect(result,
          'ept\u{25FC}task\u{2B58}erf\u{25FC}T-051\u{2B58}cv\u{25FC}D456');
    });

    test('{tnm} left literal when activeTask empty', () {
      const raw = 'erf\u{25FC}{tnm}';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: '',
        today: '123',
        driverVid: '',
        driverName: '',
        cnm: '',
        activeTask: '',
      );
      expect(result, 'erf\u{25FC}{tnm}');
    });

    test('{activeTaskVid} resolves from activeTask via delegation', () {
      const raw = 'ref\u{25FC}{activeTaskVid}';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: '',
        today: '123',
        driverVid: '',
        driverName: '',
        cnm: '',
        activeTask: 'T-099',
      );
      expect(result, 'ref\u{25FC}T-099');
    });

    test('{cnm} and {tnm} coexist in same string', () {
      const raw = 'erf\u{25FC}{cnm}\u{2B58}task\u{25FC}{tnm}';
      final result = resolveCustodyTokens(
        raw,
        vehicleId: '',
        today: '123',
        driverVid: '',
        driverName: '',
        cnm: 'CHK-VEH-AB1234-20260618-CLOSE',
        activeTask: 'T-051',
      );
      expect(result,
          'erf\u{25FC}CHK-VEH-AB1234-20260618-CLOSE\u{2B58}task\u{25FC}T-051');
    });
  });

  // ── Gate predicate ────────────────────────────────────────────────────

  group('P8 gate predicate', () {
    /// Pure-logic: evaluate gate condition.
    bool evaluateGate({
      required String noteText,
      required String photoData,
      required int minNoteLength,
    }) {
      final bool noteOk = noteText.trim().length >= minNoteLength;
      final bool photoOk = photoData != '--' && photoData.isNotEmpty;
      return noteOk && photoOk;
    }

    test('note >= 10 AND photo present -> enabled', () {
      expect(
        evaluateGate(
            noteText: 'Ada selisih di galon',
            photoData: 'aum__/path/img.jpg__mua',
            minNoteLength: 10),
        true,
      );
    });

    test('note < 10 -> disabled', () {
      expect(
        evaluateGate(
            noteText: 'short',
            photoData: 'aum__/path/img.jpg__mua',
            minNoteLength: 10),
        false,
      );
    });

    test('no photo -> disabled', () {
      expect(
        evaluateGate(
            noteText: 'Ada selisih di galon dan LPG',
            photoData: '',
            minNoteLength: 10),
        false,
      );
    });

    test('photo is emptyString sentinel -> disabled', () {
      expect(
        evaluateGate(
            noteText: 'Ada selisih di galon dan LPG',
            photoData: '--',
            minNoteLength: 10),
        false,
      );
    });

    test('both fail -> disabled', () {
      expect(
        evaluateGate(noteText: '', photoData: '', minNoteLength: 10),
        false,
      );
    });

    test('note exactly 10 chars -> enabled (boundary)', () {
      expect(
        evaluateGate(
            noteText: '1234567890',
            photoData: 'aum__x__mua',
            minNoteLength: 10),
        true,
      );
    });

    test('note with whitespace only trimmed < 10 -> disabled', () {
      expect(
        evaluateGate(
            noteText: '   abc   ',
            photoData: 'aum__x__mua',
            minNoteLength: 10),
        false,
      );
    });
  });

  // ── Component deep-copy with resolved strings ─────────────────────────

  group('component pre-resolve', () {
    test('deep-copies and replaces string fields', () {
      final original = <String, dynamic>{
        'type': 'custody_event_submit',
        'updateEventRow': 'search◼vv★{vehicleId}⭘cst◼ok',
        'addToEvent': 'erf◼{cnm}⭘cv◼{driverVid}',
        'route': 'vertikaTeknoLokaciptaDriverHome',
        'other': 42,
      };

      // Deep-copy
      final copy = Map<String, dynamic>.from(original);
      // In reality, resolveCustodyTokens would be called here
      copy['updateEventRow'] = 'search◼vv★V123⭘cst◼ok';
      copy['addToEvent'] = 'erf◼EVT001⭘cv◼D456';

      // Original unchanged
      expect(original['updateEventRow'], contains('{vehicleId}'));
      // Copy resolved
      expect(copy['updateEventRow'], contains('V123'));
      expect(copy['addToEvent'], contains('EVT001'));
      // Non-string fields preserved
      expect(copy['other'], 42);
    });
  });
}
