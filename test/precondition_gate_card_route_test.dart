import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/precondition_gate_card.dart';

/// PRECONDITION_GATE_CARD custody mode toggle (custody-mode-toggle spec §4.2).
///
/// Mode A (count) keeps `route`; Mode B (ack) opens `ackRoute`.
void main() {
  const String count = 'vertikaTeknoLokaciptaCustodyNotification';
  const String ack = 'vertikaTeknoLokaciptaCustodyAck';

  group('PreconditionGateCard.resolveCtaRoute', () {
    test('custodyMode absent -> route (backward-compat, Mode A)', () {
      expect(
        PreconditionGateCard.resolveCtaRoute(<String, dynamic>{'route': count}),
        count,
      );
    });

    test('custodyMode "count" -> route', () {
      expect(
        PreconditionGateCard.resolveCtaRoute(<String, dynamic>{
          'route': count,
          'custodyMode': 'count',
          'ackRoute': ack,
        }),
        count,
      );
    });

    test('custodyMode "ack" -> ackRoute (Mode B)', () {
      expect(
        PreconditionGateCard.resolveCtaRoute(<String, dynamic>{
          'route': count,
          'custodyMode': 'ack',
          'ackRoute': ack,
        }),
        ack,
      );
    });

    test('custodyMode " ACK " -> ackRoute (trimmed, case-insensitive)', () {
      expect(
        PreconditionGateCard.resolveCtaRoute(<String, dynamic>{
          'route': count,
          'custodyMode': ' ACK ',
          'ackRoute': ack,
        }),
        ack,
      );
    });

    test('custodyMode "ack" but ackRoute missing -> falls back to route', () {
      expect(
        PreconditionGateCard.resolveCtaRoute(<String, dynamic>{
          'route': count,
          'custodyMode': 'ack',
        }),
        count,
      );
    });

    test('nothing configured -> empty (CTA no-ops, no crash)', () {
      expect(
        PreconditionGateCard.resolveCtaRoute(<String, dynamic>{}),
        '',
      );
    });
  });
}
