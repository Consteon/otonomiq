import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_create_task_support.dart';

/// Pure data-layer tests for the task_create_success widget's data reading.
/// The actual widget rendering requires the full SDUI global setup
/// (transactionStore, linkElement, routeStack, etc.) so we test only the
/// data pipeline that the widget reads from.
void main() {
  setUp(() {
    AdminCreateTaskSupport.clearAllDrafts();
    AdminCreateTaskSupport.lastCreated.clear();
  });

  // ── getLastCreated read ──────────────────────────────────────────────

  group('success screen data read', () {
    test('getLastCreated returns null when no task created', () {
      expect(AdminCreateTaskSupport.getLastCreated('admin_create_task'),
          isNull);
    });

    test('getLastCreated returns null for unknown wizard key', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T', kn: 'K', vn: 'V', totalDrop: 1, totalPickup: 1);
      expect(AdminCreateTaskSupport.getLastCreated('wiz_unknown'), isNull);
    });

    test('reads all stashed fields correctly', () {
      AdminCreateTaskSupport.setLastCreated('admin_create_task',
          tnm: 'TASK-ABC-20260630-120000',
          kn: 'Toko Maju Jaya',
          vn: 'B 1234 XY',
          totalDrop: 15,
          totalPickup: 8);
      final m = AdminCreateTaskSupport.getLastCreated('admin_create_task')!;
      expect(m['tnm'], 'TASK-ABC-20260630-120000');
      expect(m['kn'], 'Toko Maju Jaya');
      expect(m['vn'], 'B 1234 XY');
      expect(m['totalDrop'], 15);
      expect(m['totalPickup'], 8);
    });

    test('stash persists after clearDraft (draft cleared on submit)', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T1', kn: 'K', vn: 'V', totalDrop: 5, totalPickup: 3);
      AdminCreateTaskSupport.clearDraft('wiz1');
      final m = AdminCreateTaskSupport.getLastCreated('wiz1');
      expect(m, isNotNull);
      expect(m!['tnm'], 'T1');
    });

    test('stash persists after clearAllDrafts (buildPage clear)', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T1', kn: 'K', vn: 'V', totalDrop: 5, totalPickup: 3);
      AdminCreateTaskSupport.clearAllDrafts();
      final m = AdminCreateTaskSupport.getLastCreated('wiz1');
      expect(m, isNotNull);
      expect(m!['tnm'], 'T1');
    });

    test('type safety: totalDrop and totalPickup are int', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T', kn: 'K', vn: 'V', totalDrop: 10, totalPickup: 5);
      final m = AdminCreateTaskSupport.getLastCreated('wiz1')!;
      expect(m['totalDrop'], isA<int>());
      expect(m['totalPickup'], isA<int>());
    });

    test('zero totals are valid', () {
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'T', kn: 'K', vn: 'V', totalDrop: 0, totalPickup: 0);
      final m = AdminCreateTaskSupport.getLastCreated('wiz1')!;
      expect(m['totalDrop'], 0);
      expect(m['totalPickup'], 0);
    });
  });

  // ── Submit-to-success data flow ──────────────────────────────────────

  group('submit to success flow', () {
    test('stash computed from draft mirrors computeTotals', () {
      // Simulate what task_create_submit does:
      // 1. Build a draft
      final items = [
        DraftItem(ii: 'a', itemName: 'A', tx: 'deliver', pd: 5, pp: 3),
        DraftItem(ii: 'b', itemName: 'B', tx: 'deliver', pd: 2, pp: 4),
        DraftItem(ii: 'c', itemName: 'C', tx: 'sale', ps: 10),
      ];
      // 2. Compute totals
      final totals = AdminCreateTaskSupport.computeTotals(items);
      // 3. Stash
      AdminCreateTaskSupport.setLastCreated('wiz1',
          tnm: 'TASK-X-20260630-100000',
          kn: 'Toko Test',
          vn: 'B 9999 ZZ',
          totalDrop: totals.totalDrop,
          totalPickup: totals.totalPickup);
      // 4. Clear draft (as submit does)
      AdminCreateTaskSupport.clearDraft('wiz1');

      // 5. Success screen reads stash
      final m = AdminCreateTaskSupport.getLastCreated('wiz1')!;
      expect(m['totalDrop'], 7);   // 5+2
      expect(m['totalPickup'], 7); // 3+4
      expect(m['kn'], 'Toko Test');
      expect(m['vn'], 'B 9999 ZZ');
    });
  });
}
