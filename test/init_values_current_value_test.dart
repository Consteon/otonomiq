// Guards the seed gate in init_values.dart:16.
//
// Before the fix, an ABSENT `currentValue` key made `null.toString()` produce
// the 4-char string "null", which passed `.trim().isNotEmpty` and was seeded
// into `finalData` -- visible as a picked "null" chip on TABLE_PICKER and a
// literal "null" label on NUMBER (vertikaTeknoLokaciptaAssignExtraWork).

import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/init_values.dart';

void main() {
  group('getInitialValue - absent currentValue', () {
    test('absent key seeds empty, NOT the literal "null"', () {
      final Map<String, dynamic> picker = <String, dynamic>{
        'type': 'TABLE_PICKER',
        'position': 13,
        'labelPosition': 5,
      };
      expect(getInitialValue('scr', picker), '');
    });

    test('explicit empty and whitespace still seed empty', () {
      expect(
        getInitialValue('scr', <String, dynamic>{
          'type': 'TXF',
          'currentValue': '',
        }),
        '',
      );
      expect(
        getInitialValue('scr', <String, dynamic>{
          'type': 'NUMBER',
          'currentValue': '   ',
        }),
        '',
      );
    });

    test('a real value is still seeded verbatim', () {
      expect(
        getInitialValue('scr', <String, dynamic>{
          'type': 'NUMBER',
          'currentValue': 'ASG-2026-000012',
        }),
        'ASG-2026-000012',
      );
    });

    // A sheet cell literally holding "null" is indistinguishable from an absent
    // key AFTER stringification, so it keeps flowing through unchanged. Pinned
    // so a future "strip null everywhere" change is a deliberate decision.
    test('a literal "null" cell value is NOT swallowed by the gate', () {
      expect(
        getInitialValue('scr', <String, dynamic>{
          'type': 'NUMBER',
          'currentValue': 'null',
        }),
        'null',
      );
    });
  });
}
