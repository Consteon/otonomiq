import '../global.dart';
import '../global2.dart';
import '../states/app_code_controller.dart';
import 'table_repository.dart';

/// Validate a scanned QR value against a Firestore table.
///
/// Builds the collection path via [eventCollectionPath] (table_repository.dart)
/// using [AppCodeController.applicationTableVid], then queries for documents
/// where [searchField] equals [scanValue].
///
/// Because Firestore distinguishes string `'123'` from number `123`, this
/// function queries for the String value first, and if [scanValue] also parses
/// to a [num], runs a second query with the numeric value. Returns `true` if
/// EITHER query finds at least one document.
///
/// [tableRaw] is the raw component `table` value (e.g. `"workforce"` or
/// `"docId//subColl"`). Passed directly to [eventCollectionPath] which handles
/// both the legacy plain-name and new `//` subcollection forms.
///
/// Throws on Firestore errors (offline, permission, invalid path). The caller
/// is expected to catch and treat as NOT-FOUND.
Future<bool> scannerValidateQr(
  String tableRaw,
  String searchField,
  String scanValue, {
  int? tenantVid,
}) async {
  // Resolve the tenant container vid. [tenantVid] (resolved in the widget via
  // getTableVid) lets a caller target a DIFFERENT tenant's container than the
  // current app tenant -- e.g. the VTL workforce subcollection lives under the
  // Consteon master container (getTableVid('con')). Null is backward-compatible:
  // falls back to the current tenant's applicationTableVid.
  final AppCodeController controller = appCodeController;
  final int vid = tenantVid ?? controller.applicationTableVid;
  final String path = eventCollectionPath(tableRaw, vid);
  devPrint(
    'scannerValidateQr path=$path field=$searchField value=$scanValue vid=$vid',
  );
  if (path.isEmpty) return false;

  // Query 1: String match.
  final dynamic snap = await firestoreDb
      .collection(path)
      .where(searchField, isEqualTo: scanValue)
      .limit(1)
      .get();
  if ((snap.docs as List).isNotEmpty) {
    devPrint('scannerValidateQr FOUND (string match)');
    return true;
  }

  // Query 2: Numeric match (if scanValue parses to a num).
  // Firestore stores VID as a number in some tenants; a string isEqualTo
  // query will MISS a numeric field value. Defensive dual-query avoids
  // per-tenant mismatches.
  final num? numValue = num.tryParse(scanValue);
  if (numValue != null) {
    final dynamic snap2 = await firestoreDb
        .collection(path)
        .where(searchField, isEqualTo: numValue)
        .limit(1)
        .get();
    if ((snap2.docs as List).isNotEmpty) {
      devPrint('scannerValidateQr FOUND (num match)');
      return true;
    }
  }

  devPrint('scannerValidateQr NOT FOUND');
  return false;
}

/// Derive the `#TABLE<code>` key -- used by BOTH the initState subscribe and
/// the scannerVidInWorkforce lookup, so the load key and lookup key match.
///
/// Mirrors `otq_txf_2.dart:231`:
/// `autheniumDecode(normalizeTableName(widget.component['table'] ?? '')) ?? ''`
///
/// [tableRaw] is the raw component `table` value. `normalizeTableName`
/// (global2.dart) handles `//` subcollection splitting; `autheniumDecode`
/// (global.dart) decodes `_25FC_`/`_2B58_` server escapes. Null-coalesced to
/// empty string.
///
/// Pure function with no side effects -- unit-tested in test/scanner_test.dart.
String scannerTableCode(String tableRaw) {
  return autheniumDecode(normalizeTableName(tableRaw)) ?? '';
}

/// Hybrid local-first workforce compare for the scanner decrypt pipeline.
///
/// Checks whether [vid] (the resolved VID string -- decrypted or raw depending
/// on the `qr` gate) exists in the workforce table specified by [tableRaw]
/// and [searchField].
///
/// **Local path (preferred):** If `#TABLE<tableCode>` is non-null in
/// [transactionStore] (the table has been loaded by `createInternalTable`),
/// uses [findData] for an O(1) map lookup. This avoids a network round-trip
/// and works offline.
///
/// **Firestore fallback:** If `#TABLE<tableCode>` is null (table not yet
/// loaded), falls back to [scannerValidateQr] which queries Firestore with
/// a dual string/num match.
///
/// **CRITICAL distinction:** `table != null` + [findData] returns null =
/// genuine not-found (return false). `table == null` = table not loaded
/// (fall back to Firestore). Getting this wrong would miss genuine
/// not-found cases.
///
/// [tableRaw] is the raw component `table` value (e.g. `"workforce"`).
/// [searchField] is the Firestore field name (used only in the fallback path).
/// [vid] is the resolved VID as a string (e.g. `'12345'`).
/// [tenantVid] (round 8) is the tenant container vid for the Firestore fallback
/// path -- resolved in the widget via getTableVid. Null is backward-compatible
/// (scannerValidateQr falls back to applicationTableVid). The local #TABLE path
/// is keyed by code and does not use the vid, so only the fallback forwards it.
///
/// Throws on Firestore errors in the fallback path. The caller catches.
Future<bool> scannerVidInWorkforce(
  String tableRaw,
  String searchField,
  String vid, {
  int? tenantVid,
}) async {
  // 1. Compute tableCode via the shared scannerTableCode helper -- the SINGLE
  //    source of truth for the #TABLE<code> key. The initState subscribe in
  //    scanner.dart uses the same helper, so the load key and this lookup key
  //    are guaranteed identical (round 7 fix). The helper applies the same
  //    autheniumDecode(normalizeTableName(...)) chain as otq_txf_2.dart:231.
  final String tableCode = scannerTableCode(tableRaw);
  devPrint('scannerVidInWorkforce tableCode=$tableCode tenantVid=$tenantVid');
  if (tableCode.isEmpty) {
    // Empty table code -- fall back to Firestore (defensive). Forward tenantVid
    // so the fallback query hits the correct tenant container.
    devPrint('scannerVidInWorkforce FALLBACK to Firestore (empty tableCode)');
    return scannerValidateQr(tableRaw, searchField, vid, tenantVid: tenantVid);
  }

  // 2. Check if the table is loaded locally in transactionStore.
  //    Pattern: transactionStore.state.screenTx['#TABLE$tableCode']
  //    Verified at findData (table_repository.dart:1953),
  //    getQRContent (api.dart), createInternalTable (table_repository.dart).
  final dynamic table = transactionStore.state.screenTx['#TABLE$tableCode'];

  if (table != null) {
    // 3a. Table IS loaded locally. Use findData for O(1) map lookup.
    //     findData (table_repository.dart:1953) returns List<dynamic>? --
    //     the row keyed by vid, or null if not present.
    //     CRITICAL: table non-null + findData null = genuine not-found (false).
    //     Do NOT fall back to Firestore here.
    final bool found = findData(tableCode, vid) != null;
    devPrint('scannerVidInWorkforce LOCAL hit=$found');
    return found;
  }

  // 3b. Table NOT loaded. Fall back to Firestore query. Forward tenantVid so
  //     the fallback query hits the correct tenant container (round 8 fix).
  //     scannerValidateQr handles the dual string/num query.
  devPrint('scannerVidInWorkforce FALLBACK to Firestore');
  return scannerValidateQr(tableRaw, searchField, vid, tenantVid: tenantVid);
}
