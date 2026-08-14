import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/sdui_spec.dart';
import 'package:otonomiq/widget/doc_download.dart';

/// Tests for DOC_DOWNLOAD decision-rule functions.
///
/// Each test names the production change that would turn it RED.
///
/// What CANNOT be tested here (requires device QA):
/// - Real HTTP download (createFileOfPdfUrl uses HttpClient)
/// - Firebase Storage getDownloadURL (requires live Firebase)
/// - SharePlus share sheet + ShareResult.status (native OS dialog)
/// - bioGate biometric prompt (LocalAuthentication)
/// - Token resolution (TokenResolver.curly has side effects)
void main() {
  group('docDownloadTexts', () {
    // RED if: default label changes from 'Unduh'
    test('all defaults when text is empty', () {
      final spec = SduiSpec({});
      final t = docDownloadTexts(spec);
      expect(t.label, 'Unduh');
      expect(t.progress, 'Mengunduh…');
      expect(t.success, 'Tersimpan');
      expect(t.failure, 'Gagal mengunduh');
    });

    // RED if: SduiSpec.text stops returning config values at correct indexes
    test('all 4 slots provided', () {
      final spec = SduiSpec({
        'text': 'Download◆Loading◆Saved◆Failed',
      });
      final t = docDownloadTexts(spec);
      expect(t.label, 'Download');
      expect(t.progress, 'Loading');
      expect(t.success, 'Saved');
      expect(t.failure, 'Failed');
    });

    // RED if: index guard breaks (slot 0 returned but slots 1-3 not defaulted)
    test('single value uses slot 0 only, rest default', () {
      final spec = SduiSpec({'text': 'Unduh PDF'});
      final t = docDownloadTexts(spec);
      expect(t.label, 'Unduh PDF');
      expect(t.progress, 'Mengunduh…');
      expect(t.success, 'Tersimpan');
      expect(t.failure, 'Gagal mengunduh');
    });

    // RED if: partial diamond split breaks mid-list defaults
    test('2 slots provided, remaining 2 default', () {
      final spec = SduiSpec({
        'text': 'Save◆Saving',
      });
      final t = docDownloadTexts(spec);
      expect(t.label, 'Save');
      expect(t.progress, 'Saving');
      expect(t.success, 'Tersimpan');
      expect(t.failure, 'Gagal mengunduh');
    });

    // W1 — RED if: the blank-slot guard is removed (spec.text alone returns '').
    // A present-but-blank ◆ slot must fall back to the default (decision D4),
    // NOT show a blank label. SduiSpec.text is a length guard only.
    test('blank middle slot falls back to default', () {
      final t = docDownloadTexts(SduiSpec({'text': 'Unduh PDF◆◆Tersimpan◆Gagal'}));
      expect(t.label, 'Unduh PDF'); // slot 0 present
      expect(t.progress, 'Mengunduh…'); // slot 1 BLANK → default (the W1 guard)
      expect(t.success, 'Tersimpan'); // slot 2 present
      expect(t.failure, 'Gagal'); // slot 3 present (its literal value, not default)
    });
  });

  group('docDownloadEffectiveName', () {
    // RED if: config preference is removed (function stops using configResolved)
    test('resolved config wins over URL fallback', () {
      expect(
        docDownloadEffectiveName('Slip Gaji Juli 2026.pdf', 'abc123.pdf'),
        'Slip Gaji Juli 2026.pdf',
      );
    });

    // RED if: unresolved-token check is removed (contains '{' not checked)
    test('unresolved token in config falls back to URL', () {
      expect(
        docDownloadEffectiveName('Slip {prdL}.pdf', 'abc123.pdf'),
        'abc123.pdf',
      );
    });

    // RED if: empty config check is removed
    test('empty config falls back to URL', () {
      expect(
        docDownloadEffectiveName('', 'document.pdf'),
        'document.pdf',
      );
    });

    // RED if: double fallback 'document.pdf' is removed
    test('both empty falls back to document.pdf', () {
      expect(
        docDownloadEffectiveName('', ''),
        'document.pdf',
      );
    });

    // RED if: function incorrectly rejects config without file extension
    test('config without extension still wins', () {
      expect(
        docDownloadEffectiveName('Slip Gaji', 'fallback.pdf'),
        'Slip Gaji',
      );
    });
  });

  group('end-to-end config read', () {
    // RED if: SduiSpec stops parsing the DOC_DOWNLOAD component shape, OR
    // any extracted decision function changes behavior.
    test('full DOC_DOWNLOAD component flows through decision functions', () {
      final spec = SduiSpec({
        'type': 'DOC_DOWNLOAD',
        'url': 'https://example.com/slip.pdf',
        'fileName': 'Slip Gaji Juli 2026.pdf',
        'mode': 'save',
        'icon': 'download',
        'text': 'Unduh PDF◆Mengunduh…◆Berhasil◆Gagal',
      });

      final t = docDownloadTexts(spec);
      expect(t.label, 'Unduh PDF');
      expect(t.progress, 'Mengunduh…');
      expect(t.success, 'Berhasil');
      expect(t.failure, 'Gagal');

      final fileName = spec.str('fileName');
      expect(
        docDownloadEffectiveName(fileName, 'fallback.pdf'),
        'Slip Gaji Juli 2026.pdf',
      );

      // mode is parsed but inert — just verify SduiSpec reads it
      expect(spec.str('mode', 'save'), 'save');
      expect(spec.str('icon'), 'download');
    });
  });
}
