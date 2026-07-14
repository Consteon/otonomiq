import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/biometric_gate.dart';

void main() {
  group('bioGateRequired', () {
    test('true when component is Map with biometrik: true', () {
      expect(bioGateRequired({'biometrik': true}), isTrue);
    });

    test('false when biometrik is absent', () {
      expect(bioGateRequired({'other': 'value'}), isFalse);
    });

    test('false when biometrik is false', () {
      expect(bioGateRequired({'biometrik': false}), isFalse);
    });

    test('false when biometrik is null', () {
      expect(bioGateRequired({'biometrik': null}), isFalse);
    });

    test('true when biometrik is string "true" (server sends strings)', () {
      expect(bioGateRequired({'biometrik': 'true'}), isTrue);
    });

    test('true when biometrik is string "TRUE" (case-insensitive)', () {
      expect(bioGateRequired({'biometrik': 'TRUE'}), isTrue);
    });

    test('false when biometrik is string "false"', () {
      expect(bioGateRequired({'biometrik': 'false'}), isFalse);
    });

    test('false when biometrik is int 1', () {
      expect(bioGateRequired({'biometrik': 1}), isFalse);
    });

    test('false when component is null', () {
      expect(bioGateRequired(null), isFalse);
    });

    test('false when component is not a Map', () {
      expect(bioGateRequired('not a map'), isFalse);
    });

    test('false when component is empty Map', () {
      expect(bioGateRequired({}), isFalse);
    });
  });

  group('bioGateOutcome', () {
    test('not required -> true (no gate)', () {
      expect(
        bioGateOutcome(
          required: false,
          deviceCanAuth: true,
          authOk: false,
        ),
        isTrue,
      );
    });

    test('required but no device biometric -> true (spec 5 pass-through)', () {
      expect(
        bioGateOutcome(
          required: true,
          deviceCanAuth: false,
          authOk: false,
        ),
        isTrue,
      );
    });

    test('required + device has biometric + auth ok -> true', () {
      expect(
        bioGateOutcome(
          required: true,
          deviceCanAuth: true,
          authOk: true,
        ),
        isTrue,
      );
    });

    test('required + device has biometric + auth fail -> false', () {
      expect(
        bioGateOutcome(
          required: true,
          deviceCanAuth: true,
          authOk: false,
        ),
        isFalse,
      );
    });
  });

  group('bioGatePinAllowed (biometrikPin)', () {
    test('true when biometrikPin is string "true"', () {
      expect(bioGatePinAllowed({'biometrikPin': 'true'}), isTrue);
    });

    test('true when biometrikPin is string "TRUE" (case-insensitive)', () {
      expect(bioGatePinAllowed({'biometrikPin': 'TRUE'}), isTrue);
    });

    test('false when biometrikPin is absent (biometric-only default)', () {
      expect(bioGatePinAllowed({'biometrik': 'true'}), isFalse);
    });

    test('false when biometrikPin is string "false"', () {
      expect(bioGatePinAllowed({'biometrikPin': 'false'}), isFalse);
    });

    test('false when biometrikPin is null', () {
      expect(bioGatePinAllowed({'biometrikPin': null}), isFalse);
    });

    test('false when component is not a Map', () {
      expect(bioGatePinAllowed('not a map'), isFalse);
    });
  });

  group('bioGateTexts (◆-separated biometrikText)', () {
    test('all defaults when biometrikText absent', () {
      final t = bioGateTexts({'biometrik': true});
      expect(t.reason, 'Verifikasi identitas Anda');
      expect(t.failTitle, 'Autentikasi Gagal');
      expect(t.failMessage, 'Verifikasi biometrik gagal. Coba lagi.');
    });

    test('all defaults when component is null / non-Map', () {
      final t = bioGateTexts(null);
      expect(t.reason, 'Verifikasi identitas Anda');
      expect(t.failTitle, 'Autentikasi Gagal');
      expect(t.failMessage, 'Verifikasi biometrik gagal. Coba lagi.');
    });

    test('full three-part string parsed in order', () {
      final t = bioGateTexts({'biometrikText': 'R◆T◆M'});
      expect(t.reason, 'R');
      expect(t.failTitle, 'T');
      expect(t.failMessage, 'M');
    });

    test('partial (two parts) -> third falls back', () {
      final t = bioGateTexts({'biometrikText': 'R◆T'});
      expect(t.reason, 'R');
      expect(t.failTitle, 'T');
      expect(t.failMessage, 'Verifikasi biometrik gagal. Coba lagi.');
    });

    test('single part -> title+message fall back', () {
      final t = bioGateTexts({'biometrikText': 'R'});
      expect(t.reason, 'R');
      expect(t.failTitle, 'Autentikasi Gagal');
      expect(t.failMessage, 'Verifikasi biometrik gagal. Coba lagi.');
    });

    test('blank leading segments fall back per-part', () {
      final t = bioGateTexts({'biometrikText': '◆◆M'});
      expect(t.reason, 'Verifikasi identitas Anda');
      expect(t.failTitle, 'Autentikasi Gagal');
      expect(t.failMessage, 'M');
    });

    test('empty string -> all defaults', () {
      final t = bioGateTexts({'biometrikText': ''});
      expect(t.reason, 'Verifikasi identitas Anda');
      expect(t.failTitle, 'Autentikasi Gagal');
      expect(t.failMessage, 'Verifikasi biometrik gagal. Coba lagi.');
    });
  });

  // Note: bioGate() itself (the orchestrator) calls LocalAuthentication()
  // which is a platform plugin singleton. Without DI seam / mocktail (not in
  // this repo), it cannot be unit-tested. Runtime coverage is device-QA only.
  // The two pure functions above cover all decision logic.
}
