import '../global.dart';
import '../global2.dart';
import '../states/app_code_controller.dart';
import 'table_repository.dart';

/// Outcome of a scanner validation lookup.
///
/// `found` -- the scanned value matched the table (today's boolean answer).
/// `row`   -- the matched document's named fields, or `null` when the answer
///            came from the local `#TABLE` positional cache (which has no
///            field names) or when nothing matched.
///
/// An AMBIGUOUS lookup (more than one matching document -- only detected when
/// the caller sets `needRow`) is reported as `(found: false, row: null)`,
/// deliberately the SAME shape as not-found, because the widget shows the same
/// slot-9/10 "QR salah" snackbar for both. The two cases are told apart in the
/// debug log, not in the return value.
typedef ScannerMatch = ({bool found, Map<String, dynamic>? row});

/// Decide the match outcome from the rows a validation query returned.
///
/// [needRow] means "the caller needs the matched document", which is true
/// exactly when the scanner component carries a non-empty `routeParams`. When
/// it is true, a >1-row result is AMBIGUOUS and reported as not-found:
/// silently taking the first row picks an arbitrary site, and for the meter
/// feature that is a reading billed to the wrong tenant.
///
/// When [needRow] is false the caller only wants a yes/no answer, so the
/// historical first-match-wins semantics are preserved untouched -- that is
/// what keeps every already-live scanner page (e.g. DriverScanLogin) byte-for-
/// byte the same.
///
/// Pure function: no Firestore, no globals. Unit-tested in
/// test/scanner_test.dart.
ScannerMatch scannerMatchFromRows(
  List<Map<String, dynamic>> rows, {
  required bool needRow,
}) {
  if (rows.isEmpty) return (found: false, row: null);
  if (needRow && rows.length > 1) return (found: false, row: null);
  return (found: true, row: rows.first);
}

/// Materialise Firestore query docs into typed named-field maps.
///
/// `firestoreDb` is statically `dynamic` in this repo, so `snap.docs` is cast
/// with `as List` (the established pattern) and each element is copied with
/// `Map<String, dynamic>.from(d.data() as Map)` -- the same cast
/// `fetchOpeningState` in driver_home_support.dart uses. A `.map().toList()`
/// off a dynamic infers `List<dynamic>` at runtime and fails to assign to a
/// typed variable, so the collection-for below is deliberate.
///
/// A null `d.data()` would make that cast throw; query snapshots never yield
/// null data (only a `DocumentSnapshot` for a missing doc does), and if one
/// ever did, `scanner.dart`'s existing `catch (_)` around the lookup turns the
/// throw into not-found -> the "QR salah" snackbar, never a crash.
///
/// Each row is stamped with `__docId` = the document's own id, because every
/// other `routeParams` producer feeds `writeRouteParamsFromRow` a row that came
/// from `subscribeToMapCollection` (table_repository.dart), which stamps that
/// same key -- without it a config author copying `docId◼{__docId}` from a
/// working LIST_CARD would get a silently blank key here.
List<Map<String, dynamic>> _rowsFromDocs(List<dynamic> docs) {
  return <Map<String, dynamic>>[
    for (final dynamic d in docs)
      Map<String, dynamic>.from(d.data() as Map)..['__docId'] = d.id,
  ];
}

