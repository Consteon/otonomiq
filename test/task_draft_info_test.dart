import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';
import 'package:otonomiq/widget/task_item_builder.dart';

/// Pure-function tests for the draft-info rendering data path.
/// The actual widget rendering requires the full SDUI global setup
/// (transactionStore, linkElement, etc.) so we test the data layer
/// that the widget reads from.
void main() {
  setUp(() {
    AdminCreateTaskSupport.clearAllDrafts();
  });

  // ── Customer + vehicle combined lifecycle ─────────────────────────────

  group('draft info data layer', () {
    test('customer and vehicle are independent per wizard key', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Toko A', al: 'Addr A');
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'B 1234 XY');
      AdminCreateTaskSupport.setCustomer('wiz2',
          kl: 'C2', kn: 'Toko B', al: 'Addr B');

      expect(AdminCreateTaskSupport.getCustomer('wiz1')!['kn'], 'Toko A');
      expect(AdminCreateTaskSupport.getVehicle('wiz1')!['vn'], 'B 1234 XY');
      expect(AdminCreateTaskSupport.getCustomer('wiz2')!['kn'], 'Toko B');
      expect(AdminCreateTaskSupport.getVehicle('wiz2'), isNull);
    });

    test('re-pick customer overwrites without affecting vehicle', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Old', al: 'Old Addr');
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'B 1234 XY');
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C2', kn: 'New', al: 'New Addr');

      expect(AdminCreateTaskSupport.getCustomer('wiz1')!['kl'], 'C2');
      expect(AdminCreateTaskSupport.getVehicle('wiz1')!['vv'], 'V1');
    });

    test('re-pick vehicle overwrites without affecting customer', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Name', al: 'Addr');
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'Old Plate');
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V2', vn: 'New Plate');

      expect(AdminCreateTaskSupport.getCustomer('wiz1')!['kl'], 'C1');
      expect(AdminCreateTaskSupport.getVehicle('wiz1')!['vv'], 'V2');
    });

    test('clearDraft atomically clears items + customer + vehicle', () {
      AdminCreateTaskSupport.getDraft('wiz1').add(
        DraftItem(ii: 'x', itemName: 'X', tx: 'deliver'),
      );
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'N', al: 'A');
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'Plate');

      AdminCreateTaskSupport.clearDraft('wiz1');

      expect(AdminCreateTaskSupport.getDraft('wiz1'), isEmpty);
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
    });

    test('empty customer name triggers empty-state', () {
      AdminCreateTaskSupport.setCustomer('wiz1', kl: 'C1', kn: '', al: '');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      // Widget should show empty-state when kn is empty
      expect((c['kn'] ?? '').isEmpty, true);
    });

    test('empty vehicle id triggers empty-state', () {
      AdminCreateTaskSupport.setVehicle('wiz1', vv: '', vn: '');
      final v = AdminCreateTaskSupport.getVehicle('wiz1')!;
      // Widget should show empty-state when vv is empty
      expect((v['vv'] ?? '').isEmpty, true);
    });
  });

  // ── Submit path: draft-first with screenTx fallback ───────────────────

  group('submit data resolution', () {
    test('draft values take precedence when present', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'DRAFT_C1', kn: 'Draft Name', al: 'Draft Addr');
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'DRAFT_V1', vn: 'Draft Plate');

      final dc = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(dc['kl'], 'DRAFT_C1');
      expect(dc['kn'], 'Draft Name');

      final dv = AdminCreateTaskSupport.getVehicle('wiz1')!;
      expect(dv['vv'], 'DRAFT_V1');
    });

    test('null draft falls back gracefully', () {
      // No draft set -- getCustomer/getVehicle return null
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
      expect(AdminCreateTaskSupport.getVehicle('wiz1'), isNull);
      // Submit code should fall back to screenTx (tested at widget level)
    });

    test('draft with empty kl still resolves to empty string', () {
      AdminCreateTaskSupport.setCustomer('wiz1', kl: '', kn: 'Name', al: 'Addr');
      final dc = AdminCreateTaskSupport.getCustomer('wiz1')!;
      // Empty kl means submit should fall back to screenTx
      expect((dc['kl'] ?? '').isEmpty, true);
    });
  });

  // ── Variant data layer: card (default) ────────────────────────────────

  group('variant card data layer', () {
    test('card variant reads customer kn + al + pic from draft', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Toko A', al: 'Jl. Test 1',
          pic: 'Pak Budi \u{00B7} 081234567890');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kn'], 'Toko A');
      expect(c['al'], 'Jl. Test 1');
      expect(c['pic'], 'Pak Budi \u{00B7} 081234567890');
    });

    test('card variant reads vehicle vv + vn unchanged', () {
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'B 1234 XY');
      final v = AdminCreateTaskSupport.getVehicle('wiz1')!;
      expect(v['vv'], 'V1');
      expect(v['vn'], 'B 1234 XY');
    });

    test('card variant empty pic does not add visual noise', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Toko A', al: 'Addr');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      // pic defaults to '' when omitted -- widget should not render a pic line
      expect(c['pic'], '');
    });
  });

  // ── Variant data layer: strip (P2) ────────────────────────────────────

  group('variant strip data layer', () {
    test('strip reads kn + pic from draft customer', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Honda Bintaro', al: 'Jl. Bintaro Utama 23',
          pic: 'Bu Sari \u{00B7} 081298765432');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kn'], 'Honda Bintaro');
      expect(c['pic'], 'Bu Sari \u{00B7} 081298765432');
    });

    test('strip empty state: null customer returns null', () {
      // No customer set -> widget should render SizedBox.shrink()
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
    });

    test('strip empty state: empty kn signals empty', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: '', al: '', pic: '');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      // Widget should render SizedBox.shrink() when kn is empty
      expect((c['kn'] ?? '').isEmpty, true);
    });

    test('strip does not read vehicle (not rendered)', () {
      AdminCreateTaskSupport.setVehicle('wiz1',
          vv: 'V1', vn: 'Plate');
      // Vehicle is set but strip variant never reads it
      final v = AdminCreateTaskSupport.getVehicle('wiz1');
      expect(v, isNotNull); // still exists, just not rendered by strip
    });
  });

  // ── Variant data layer: stripTotals (P3) ──────────────────────────────

  group('variant stripTotals data layer', () {
    test('stripTotals reads kn from customer + computeTotals', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Customer X', al: 'Addr',
          pic: 'Contact');
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'I1', itemName: 'Galon 19L', tx: 'deliver', pd: 10, pp: 5),
        DraftItem(ii: 'I2', itemName: 'Galon 12L', tx: 'deliver', pd: 3, pp: 2),
        DraftItem(ii: 'I3', itemName: 'Amidis', tx: 'sale', ps: 4),
      ]);
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      expect(c['kn'], 'Customer X');

      final totals = AdminCreateTaskSupport.computeTotals(
          AdminCreateTaskSupport.getDraft('wiz1'));
      expect(totals.totalDrop, 13);
      expect(totals.totalPickup, 7);
    });

    test('stripTotals empty draft shows zero totals', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'Customer X', al: 'Addr');
      final totals = AdminCreateTaskSupport.computeTotals(
          AdminCreateTaskSupport.getDraft('wiz1'));
      expect(totals.totalDrop, 0);
      expect(totals.totalPickup, 0);
    });

    test('stripTotals empty state: null customer returns null', () {
      expect(AdminCreateTaskSupport.getCustomer('wiz1'), isNull);
    });
  });

  // ── Letter-avatar logic ───────────────────────────────────────────────

  group('letter avatar', () {
    test('first char of kn uppercased is the avatar', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: 'honda Bintaro', al: 'Addr');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      final String kn = c['kn'] ?? '';
      // Widget derives avatar from kn[0].toUpperCase()
      expect(kn.isNotEmpty ? kn[0].toUpperCase() : '', 'H');
    });

    test('empty kn yields empty avatar', () {
      AdminCreateTaskSupport.setCustomer('wiz1',
          kl: 'C1', kn: '', al: 'Addr');
      final c = AdminCreateTaskSupport.getCustomer('wiz1')!;
      final String kn = c['kn'] ?? '';
      expect(kn.isEmpty, true);
    });
  });

  // ── P4 aggregate pickup breakdown ────────────────────────────────────

  group('P4 aggregate pickup breakdown', () {
    setUp(() {
      AdminCreateTaskSupport.clearAllDrafts();
    });

    test('aggregate exchange/clearing/pickup over deliver items', () {
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'deliver', pd: 2, pp: 4),
      ]);
      final draft = AdminCreateTaskSupport.getDraft('wiz1');

      int totalExchange = 0;
      int totalClearing = 0;
      for (final item in draft) {
        if (item.tx != 'deliver') continue;
        totalExchange += TaskItemBuilder.pickupExchange(item.pd, item.pp);
        totalClearing += TaskItemBuilder.pickupClearing(item.pd, item.pp);
      }
      final totalPickup = totalExchange + totalClearing;

      // Item a: exchange=min(5,3)=3, clearing=max(0,3-5)=0
      // Item b: exchange=min(2,4)=2, clearing=max(0,4-2)=2
      expect(totalExchange, 5); // 3+2
      expect(totalClearing, 2); // 0+2
      expect(totalPickup, 7);   // 3+4 = sum of pp
      expect(totalPickup, totalExchange + totalClearing);
    });

    test('non-deliver items excluded from breakdown', () {
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'sale', ps: 10),
        DraftItem(ii: 'c', itemName: 'C', tx: 'purchase', pb: 7),
        DraftItem(ii: 'd', itemName: 'D', tx: 'refill', pr: 2),
      ]);
      final draft = AdminCreateTaskSupport.getDraft('wiz1');

      int totalPickup = 0;
      for (final item in draft) {
        if (item.tx != 'deliver') continue;
        totalPickup += TaskItemBuilder.pickupExchange(item.pd, item.pp) +
            TaskItemBuilder.pickupClearing(item.pd, item.pp);
      }

      // Only item a contributes: pickup = min(5,3) + max(0,3-5) = 3 + 0 = 3
      expect(totalPickup, 3);
    });

    test('visibility gate: totalPickup <= 0 means no breakdown', () {
      // All deliver items with pp=0
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 0),
        DraftItem(ii: 'b', itemName: 'B', tx: 'deliver', pd: 3, pp: 0),
      ]);
      final draft = AdminCreateTaskSupport.getDraft('wiz1');

      int totalPickup = 0;
      for (final item in draft) {
        if (item.tx != 'deliver') continue;
        totalPickup += TaskItemBuilder.pickupExchange(item.pd, item.pp) +
            TaskItemBuilder.pickupClearing(item.pd, item.pp);
      }

      expect(totalPickup, 0);
      // Widget would NOT render the breakdown box
    });

    test('visibility gate: totalPickup > 0 means breakdown visible', () {
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 1),
      ]);
      final draft = AdminCreateTaskSupport.getDraft('wiz1');

      int totalPickup = 0;
      for (final item in draft) {
        if (item.tx != 'deliver') continue;
        totalPickup += TaskItemBuilder.pickupExchange(item.pd, item.pp) +
            TaskItemBuilder.pickupClearing(item.pd, item.pp);
      }

      expect(totalPickup, 1);
      // Widget WOULD render the breakdown box
    });

    test('empty draft produces totalPickup == 0', () {
      final draft = AdminCreateTaskSupport.getDraft('wiz1');

      int totalPickup = 0;
      for (final item in draft) {
        if (item.tx != 'deliver') continue;
        totalPickup += TaskItemBuilder.pickupExchange(item.pd, item.pp) +
            TaskItemBuilder.pickupClearing(item.pd, item.pp);
      }

      expect(totalPickup, 0);
    });

    test('exchange + clearing == totalPickup (identity)', () {
      AdminCreateTaskSupport.getDraft('wiz1').addAll([
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 10, pp: 7),
        DraftItem(ii: 'b', itemName: 'B', tx: 'deliver', pd: 3, pp: 5),
        DraftItem(ii: 'c', itemName: 'C', tx: 'deliver', pd: 0, pp: 4),
      ]);
      final draft = AdminCreateTaskSupport.getDraft('wiz1');

      int totalExchange = 0;
      int totalClearing = 0;
      int directPickup = 0;
      for (final item in draft) {
        if (item.tx != 'deliver') continue;
        totalExchange += TaskItemBuilder.pickupExchange(item.pd, item.pp);
        totalClearing += TaskItemBuilder.pickupClearing(item.pd, item.pp);
        directPickup += item.pp;
      }

      // Identity: exchange + clearing == pp for each item
      expect(totalExchange + totalClearing, directPickup);
      // a: exch=7, clear=0; b: exch=3, clear=2; c: exch=0, clear=4
      expect(totalExchange, 10); // 7+3+0
      expect(totalClearing, 6);  // 0+2+4
      expect(directPickup, 16);  // 7+5+4
    });
  });
}
