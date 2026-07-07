import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/driver_home_support.dart';

/// admin-create-task write-canon cluster — GROUP A anchors.
///
/// A1: TaskCreateSubmit._onSubmit resolves the origin-warehouse `gl` via
///     resolveWarehouseId(config > #ACTIVE_WAREHOUSE-store > single
///     stock_location lt=='warehouse' -> lv). resolveWarehouseId is the shared
///     O1 helper (driver_home_support.dart); these tests pin the precedence the
///     widget relies on. The widget wiring itself (subscribeToMapCollection +
///     the mapTableContent read) needs Firestore and is verified on-device.
void main() {
  group('resolveWarehouseId precedence (A1 gl resolution)', () {
    final List<Map<String, dynamic>> stock = <Map<String, dynamic>>[
      <String, dynamic>{'lt': 'warehouse', 'lv': 'WH-FALLBACK'},
      <String, dynamic>{'lt': 'client', 'lv': 'CLIENT-1'},
    ];

    test('config originWarehouse wins over store and stock fallback', () {
      expect(
        resolveWarehouseId(
          configResolved: 'WH-CONFIG',
          fromStore: 'WH-STORE',
          stockDocs: stock,
        ),
        'WH-CONFIG',
      );
    });

    test('store (#ACTIVE_WAREHOUSE) wins when config empty', () {
      expect(
        resolveWarehouseId(
          configResolved: '',
          fromStore: 'WH-STORE',
          stockDocs: stock,
        ),
        'WH-STORE',
      );
    });

    test('single lt==warehouse lv is the fallback when config + store empty', () {
      expect(
        resolveWarehouseId(
          configResolved: '',
          fromStore: '',
          stockDocs: stock,
        ),
        'WH-FALLBACK',
      );
    });

    test('unresolved {token} in config is skipped -> falls through to store', () {
      expect(
        resolveWarehouseId(
          configResolved: '{warehouseId}',
          fromStore: 'WH-STORE',
          stockDocs: stock,
        ),
        'WH-STORE',
      );
    });

    test('all empty and no warehouse doc -> empty gl (degrade-safe)', () {
      expect(
        resolveWarehouseId(
          configResolved: '',
          fromStore: '',
          stockDocs: const <Map<String, dynamic>>[],
        ),
        '',
      );
    });
  });

  // ── B1-A: hasNewCustomerIdMarker gate predicate ─────────────────────
  group('hasNewCustomerIdMarker (B1-A gate)', () {
    test('returns true when addToEvent contains {newCustomerId}', () {
      final component = <String, dynamic>{
        'addToEvent':
            '84214220504259//stock_location_u2B58_lt_u25FC_client_u2B58_lv_u25FC_{newCustomerId}',
      };
      expect(hasNewCustomerIdMarker(component), isTrue);
    });

    test('returns false when addToEvent has no marker', () {
      final component = <String, dynamic>{
        'addToEvent':
            '84214220504259//task_u2B58_tst_u25FC_assigned',
      };
      expect(hasNewCustomerIdMarker(component), isFalse);
    });

    test('returns false when addToEvent is absent', () {
      final component = <String, dynamic>{};
      expect(hasNewCustomerIdMarker(component), isFalse);
    });

    test('returns false when addToEvent is null', () {
      final component = <String, dynamic>{'addToEvent': null};
      expect(hasNewCustomerIdMarker(component), isFalse);
    });

    test('returns false when addToEvent is empty string', () {
      final component = <String, dynamic>{'addToEvent': ''};
      expect(hasNewCustomerIdMarker(component), isFalse);
    });

    test('does not false-positive on partial match (newCustomer alone)', () {
      final component = <String, dynamic>{
        'addToEvent': 'newCustomer_u2B58_other',
      };
      expect(hasNewCustomerIdMarker(component), isFalse);
    });
  });
}
