import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/global.dart';
import 'package:otonomiq/redux/screen_transaction.dart';
import 'package:otonomiq/redux/screen_transaction_reducers.dart';
import 'package:otonomiq/sdui_spec.dart';
import 'package:otonomiq/states/app_code_controller.dart';
import 'package:otonomiq/widget/doc_viewer.dart';
import 'package:redux_dev_tools/redux_dev_tools.dart';

/// Tests for DOC_VIEWER decision-rule functions extracted from [DocViewer].
///
/// Each test has a one-line comment naming the code change that would turn it
/// RED — per the "structurally-guaranteed assertion certifies nothing" rule.
///
/// What CANNOT be tested here (requires device QA):
/// - PDFView platform-view rendering (native Android/iOS view)
/// - Real HTTP download (createFileOfPdfUrl uses HttpClient)
/// - Firebase Storage getDownloadURL (requires live Firebase)
/// - Navigator.push to OtqPdfViewer fullscreen page
void main() {
  // Binding + appCodeController: once per file (never mutated between tests).
  // appCodeController is a `late` global (global.dart) assigned only in
  // globalInit(), which does NOT run under flutter_test.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    appCodeController = AppCodeController()..applicationTableVid = 99999;
  });

  // Rebuild store before each test for isolation.
  // UpdateScreenTxAction is a shallow-copy + per-key overwrite merge
  // (screen_transaction_reducers.dart:69-78), so prior tests' seeded keys
  // would leak into later tests without this.
  setUp(() {
    transactionStore = DevToolsStore<ScreenTransaction>(
      transactionReducer,
      initialState: ScreenTransaction(initTransactionStore()),
    );
  });

  group('docViewerSourceIsUsable', () {
    // RED if: function body changes to return true for empty strings
    test('empty string is not usable', () {
      expect(docViewerSourceIsUsable(''), false);
    });

    // RED if: function stops checking for unresolved {token} markers
    test('unresolved curly token is not usable', () {
      expect(docViewerSourceIsUsable('{link}'), false);
    });

    // RED if: function stops checking for unresolved {token} markers
    test('partially resolved URL with remaining token is not usable', () {
      expect(docViewerSourceIsUsable('https://example.com/{file}'), false);
    });

    // RED if: function rejects valid resolved URLs
    test('resolved URL is usable', () {
      expect(docViewerSourceIsUsable('https://example.com/doc.pdf'), true);
    });

    // RED if: function rejects valid storage paths (no braces, non-empty)
    test('storage path without braces is usable', () {
      expect(docViewerSourceIsUsable('documents/payslip/2026-08.pdf'), true);
    });
  });

  group('docViewerNeedsStorageResolve', () {
    // RED if: function stops routing sourceType "path" to storage resolve
    test('sourceType path needs storage resolve', () {
      expect(
        docViewerNeedsStorageResolve('path', 'documents/payslip/2026-08.pdf'),
        true,
      );
    });

    // RED if: function stops routing non-http sources to storage resolve
    test('non-http source needs storage resolve regardless of sourceType', () {
      expect(
        docViewerNeedsStorageResolve('url', 'gs://bucket/file.pdf'),
        true,
      );
    });

    // RED if: function incorrectly routes http URLs to storage resolve
    test('http URL with sourceType url does not need storage resolve', () {
      expect(
        docViewerNeedsStorageResolve('url', 'https://example.com/doc.pdf'),
        false,
      );
    });

    // RED if: function stops treating sourceType "path" as storage override
    test('sourceType path overrides http prefix', () {
      expect(
        docViewerNeedsStorageResolve('path', 'https://example.com/doc.pdf'),
        true,
      );
    });
  });

  group('docViewerSwipeHorizontal', () {
    // RED if: function starts treating "vertical" as horizontal
    test('vertical is not horizontal', () {
      expect(docViewerSwipeHorizontal('vertical'), false);
    });

    // RED if: function stops treating "horizontal" as horizontal
    test('horizontal is horizontal', () {
      expect(docViewerSwipeHorizontal('horizontal'), true);
    });

    // RED if: function starts treating empty string as vertical
    test('empty string defaults to horizontal (mirrors OtqPdfViewer)', () {
      expect(docViewerSwipeHorizontal(''), true);
    });
  });

  group('end-to-end config read', () {
    // RED if: SduiSpec stops parsing the DOC_VIEWER component shape correctly,
    // OR any of the three extracted decision functions change behavior.
    test('full DOC_VIEWER component map flows through decision functions', () {
      final spec = SduiSpec({
        'type': 'DOC_VIEWER',
        'source': 'https://example.com/doc.pdf',
        'sourceType': 'url',
        'swipe': 'horizontal',
        'fullscreen': 'false',
        'text': 'Slip Gaji',
        'emptyText': 'Slip belum tersedia',
        'height': 480,
      });

      final source = spec.str('source');
      final sourceType = spec.str('sourceType', 'url').toLowerCase();
      final swipe = spec.str('swipe', 'vertical').toLowerCase();

      expect(docViewerSourceIsUsable(source), true);
      expect(docViewerNeedsStorageResolve(sourceType, source), false);
      expect(docViewerSwipeHorizontal(swipe), true);
    });
  });

  group('pump: token resolution and D2 message', () {
    // These testWidgets pump DocViewer and observe rendered text.
    // Safe by construction: #STORAGE_BUCKET absent -> _resolveStoragePath
    // returns at null guard (doc_viewer.dart:119) before Firebase;
    // _errorMessage non-empty -> build() takes Text branch (doc_viewer.dart:163)
    // -> PDFView never constructed -> no platform view, no HTTP.

    // RED if: _resolveAndLoad stops calling TokenResolver.curly (e.g. uses
    // rawSource directly). Seeded key would NOT resolve -> source stays
    // '{slipPath}' -> unusable -> hits D2 branch -> distinct message rendered
    // instead of emptyText. expect(find.text('Slip belum tersedia')) fails.
    testWidgets('seeded token resolves, hits storage path, shows emptyText',
        (tester) async {
      // DEPENDENCY: relies on #STORAGE_BUCKET being ABSENT from
      // initTransactionStore(). This test reaches _resolveStoragePath, which
      // returns at the null guard instead of hitting real Firebase. If that
      // key is ever seeded in initTransactionStore(), this test would attempt
      // live Storage resolution and this expectation would break.
      // Seed bare key so TokenResolver.curly resolves {slipPath}
      transactionStore.dispatch(UpdateScreenTxAction(ScreenTransaction({
        'slipPath': 'slip/2026-08.pdf',
      })));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocViewer(
              key: const Key('test-dv-a'),
              component: {
                'type': 'DOC_VIEWER',
                'source': '{slipPath}',
                'table': 'x//y',
                'emptyText': 'Slip belum tersedia',
                'height': 200,
              },
              scrName: 'testScreenA',
            ),
          ),
        ),
      );
      await tester.pump();

      // Token resolved -> source usable -> storage path -> #STORAGE_BUCKET
      // null -> _errorMessage = _emptyText -> renders emptyText
      expect(find.text('Slip belum tersedia'), findsOneWidget);
      expect(find.text(docViewerVariantBMessage), findsNothing);
    });

    // RED if: docViewerSourceIsUsable stops detecting unresolved {token}
    // (e.g. contains('{') guard removed). Unresolved source would pass as
    // usable -> storage path -> #STORAGE_BUCKET null -> emptyText rendered
    // instead of distinct message. expect(find.text(docViewerVariantBMessage))
    // fails.
    testWidgets('unseeded token stays literal, D2 distinct message renders',
        (tester) async {
      // Do NOT seed 'noSuchSlip' -> TokenResolver.curly leaves literal
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocViewer(
              key: const Key('test-dv-b'),
              component: {
                'type': 'DOC_VIEWER',
                'source': '{noSuchSlip}',
                'table': 'x//y',
                'emptyText': 'Slip belum tersedia',
                'height': 200,
              },
              scrName: 'testScreenB',
            ),
          ),
        ),
      );
      await tester.pump();

      // Token unresolved -> source unusable -> hasTable true -> D2 branch
      // -> renders docViewerVariantBMessage, NOT emptyText
      expect(find.text(docViewerVariantBMessage), findsOneWidget);
      expect(find.text('Slip belum tersedia'), findsNothing);
    });
  });

  group('docViewerUnusableSourceMessage', () {
    // RED if: function stops returning the distinct constant when hasTable is
    // true (e.g. always returns emptyText).
    test('table set yields distinct message, not emptyText', () {
      final result =
          docViewerUnusableSourceMessage(true, 'Slip belum tersedia');
      expect(result, docViewerVariantBMessage);
      expect(result, isNot('Slip belum tersedia'));
    });

    // RED if: function stops returning emptyText when hasTable is false.
    test('no table returns emptyText unchanged', () {
      final result =
          docViewerUnusableSourceMessage(false, 'Slip belum tersedia');
      expect(result, 'Slip belum tersedia');
    });
  });
}
