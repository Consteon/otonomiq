import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/notice_bar.dart';
import 'package:otonomiq/widget/panel_card_support.dart';

void main() {
  // ── Inline emphasis parser ──────────────────────────────────────────────

  group('parseInlineEmphasis', () {
    const TextStyle base = TextStyle(fontSize: 14, color: Color(0xFFD97706));

    test('empty string returns empty list', () {
      final spans = parseInlineEmphasis('', base);
      expect(spans, isEmpty);
    });

    test('no markers returns single literal TextSpan', () {
      final spans = parseInlineEmphasis('hello world', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'hello world');
      expect((spans[0] as TextSpan).style, base);
    });

    test('only bold', () {
      final spans = parseInlineEmphasis('**all bold**', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'all bold');
      expect((spans[0] as TextSpan).style!.fontWeight, FontWeight.w700);
    });

    test('only italic', () {
      final spans = parseInlineEmphasis('*all italic*', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'all italic');
      expect((spans[0] as TextSpan).style!.fontStyle, FontStyle.italic);
    });

    test('multiple emphases', () {
      final spans = parseInlineEmphasis('**a** then *b*', base);
      // bold "a" + literal " then " + italic "b"
      expect(spans.length, 3);
      expect((spans[0] as TextSpan).text, 'a');
      expect((spans[0] as TextSpan).style!.fontWeight, FontWeight.w700);
      expect((spans[1] as TextSpan).text, ' then ');
      expect((spans[1] as TextSpan).style, base);
      expect((spans[2] as TextSpan).text, 'b');
      expect((spans[2] as TextSpan).style!.fontStyle, FontStyle.italic);
    });

    test('adjacent emphases', () {
      final spans = parseInlineEmphasis('**a***b*', base);
      expect(spans.length, 2);
      expect((spans[0] as TextSpan).text, 'a');
      expect((spans[0] as TextSpan).style!.fontWeight, FontWeight.w700);
      expect((spans[1] as TextSpan).text, 'b');
      expect((spans[1] as TextSpan).style!.fontStyle, FontStyle.italic);
    });

    test('unbalanced ** renders literally', () {
      final spans = parseInlineEmphasis('**broken', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, '**broken');
      expect((spans[0] as TextSpan).style, base);
    });

    test('marker at start', () {
      final spans = parseInlineEmphasis('**bold** rest', base);
      expect(spans.length, 2);
      expect((spans[0] as TextSpan).text, 'bold');
      expect((spans[0] as TextSpan).style!.fontWeight, FontWeight.w700);
      expect((spans[1] as TextSpan).text, ' rest');
    });

    test('marker at end', () {
      final spans = parseInlineEmphasis('rest **bold**', base);
      expect(spans.length, 2);
      expect((spans[0] as TextSpan).text, 'rest ');
      expect((spans[1] as TextSpan).text, 'bold');
      expect((spans[1] as TextSpan).style!.fontWeight, FontWeight.w700);
    });

    test('lone asterisk not a marker', () {
      final spans = parseInlineEmphasis('a * b', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'a * b');
      expect((spans[0] as TextSpan).style, base);
    });

    test('whole string emphasized bold', () {
      final spans = parseInlineEmphasis('**everything**', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'everything');
      expect((spans[0] as TextSpan).style!.fontWeight, FontWeight.w700);
    });

    test('whole string emphasized italic', () {
      final spans = parseInlineEmphasis('*everything*', base);
      expect(spans.length, 1);
      expect((spans[0] as TextSpan).text, 'everything');
      expect((spans[0] as TextSpan).style!.fontStyle, FontStyle.italic);
    });
  });

  // ── statusColor / statusBgColor extension ───────────────────────────────

  group('statusColor extensions', () {
    test('info returns blue', () {
      expect(statusColor('info'), const Color(0xFF2563EB));
    });

    test('ok returns green (explicit case)', () {
      expect(statusColor('ok'), const Color(0xFF16A34A));
    });

    test('REGRESSION: unknown token still returns green', () {
      expect(statusColor('{ws}'), const Color(0xFF16A34A));
      expect(statusColor(''), const Color(0xFF16A34A));
      expect(statusColor('gibberish'), const Color(0xFF16A34A));
    });

    test('danger and warn unchanged', () {
      expect(statusColor('danger'), const Color(0xFFDC2626));
      expect(statusColor('warn'), const Color(0xFFD97706));
    });
  });

  group('statusBgColor extensions', () {
    test('info returns light blue', () {
      expect(statusBgColor('info'), const Color(0xFFDBEAFE));
    });

    test('ok returns light green (explicit case)', () {
      expect(statusBgColor('ok'), const Color(0xFFDCFCE7));
    });

    test('REGRESSION: unknown token still returns light green', () {
      expect(statusBgColor('{ws}'), const Color(0xFFDCFCE7));
      expect(statusBgColor(''), const Color(0xFFDCFCE7));
      expect(statusBgColor('gibberish'), const Color(0xFFDCFCE7));
    });

    test('danger and warn unchanged', () {
      expect(statusBgColor('danger'), const Color(0xFFFEE2E2));
      expect(statusBgColor('warn'), const Color(0xFFFEF3C7));
    });
  });

  // ── panelIcon extensions ────────────────────────────────────────────────

  group('panelIcon extensions', () {
    test('info maps to info_outline_rounded', () {
      expect(panelIcon('info'), Icons.info_outline_rounded);
    });

    test('alert maps to warning_amber_rounded', () {
      expect(panelIcon('alert'), Icons.warning_amber_rounded);
    });

    test('existing icons unchanged', () {
      expect(panelIcon('users'), Icons.people_alt_rounded);
      expect(panelIcon('clipboard-check'), Icons.fact_check_rounded);
      expect(panelIcon('map-pin'), Icons.location_on_rounded);
      expect(panelIcon('clock'), Icons.schedule_rounded);
    });

    test('unknown still falls back', () {
      expect(panelIcon('nope'), Icons.dashboard_rounded);
    });
  });

  // ── Widget render tests ─────────────────────────────────────────────────

  group('NoticeBar widget', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    // Helper: find the inner decorated Container by its stable ValueKey.
    // The INNER Container in notice_bar.dart carries
    // key: const ValueKey('noticeBarBox') and holds the BoxDecoration.
    Finder noticeBarBox() => find.byKey(const ValueKey('noticeBarBox'));

    // Helper: scope a finder to descendants of the NoticeBar widget only,
    // avoiding false matches against Material/Scaffold chrome.
    Finder withinNoticeBar(Finder matching) =>
        find.descendant(of: find.byType(NoticeBar), matching: matching);

    testWidgets('danger variant renders danger bg color',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {'type': 'noticeBar', 'variant': 'danger', 'text': 'Error!'},
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      final container = tester.widget<Container>(noticeBarBox());
      final BoxDecoration deco = container.decoration as BoxDecoration;
      expect(deco.color, const Color(0xFFFEE2E2));
    });

    testWidgets('warn variant renders warn bg color',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {'type': 'noticeBar', 'variant': 'warn', 'text': 'Watch out'},
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      final container = tester.widget<Container>(noticeBarBox());
      final BoxDecoration deco = container.decoration as BoxDecoration;
      expect(deco.color, const Color(0xFFFEF3C7));
    });

    testWidgets('info variant renders info bg color',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {'type': 'noticeBar', 'variant': 'info', 'text': 'FYI'},
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      final container = tester.widget<Container>(noticeBarBox());
      final BoxDecoration deco = container.decoration as BoxDecoration;
      expect(deco.color, const Color(0xFFDBEAFE));
    });

    testWidgets('ok variant renders ok bg color',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {'type': 'noticeBar', 'variant': 'ok', 'text': 'All good'},
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      final container = tester.widget<Container>(noticeBarBox());
      final BoxDecoration deco = container.decoration as BoxDecoration;
      expect(deco.color, const Color(0xFFDCFCE7));
    });

    testWidgets('unknown variant defaults to ok/green',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'banana',
          'text': 'Unknown'
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      final container = tester.widget<Container>(noticeBarBox());
      final BoxDecoration deco = container.decoration as BoxDecoration;
      expect(deco.color, const Color(0xFFDCFCE7));
    });

    testWidgets('text-only (no label, no title) renders body, no left bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {'type': 'noticeBar', 'variant': 'warn', 'text': 'Just body'},
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      expect(withinNoticeBar(find.text('Just body')), findsOneWidget);
      // No 4px-wide accent bar container within NoticeBar
      final barFinder = withinNoticeBar(find.byWidgetPredicate((w) =>
          w is Container &&
          w.constraints != null &&
          w.constraints!.maxWidth == 4.0));
      expect(barFinder, findsNothing);
    });

    testWidgets('label present triggers left accent bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'warn',
          'label': 'URGENT',
          'text': 'Body'
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      expect(withinNoticeBar(find.text('URGENT')), findsOneWidget);
      // Should find the accent bar (4px wide container) within NoticeBar
      final barFinder = withinNoticeBar(find.byWidgetPredicate((w) =>
          w is Container &&
          w.constraints != null &&
          w.constraints!.maxWidth == 4.0));
      expect(barFinder, findsOneWidget);
    });

    testWidgets('title present triggers left accent bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'info',
          'title': 'Heading',
          'text': 'Body'
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      expect(withinNoticeBar(find.text('Heading')), findsOneWidget);
      final barFinder = withinNoticeBar(find.byWidgetPredicate((w) =>
          w is Container &&
          w.constraints != null &&
          w.constraints!.maxWidth == 4.0));
      expect(barFinder, findsOneWidget);
    });

    testWidgets('label + title + text renders all three tiers',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'warn',
          'label': 'WARNING',
          'title': 'Check this',
          'text': 'Details here'
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      expect(withinNoticeBar(find.text('WARNING')), findsOneWidget);
      expect(withinNoticeBar(find.text('Check this')), findsOneWidget);
      // Body uses Text.rich so we check for RichText
      expect(withinNoticeBar(find.textContaining('Details here')),
          findsOneWidget);
    });

    testWidgets('only text renders, missing tiers produce no widgets',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'ok',
          'text': 'All good',
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      // Body present
      expect(withinNoticeBar(find.textContaining('All good')), findsOneWidget);
    });

    testWidgets('icon present renders Icon widget',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'info',
          'icon': 'info',
          'title': 'Note',
          'text': 'Body',
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      expect(withinNoticeBar(find.byIcon(Icons.info_outline_rounded)),
          findsOneWidget);
    });

    testWidgets('icon absent renders no Icon widget',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'warn',
          'text': 'No icon',
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      expect(withinNoticeBar(find.byType(Icon)), findsNothing);
    });

    testWidgets('all fields empty renders SizedBox.shrink',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const NoticeBar(
        component: {
          'type': 'noticeBar',
          'variant': 'warn',
          'text': '',
        },
        scrName: 'testScreen',
        lPad: 0,
        tPad: 0,
        rPad: 0,
        bPad: 0,
      )));
      // NoticeBar itself is in the tree, but its build returns SizedBox.shrink
      // so no Container or Text descendants exist under it.
      expect(find.byType(NoticeBar), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(NoticeBar), matching: find.byType(Container)),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(NoticeBar), matching: find.byType(Text)),
          findsNothing);
    });
  });
}