/// Validate a scanned QR value against a Firestore table.
///
/// Builds the collection path via [eventCollectionPath] (table_repository.dart)
/// using [AppCodeController.applicationTableVid], then queries for documents
/// where [searchField] equals [scanValue].
///
/// Because Firestore distinguishes string `'123'` from number `123`, this
/// function queries for the String value first, and if [scanValue] also parses
/// to a [num], runs a second query with the numeric value. The first query
/// that returns rows wins.
///
/// [tableRaw] is the raw component `table` value (e.g. `"workforce"` or
/// `"docId//subColl"`). Passed directly to [eventCollectionPath] which handles
/// both the legacy plain-name and new `//` subcollection forms.
///
/// [needRow] (routeParams support) makes the query fetch up to TWO documents
/// instead of one, so [scannerMatchFromRows] can detect an ambiguous match.
/// It is `false` by default, so a caller that only wants a yes/no answer pays
/// exactly the same single-document read as before.
///
/// KNOWN LIMITATION, deliberate: the string query short-circuits the numeric
/// one, so a tenant storing the same field as `'123'` in one doc and `123` in
/// another would not have that cross-type pair flagged as ambiguous. Detecting
/// it would double the reads on every scan for a shape no live tenant has.
///
/// Throws on Firestore errors (offline, permission, invalid path). The caller
/// is expected to catch and treat as NOT-FOUND.
Future<ScannerMatch> scannerValidateQr(
  String tableRaw,
  String searchField,
  String scanValue, {
  int? tenantVid,
  bool needRow = false,
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
    'scannerValidateQr path=$path field=$searchField '
    'value=$scanValue vid=$vid needRow=$needRow',
  );
  if (path.isEmpty) return (found: false, row: null);

  // limit(2) ONLY when the caller needs the row. That single extra document
  // read is what the >1-match detection costs, and a routeParams-less scan
  // never pays it.
  final int lim = needRow ? 2 : 1;

  // Query 1: String match.
  final dynamic snap = await firestoreDb
      .collection(path)
      .where(searchField, isEqualTo: scanValue)
      .limit(lim)
      .get();
  final List<Map<String, dynamic>> rows = _rowsFromDocs(snap.docs as List);
  if (rows.isNotEmpty) {
    final ScannerMatch m = scannerMatchFromRows(rows, needRow: needRow);
    devPrint(
      'scannerValidateQr string match n=${rows.length} '
      'found=${m.found}${m.found ? '' : ' AMBIGUOUS'}',
    );
    return m;
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
        .limit(lim)
        .get();
    final List<Map<String, dynamic>> rows2 = _rowsFromDocs(snap2.docs as List);
    if (rows2.isNotEmpty) {
      final ScannerMatch m2 = scannerMatchFromRows(rows2, needRow: needRow);
      devPrint(
        'scannerValidateQr num match n=${rows2.length} '
        'found=${m2.found}${m2.found ? '' : ' AMBIGUOUS'}',
      );
      return m2;
    }
  }

  devPrint('scannerValidateQr NOT FOUND');
  return (found: false, row: null);
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
/// **Local path (preferred, [needRow] false only):** If `#TABLE<tableCode>` is
/// non-null in [transactionStore] (the table has been loaded by
/// `createInternalTable`), uses [findData] for an O(1) map lookup. This avoids
/// a network round-trip and works offline.
///
/// **Firestore fallback:** If `#TABLE<tableCode>` is null (table not yet
/// loaded), falls back to [scannerValidateQr] which queries Firestore with
/// a dual string/num match.
///
/// **CRITICAL distinction:** `table != null` + [findData] returns null =
/// genuine not-found (return `found: false`). `table == null` = table not
/// loaded (fall back to Firestore). Getting this wrong would miss genuine
/// not-found cases.
///
/// **[needRow] (routeParams support):** when true the caller needs the matched
/// document's NAMED FIELDS, so the local path is skipped entirely -- [findData]
/// returns a POSITIONAL `List<dynamic>` row with no field names, from which
/// `{li}`/`{lk}`/`{ln}` are unresolvable. Only the Firestore path can serve it.
/// This costs nothing for the first consumer: its `table` is a SUBCOLLECTION
/// (`docId//subColl`), which `subscribeToTable` cannot load, so `#TABLE<code>`
/// is always null there and the Firestore fallback already always ran.
/// [needRow] false leaves the hybrid path byte-for-byte as it was.
///
/// [tableRaw] is the raw component `table` value (e.g. `"workforce"`).
/// [searchField] is the Firestore field name (used only in the Firestore path).
/// [vid] is the resolved VID as a string (e.g. `'12345'`).
/// [tenantVid] is the tenant container vid for the Firestore path -- resolved
/// in the widget via getTableVid. Null is backward-compatible
/// (scannerValidateQr falls back to applicationTableVid). The local #TABLE path
/// is keyed by code and does not use the vid, so only the fallback forwards it.
///
/// Throws on Firestore errors in the fallback path. The caller catches.
Future<ScannerMatch> scannerVidInWorkforce(
  String tableRaw,
  String searchField,
  String vid, {
  int? tenantVid,
  bool needRow = false,
}) async {
  // 1. Compute tableCode via the shared scannerTableCode helper -- the SINGLE
  //    source of truth for the #TABLE<code> key. The initState subscribe in
  //    scanner.dart uses the same helper, so the load key and this lookup key
  //    are guaranteed identical. The helper applies the same
  //    autheniumDecode(normalizeTableName(...)) chain as otq_txf_2.dart.
  final String tableCode = scannerTableCode(tableRaw);
  devPrint(
    'scannerVidInWorkforce tableCode=$tableCode '
    'tenantVid=$tenantVid needRow=$needRow',
  );
  if (tableCode.isEmpty) {
    // Empty table code -- fall back to Firestore (defensive). Forward tenantVid
    // so the fallback query hits the correct tenant container, and needRow so
    // an ambiguous match is still caught.
    devPrint('scannerVidInWorkforce FALLBACK to Firestore (empty tableCode)');
    return scannerValidateQr(
      tableRaw,
      searchField,
      vid,
      tenantVid: tenantVid,
      needRow: needRow,
    );
  }

  // 2. routeParams gate: the caller needs NAMED FIELDS. findData
  //    (table_repository.dart) hands back a POSITIONAL List<dynamic> row, so
  //    the local cache can never satisfy it -- go straight to Firestore. This
  //    branch is the ONLY behavioural difference for a scanner that declares
  //    routeParams; without it the widget would get found=true with row=null
  //    and silently dispatch nothing.
  if (needRow) {
    devPrint('scannerVidInWorkforce needRow -> Firestore (named fields)');
    return scannerValidateQr(
      tableRaw,
      searchField,
      vid,
      tenantVid: tenantVid,
      needRow: true,
    );
  }

  // 3. Check if the table is loaded locally in transactionStore.
  //    Pattern: transactionStore.state.screenTx['#TABLE$tableCode']
  //    Same key used by findData, getQRContent and createInternalTable.
  final dynamic table = transactionStore.state.screenTx['#TABLE$tableCode'];

  if (table != null) {
    // 3a. Table IS loaded locally. Use findData for O(1) map lookup.
    //     findData returns List<dynamic>? -- the row keyed by vid, or null if
    //     not present. CRITICAL: table non-null + findData null = genuine
    //     not-found. Do NOT fall back to Firestore here.
    //     row is null because the local row is positional, not named-field.
    //     Step 2 guarantees needRow is false here, so no caller needs those
    //     fields.
    final bool found = findData(tableCode, vid) != null;
    devPrint('scannerVidInWorkforce LOCAL hit=$found');
    return (found: found, row: null);
  }

  // 3b. Table NOT loaded. Fall back to Firestore query. Forward tenantVid so
  //     the fallback query hits the correct tenant container.
  //     scannerValidateQr handles the dual string/num query. needRow is false
  //     here by construction (step 2 already returned otherwise).
  devPrint('scannerVidInWorkforce FALLBACK to Firestore');
  return scannerValidateQr(tableRaw, searchField, vid, tenantVid: tenantVid);
}
