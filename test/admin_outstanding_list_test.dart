import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/widget/admin_home_support.dart';

void main() {
  // ── Outstanding empty scenarios ─────────────────────────────────────────
  //
  // When groupOutstanding returns empty, the widget now renders the panel
  // chrome with emptyText instead of SizedBox.shrink(). These tests confirm
  // the empty-trigger conditions.

  group('Outstanding empty scenarios (triggers emptyText path)', () {
    const int now = 1719200000000;

    test('no asset_cache docs -> empty groups', () {
      final groups = groupOutstanding(
        assetCacheDocs: const [],
        stockLocations: const [],
        nowMs: now,
      );
      expect(groups, isEmpty);
    });

    test('all qt <= 0 -> empty groups (hideZero)', () {
      final groups = groupOutstanding(
        assetCacheDocs: [
          {'lv': 'C1', 'lt': 'client', 'ii': 'I1', 'qt': 0, 't': now},
          {'lv': 'C1', 'lt': 'client', 'ii': 'I2', 'qt': -1, 't': now},
        ],
        stockLocations: const [],
        nowMs: now,
      );
      expect(groups, isEmpty);
    });

    test('only non-client docs -> empty groups', () {
      final groups = groupOutstanding(
        assetCacheDocs: [
          {'lv': 'W1', 'lt': 'warehouse', 'ii': 'Gas', 'qt': 5, 't': now},
        ],
        stockLocations: const [],
        nowMs: now,
      );
      expect(groups, isEmpty);
    });

    test('non-empty groups when valid client data exists', () {
      final groups = groupOutstanding(
        assetCacheDocs: [
          {'lv': 'C1', 'lt': 'client', 'ii': 'Gas', 'qt': 3, 't': now - 86400000},
        ],
        stockLocations: [
          {'lv': 'C1', 'lt': 'client', 'ln': 'Toko A'},
        ],
        nowMs: now,
      );
      expect(groups.length, 1);
      expect(groups.first.clientName, 'Toko A');
    });
  });

  // ── emptyText config default ────────────────────────────────────────────
  //
  // Mirrors _parseConfig:
  //   final et = (widget.component['emptyText'] ?? '').toString().trim();
  //   if (et.isNotEmpty) _emptyText = et;
  // with _emptyText initialized to the default.

  group('emptyText config resolution', () {
    const String defaultText =
        'Tidak ada outstanding \u{00B7} semua sudah tertagih';

    String resolveEmptyText(Map<String, dynamic>? component) {
      final String v =
          (component?['emptyText'] ?? '').toString().trim();
      return v.isNotEmpty ? v : defaultText;
    }

    test('absent key -> default', () {
      expect(resolveEmptyText({}), defaultText);
    });

    test('null component -> default', () {
      expect(resolveEmptyText(null), defaultText);
    });

    test('custom emptyText', () {
      expect(
        resolveEmptyText({'emptyText': 'All clear'}),
        'All clear',
      );
    });

    test('empty string -> default', () {
      expect(resolveEmptyText({'emptyText': ''}), defaultText);
    });

    test('whitespace-only -> default', () {
      expect(resolveEmptyText({'emptyText': '   '}), defaultText);
    });
  });
}
