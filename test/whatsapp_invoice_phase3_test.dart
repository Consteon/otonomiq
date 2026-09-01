// test/whatsapp_invoice_phase3_test.dart
//
// whatsapp-invoice-phase3 -- spec (4) sections 6b-2.2 no.3a / no.5, plus the
// phase-2 code-review Warning W1.
//
// W-1  TaskItemBuilder.seedPriceFor      -- order mode reads priceSourceField
//                                          first, falls back to itemPriceField
// W-2  AdminCreateTaskSupport.assembleTaskDoc -- writes `ts`
// W-4  renderWhatsAppTemplate            -- the <IFSET> pass runs BEFORE <LOOP>
//
// All three targets are pure statics / pure top-level functions: no Firebase,
// no GetX, no pump. That is why there is no setUpAll here, matching
// test/task_item_builder_test.dart and test/whatsapp_send_test.dart.
//
// What a green run does NOT prove: the live sheet config
// (`priceSourceField`/`priceField` on the TASK_ITEM_BUILDER row), the Firestore
// write itself, or the wa.me launch. Those stay device + sheet work -- see the
// plan's Verification section.
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/task_item_builder.dart';
import 'package:otonomiq/widget/whatsapp_send.dart';

void main() {
  // ── W-1: seedPriceFor -- order mode price source ──────────────────────
  //
  // Live catalog carries `hrg` (walkin and supplier both read it, and the CF
  // prices the real invoice from item.hrg). Order mode was reading `harga` and
  // getting 0, which is why TASK-2026-000561 shipped every line at hg: 0.
  //
  // The FALLBACK is deliberate, not belt-and-braces: _itemPriceField's own doc
  // comment claims `harga` is a live schema, and a hard swap would silently
  // zero out any tenant for whom that is true.
  group('W-1 seedPriceFor -- order mode', () {
    int seed(String mode, String addTx, Map<String, dynamic> doc) =>
        TaskItemBuilder.seedPriceFor(
          mode: mode,
          addTx: addTx,
          itemDoc: doc,
          itemPriceField: 'harga',
          priceSourceField: 'hrg',
        );

    const Map<String, dynamic> hrgOnly = <String, dynamic>{'hrg': 18000};
    const Map<String, dynamic> hargaOnly = <String, dynamic>{'harga': 20000};
    const Map<String, dynamic> both = <String, dynamic>{
      'hrg': 18000,
      'harga': 20000,
    };

    // -- order + deliver ------------------------------------------------
    test('order+deliver: only hrg set -> hrg (THE BUG THIS ROUND FIXES)', () {
      expect(seed('order', 'deliver', hrgOnly), 18000);
    });

    test('order+deliver: only harga set -> harga (fallback fires)', () {
      expect(seed('order', 'deliver', hargaOnly), 20000);
    });

    test('order+deliver: BOTH set -> hrg wins', () {
      expect(seed('order', 'deliver', both), 18000);
    });

    // -- order + sale (a consumable deliver becomes addTx == 'sale') -----
    test('order+sale: only hrg set -> hrg', () {
      expect(seed('order', 'sale', hrgOnly), 18000);
    });

    test('order+sale: only harga set -> harga (fallback fires)', () {
      expect(seed('order', 'sale', hargaOnly), 20000);
    });

    test('order+sale: BOTH set -> hrg wins', () {
      expect(seed('order', 'sale', both), 18000);
    });

    // -- zero handling --------------------------------------------------
    test('order+deliver: hrg 0 AND harga 0 -> 0, a free item stays free', () {
      // The fallback must not turn a genuinely free item into an error or a
      // phantom price. Both zero -> 0, no throw.
      expect(
        seed('order', 'deliver', <String, dynamic>{'hrg': 0, 'harga': 0}),
        0,
      );
    });

    test('order+sale: hrg 0 AND harga 0 -> 0', () {
      expect(
        seed('order', 'sale', <String, dynamic>{'hrg': 0, 'harga': 0}),
        0,
      );
    });

    test('order+deliver: neither field present -> 0', () {
      expect(seed('order', 'deliver', <String, dynamic>{'ii': 'X'}), 0);
    });

    test(
        'CEILING: hrg 0 with a non-zero harga falls back to harga -- the '
        'fallback cannot tell "free" from "absent"', () {
      // Documented and accepted (plan section 3.1). coerceNum maps both a
      // missing key and a literal 0 to 0, so this is not distinguishable
      // without a second config flag nobody asked for. Pinned so a future
      // reader knows it is deliberate.
      expect(
        seed('order', 'deliver', <String, dynamic>{'hrg': 0, 'harga': 20000}),
        20000,
      );
    });

    // -- Convention #7: Firestore is dynamic ----------------------------
    test('order+deliver: hrg as a String from a sheet is coerced', () {
      expect(seed('order', 'deliver', <String, dynamic>{'hrg': '18000'}), 18000);
    });

    test('order+deliver: hrg as a double truncates to int', () {
      expect(seed('order', 'deliver', <String, dynamic>{'hrg': 18000.9}), 18000);
    });

    // -- order: still-unpriced tx types ---------------------------------
    test('order+purchase -> 0 even with both price fields set', () {
      expect(seed('order', 'purchase', both), 0);
    });

    test('order+refill -> 0 even with both price fields set', () {
      expect(seed('order', 'refill', both), 0);
    });
  });

  // ── W-1: the modes that must NOT move ────────────────────────────────
  //
  // Every one of these is byte-identical before and after the change. They are
  // the regression wall: the arm was inserted between the `supplier` arm and
  // the `sale` arm precisely so these keep their old routing.
  group('W-1 seedPriceFor -- walkin / supplier / seed unchanged', () {
    int seed(String mode, String addTx, Map<String, dynamic> doc) =>
        TaskItemBuilder.seedPriceFor(
          mode: mode,
          addTx: addTx,
          itemDoc: doc,
          itemPriceField: 'harga',
          priceSourceField: 'hrg',
        );

    const Map<String, dynamic> both = <String, dynamic>{
      'hrg': 18000,
      'harga': 20000,
    };

    test('walkin+sale -> hrg (priceSourceField), NOT the order arm', () {
      expect(seed('walkin', 'sale', both), 18000);
    });

    test('walkin+sale with only harga -> 0, walkin never reads harga', () {
      expect(seed('walkin', 'sale', <String, dynamic>{'harga': 20000}), 0);
    });

    test('walkin+deliver -> 0 (walkin never gets an order price)', () {
      expect(seed('walkin', 'deliver', both), 0);
    });

    test('supplier+buy -> hrg', () {
      expect(seed('supplier', 'buy', both), 18000);
    });

    test('supplier+deliver -> hrg, the supplier arm still wins FIRST', () {
      // Kills the mutation "insert the order arm above the supplier arm".
      expect(seed('supplier', 'deliver', both), 18000);
    });

    test('supplier+sale -> hrg, supplier beats the sale arm', () {
      expect(seed('supplier', 'sale', both), 18000);
    });

    test('supplier+deliver with hrg 0 and a non-zero harga -> 0, supplier '
        'never falls back to itemPriceField', () {
      // The order arm's fallback is order-only. Pins that it was NOT copied
      // onto the supplier arm.
      //
      // NOTE for a future mutation run: this fixture does NOT kill the
      // mutation "move the order arm above the supplier arm" (plan §6.4 M4).
      // That mutant was RUN and proved EQUIVALENT -- identical output on a
      // 504-combination grid (6 modes x 7 txs x 12 docs) -- because the moved
      // arm's own guard is `mode == 'order'`, which no supplier input can
      // satisfy. The two arms are mutually exclusive, so their relative order
      // is unobservable. Nothing to add here; the equivalence is a property of
      // the guards, not a gap in the fixtures.
      expect(
        seed('supplier', 'deliver', <String, dynamic>{'hrg': 0, 'harga': 20000}),
        0,
      );
    });

    test('seed mode + deliver -> 0', () {
      expect(seed('seed', 'deliver', both), 0);
    });

    test('seed mode + sale -> harga (the generic sale arm, unchanged)', () {
      expect(seed('seed', 'sale', both), 20000);
    });
  });

  // ── W-2: assembleTaskDoc writes ts ───────────────────────────────────
  group('W-2 assembleTaskDoc ts', () {
    Map<String, dynamic> doc({int t = 1782286245000}) =>
        AdminCreateTaskSupport.assembleTaskDoc(
          tnm: 'TASK-2026-000561',
          kl: 'C1',
          kn: 'Toko Maju',
          al: 'Jl. Sudirman 54',
          vv: 'VEH-123',
          gl: 'WH-001',
          cv: '12345',
          cn: 'Admin A',
          tdt: 1782244800000,
          t: t,
          itArray: const <Map<String, dynamic>>[],
          tableVid: '20342033315492',
        );

    test('ts is present', () {
      expect(doc().containsKey('ts'), isTrue);
    });

    test('ts is a String', () {
      expect(doc()['ts'], isA<String>());
    });

    test('ts equals formatWibTimestamp(t) -- cannot disagree with t', () {
      // Not self-mirroring: it asserts the RELATIONSHIP the design promises
      // (derived from the same t that is written), which is exactly the
      // property a `required String ts` parameter would have lost.
      final Map<String, dynamic> d = doc();
      expect(
        d['ts'],
        AdminCreateTaskSupport.formatWibTimestamp(d['t'] as int),
      );
    });

    test('ts is the nota format: yyyy-MM-dd HH:mm in WIB', () {
      // Arithmetic, straight off formatWibTimestamp's own body -- re-derive
      // it rather than trusting this comment:
      //   1782286245000 + 25200000 (wibOffsetMs) = 1782311445000 ms
      //   1782311445000 ms formatted as UTC      = 2026-06-24 14:30:45
      //   "yyyy-MM-dd HH:mm"                     = "2026-06-24 14:30"
      // (1782286245000 on its own is 07:30:45 UTC; WIB is UTC+7.)
      //
      // If this fails, the bug is in Task 5's wiring or in the fixture epoch.
      // Do NOT "fix" formatWibTimestamp -- nota_create_submit.dart shares that
      // formatter and it is out of scope this round.
      expect(doc()['ts'], '2026-06-24 14:30');
    });

    test('ts is ALWAYS present -- t 0 still yields a non-empty string', () {
      // Mirrors the tot / la / lo rule on this doc, NOT the omit-when-empty
      // idiom reserved for vv / ln / tdt.
      final Map<String, dynamic> d = doc(t: 0);
      expect(d.containsKey('ts'), isTrue);
      expect(d['ts'], '1970-01-01 07:00');
    });

    test('t itself is untouched', () {
      expect(doc()['t'], 1782286245000);
    });
  });

  // ── W-4: <IFSET> pass ordering ───────────────────────────────────────
  //
  // Carry-over Warning W1 from the phase-2 code review. The <IFSET> pass used
  // to run AFTER the <LOOP> pass, and the <LOOP> pass substitutes {{item.*}}
  // VALUES into the result string -- so a catalog item name containing a
  // literal <IFSET ...>...</IFSET> was EXECUTED as control flow and could
  // delete itself from the customer's WhatsApp line, silently.
  //
  // After the move, injected tags leak VERBATIM into the editable preview
  // sheet, where the admin can see them. Visible garbage beats silent loss.
  //
  // THIS GROUP IS THE ONE THAT PINS THE PASS ORDER. Injection is the only
  // observable difference between the three candidate positions, so these
  // three tests are what kill BOTH reorderings -- moving the pass back below
  // <LOOP> (its pre-fix position) and moving it below the {{field}} pass. The
  // render-output group further down stays green under all three orders and
  // pins output, not ordering.
  group('W-4 IFSET pass runs before LOOP -- item data is never control flow',
      () {
    const String loopTpl = r"A<LOOP source='li'>{{item.nm}}</LOOP>B";

    test('item name carrying an IFSET tag survives VERBATIM (tot 0)', () {
      // BEFORE the move this returned 'AB' -- the item name deleted itself.
      expect(
        renderWhatsAppTemplate(loopTpl, <String, dynamic>{
          'li': <Map<String, dynamic>>[
            <String, dynamic>{'nm': r"<IFSET source='tot'>GONE</IFSET>"},
          ],
          'tot': 0,
        }),
        r"A<IFSET source='tot'>GONE</IFSET>B",
      );
    });

    test('same item name with tot SET also survives verbatim', () {
      // BEFORE the move this returned 'AKEPTB'. Both cases together prove the
      // old behaviour was EXECUTION, not stripping.
      expect(
        renderWhatsAppTemplate(loopTpl, <String, dynamic>{
          'li': <Map<String, dynamic>>[
            <String, dynamic>{'nm': r"<IFSET source='tot'>KEPT</IFSET>"},
          ],
          'tot': 7,
        }),
        r"A<IFSET source='tot'>KEPT</IFSET>B",
      );
    });

    test('top-level {{field}} data was already immune and stays immune', () {
      expect(
        renderWhatsAppTemplate('A {{note}} B', <String, dynamic>{
          'note': r"<IFSET source='tot'>LEAK</IFSET>",
          'tot': 0,
        }),
        r"A <IFSET source='tot'>LEAK</IFSET> B",
      );
    });
  });

  // ── W-4: render output regression wall ───────────────────────────────
  //
  // These pin the RENDERED OUTPUT of <IFSET>/<LOOP>/{{field}} across the move,
  // not the pass order. Every one of them is green under all three candidate
  // orders (before <LOOP>, between <LOOP> and {{field}}, after {{field}}) --
  // measured, so do not read them as ordering evidence. Substituting into a
  // body that is then deleted wholesale is unobservable. The ordering is
  // pinned by the injection group above; these are the wall that catches a
  // change breaking the <LOOP> or {{field}} pass itself.
  group('W-4 render output regression wall', () {
    const String totalBlock =
        r"<IFSET source='tot'>--------------------\n*Perkiraan total: {{tot|idr}}*\n</IFSET>";

    test('KEPT body still gets its {{tot|idr}} substituted', () {
      // Output regression only -- green under every pass order (see the group
      // comment). What it catches is the {{field}} pass or _formatIdrWa
      // breaking, not <IFSET> moving.
      expect(
        renderWhatsAppTemplate(totalBlock, <String, dynamic>{'tot': 150000}),
        '--------------------\n*Perkiraan total: 150.000*\n',
      );
    });

    test('DROPPED body takes its separator with it (tot 0)', () {
      expect(
        renderWhatsAppTemplate(totalBlock, <String, dynamic>{'tot': 0}),
        '',
      );
    });

    test('LOOP output survives while the total block drops', () {
      expect(
        renderWhatsAppTemplate(
          r"<LOOP source='li'>- {{item.in}}\n</LOOP><IFSET source='tot'>-----\n*Total: {{tot|idr}}*</IFSET>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'Galon Kosong'},
            ],
            'tot': 0,
          },
        ),
        '- Galon Kosong\n',
      );
    });

    test('LOOP and a KEPT IFSET render together, in order', () {
      expect(
        renderWhatsAppTemplate(
          r"Order:\n<LOOP source='li'>- {{item.in}} x{{item.pd}} @ {{item.hg|idr}}\n</LOOP><IFSET source='tot'>-----\n*Total: {{tot|idr}}*</IFSET>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'Galon', 'pd': 2, 'hg': 20000},
              <String, dynamic>{'in': 'Air', 'pd': 1, 'hg': 5000},
            ],
            'tot': 45000,
          },
        ),
        'Order:\n- Galon x2 @ 20.000\n- Air x1 @ 5.000\n-----\n*Total: 45.000*',
      );
    });

    test('IFSET inside a LOOP body: output unchanged by the move (tot 0)', () {
      // The reviewer's "breaks nesting differently" concern, pinned. Both pass
      // orders produce this same string; verified by running both.
      expect(
        renderWhatsAppTemplate(
          r"<LOOP source='li'>- {{item.in}}<IFSET source='tot'>!</IFSET>\n</LOOP>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'A'},
              <String, dynamic>{'in': 'B'},
            ],
            'tot': 0,
          },
        ),
        '- A\n- B\n',
      );
    });

    test('IFSET inside a LOOP body: output unchanged by the move (tot 9)', () {
      expect(
        renderWhatsAppTemplate(
          r"<LOOP source='li'>- {{item.in}}<IFSET source='tot'>!</IFSET>\n</LOOP>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'A'},
              <String, dynamic>{'in': 'B'},
            ],
            'tot': 9,
          },
        ),
        '- A!\n- B!\n',
      );
    });

    test('LOOP inside an IFSET body still expands when the body is kept', () {
      expect(
        renderWhatsAppTemplate(
          r"<IFSET source='tot'><LOOP source='li'>{{item.in}} </LOOP>total {{tot|idr}}</IFSET>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'A'},
              <String, dynamic>{'in': 'B'},
            ],
            'tot': 9000,
          },
        ),
        'A B total 9.000',
      );
    });

    test('LOOP inside a DROPPED IFSET body emits nothing', () {
      expect(
        renderWhatsAppTemplate(
          r"<IFSET source='tot'><LOOP source='li'>{{item.in}} </LOOP>total {{tot|idr}}</IFSET>",
          <String, dynamic>{
            'li': <Map<String, dynamic>>[
              <String, dynamic>{'in': 'A'},
              <String, dynamic>{'in': 'B'},
            ],
            'tot': 0,
          },
        ),
        '',
      );
    });
  });
}
