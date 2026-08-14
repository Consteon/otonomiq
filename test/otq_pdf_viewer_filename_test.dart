import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/page/otq_pdf_viewer.dart';
import 'package:otonomiq/sdui_spec.dart';

/// Guards the two ways a PDF_VIEW row reached the network layer with garbage:
/// a URL whose filename could not be sliced (RangeError), and an empty-string
/// config slot that `?? default` let through.
void main() {
  group('pdfFileNameFromUrl', () {
    test('firebase object path (%2F-encoded) keeps only the file', () {
      expect(
        pdfFileNameFromUrl(
          'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/'
          'c%2Fautsorz%2FOtonomiq.pdf?alt=media&token=efcd3c1a',
        ),
        'Otonomiq.pdf',
      );
    });

    test('plain path URL keeps only the file', () {
      expect(
        pdfFileNameFromUrl(
          'https://mozilla.github.io/pdf.js/web/compressed.tracemonkey.pdf',
        ),
        'compressed.tracemonkey.pdf',
      );
    });

    test('URL with no .pdf does not throw (was RangeError)', () {
      expect(pdfFileNameFromUrl('https://example.com/files/slip'), 'slip');
    });

    test('no path segment at all falls back', () {
      expect(pdfFileNameFromUrl('https://example.com'), 'document.pdf');
    });

    test('empty url falls back instead of throwing', () {
      expect(pdfFileNameFromUrl(''), 'document.pdf');
    });
  });

  group('PDF_VIEW config slots', () {
    // The live sheet row ships "path":"" for an unfilled PDF slot; the old
    // `component['path'] ?? defaultPdf` only defaulted on a MISSING key.
    test('blank path falls back to the default pdf', () {
      final spec = SduiSpec({'type': 'PDF_VIEW', 'path': '', 'url': ''});
      expect(spec.str('path', 'FALLBACK_PDF'), 'FALLBACK_PDF');
      expect(spec.str('url', 'FALLBACK_IMG'), 'FALLBACK_IMG');
    });

    test('filled path is used verbatim', () {
      final spec = SduiSpec({'path': 'https://x/y.pdf'});
      expect(spec.str('path', 'FALLBACK_PDF'), 'https://x/y.pdf');
    });

    test('swipe/linkNavigation blanks land on the documented defaults', () {
      final spec = SduiSpec({'swipe': '', 'linkNavigation': ''});
      expect(spec.str('swipe', 'vertical').toLowerCase(), 'vertical');
      expect(spec.str('linkNavigation').toLowerCase() == 'true', false);
    });
  });
}
