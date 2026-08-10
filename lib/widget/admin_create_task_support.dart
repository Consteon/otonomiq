import '../api.dart'; // getNowMillisecondFromEpoch
import '../global.dart'; // emptyString ('--' no-data marker)
import '../screen_session.dart';
import 'driver_home_support.dart'; // coerceNum

// ============================================================================
// Admin Create Task support -- pure helpers for P2 taskItemBuilder +
// P4 task_create_submit.
//
// Mirror: lib/widget/admin_home_support.dart (pure function section).
// All computation is pure over inputs. The draft holder is the ONLY mutable
// static state; it is cleared on submit/cancel.
// ============================================================================

// ── DraftItem model ─────────────────────────────────────────────────────────

/// One item line in the in-flight wizard draft.
///
/// Mutable: qty fields are edited by the builder UI. The [toItMap]
/// method serializes to the it[] element shape consumed by
/// item_execution_list.dart:218-280.
class DraftItem {
  /// Item id (FK -> item collection). Immutable once added.
  final String ii;

  /// Item display name (denorm from item `in` field). Immutable once added.
  final String itemName;

  /// Transaction kind: 'deliver' | 'sale' | 'purchase' | 'refill' | 'buy'.
  String tx;

  /// Planned drop qty (deliver only).
  int pd;

  /// Planned pickup qty (deliver only).
  int pp;

  /// Sale qty (sale only -- walkin/order modes).
  int ps;

  /// Purchase qty (purchase only).
  int pb;

  /// Refill qty (refill only -- order mode).
  int pr;

  /// Condition out: 'full' | 'empty' | '' (deliver + sale).
  String cdo;

  /// Condition in: 'full' | 'empty' | '' (deliver + purchase).
  String cdi;

  /// Water type: 'ro' | 'refill' | '' (refill only).
  String wt;

  /// Unit price (integer rupiah, e.g. 45000). Sale rows (walkin/order) and
  /// ALL supplier rows carry this field.
  int hg;

  /// Qty out (supplier: sale out, refill empty-out). Default 0.
  int qo;

  /// Qty in (supplier: buy in, refill full-in). Default 0.
  int qi;

  DraftItem({
    required this.ii,
    required this.itemName,
    required this.tx,
    this.pd = 0,
    this.pp = 0,
    this.ps = 0,
    this.pb = 0,
    this.pr = 0,
    this.cdo = '',
    this.cdi = '',
    this.wt = '',
    this.hg = 0,
    this.qo = 0,
    this.qi = 0,
  });

  /// Serialize to the Firestore it[] element shape (order mode).
  ///
  /// Sets zero-fields per tx type so the consumer (item_execution_list)
  /// sees a complete shape regardless of tx kind. Adds `hg` for sale rows
  /// only (deliver/purchase/refill never carry price).
  Map<String, dynamic> toItMap() {
    final Map<String, dynamic> m = <String, dynamic>{
      'ii': ii,
      'in': itemName,
      'tx': tx,
      'pd': tx == 'deliver' ? pd : 0,
      'pp': tx == 'deliver' ? pp : 0,
      'ps': tx == 'sale' ? ps : 0,
      'pb': tx == 'purchase' ? pb : 0,
      'pr': tx == 'refill' ? pr : 0,
      'cdo': (tx == 'deliver' || tx == 'sale') ? cdo : '',
      'cdi': (tx == 'deliver' || tx == 'purchase') ? cdi : '',
      'wt': tx == 'refill' ? wt : '',
      'ad': null,
      'ap': null,
    };
    // Price for sale rows only (per spec target doc; deliver rows have no hg)
    if (tx == 'sale') {
      m['hg'] = hg;
    }
    return m;
  }

  /// Serialize to the nota li[] element shape (walkin POS mode).
  ///
  /// Walkin POS lines: {ii, in, qt, hg, sub} -- all fields present, none
  /// omitted. qt/hg/sub are int (Firestore Number). in is the item display
  /// name (String). ii is the item id (String).
  Map<String, dynamic> toLiMap() {
    return <String, dynamic>{
      'ii': ii,
      'in': itemName,
      'qt': ps, // walkin qty = sale qty (ps)
      'hg': hg,
      'sub': ps * hg,
    };
  }

  /// Serialize to the supplier nota li[] element shape.
  ///
  /// Supplier lines: {ii, in, tx, qo, qi, hrg} -- qo/qi/hrg are int
  /// (Firestore Number). Irrelevant qo/qi carry 0.
  Map<String, dynamic> toSupplierLiMap() {
    return <String, dynamic>{
      'ii': ii,
      'in': itemName,
      'tx': tx,
      'qo': qo,
      'qi': qi,
      'hrg': hg,
    };
  }

  /// Serialize to the seed nota li[] element shape.
  ///
  /// Seed lines: {ii, in, qt, cd} -- qt is int (Firestore Number),
  /// cd is always 'full' (galon at customer = full/unreturned).
  /// Uses ps as the internal qty holder (same mapping as walkin toLiMap).
  Map<String, dynamic> toSeedLiMap() {
    return <String, dynamic>{'ii': ii, 'in': itemName, 'qt': ps, 'cd': 'full'};
  }

  /// The primary quantity for this line's tx type (for display in summaries).
  int get primaryQty {
    switch (tx) {
      case 'deliver':
        return pd;
      case 'sale':
        return ps;
      case 'purchase':
        return pb;
      case 'refill':
        return pr;
      default:
        return 0;
    }
  }
}

// ── Totals model ────────────────────────────────────────────────────────────

/// Aggregate totals across all draft items.
class TaskTotals {
  final int totalDrop;
  final int totalPickup;
  final int totalSale;
  final int totalPurchase;
  final int totalRefill;

  /// Sum of hg * ps across all sale lines.
  final int totalSalePrice;
  final int lineCount;

  const TaskTotals({
    this.totalDrop = 0,
    this.totalPickup = 0,
    this.totalSale = 0,
    this.totalPurchase = 0,
    this.totalRefill = 0,
    this.totalSalePrice = 0,
    this.lineCount = 0,
  });
}

// ── Draft holder (static, cross-screen wizard state) ────────────────────────

/// Static draft holder for the create-task wizard.
///
/// Uses a WIZARD KEY (not a per-page scrName) because the draft is DELIBERATELY
/// shared across P2 (builder) and P4 (submit) screens -- analogous to
/// #ACTIVE_TASK cross-screen semantics.
///
/// The key is `component['wizardKey']` (default 'admin_create_task'). This
/// allows future multi-wizard scenarios (different tenants, different flows)
/// without collision.
///
/// Cleared on: submit success (clearDraft, task_create_submit) and the global
/// buildPage clear hook (clearAllDrafts via ui_component.dart, on
/// constructAllPageElements / proxy refresh). NOTE: there is currently NO
/// explicit wizard-cancel / P1-entry clear, so abandoning the wizard without
/// submitting leaves the draft until the next buildPage(clear:true). This is
/// the same lifecycle as the pre-existing draftItems holder (customer/vehicle
/// holders below clear in lockstep with it).
class AdminCreateTaskSupport {
  /// In-flight draft items keyed by wizard key.
  static final Map<String, List<DraftItem>> draftItems =
      <String, List<DraftItem>>{};

  /// In-flight customer data keyed by wizard key.
  /// Set from P1 (TaskFeedList flat-mode tap), read by P4 (TaskDraftInfo +
  /// TaskCreateSubmit). Shape: {'kl': id, 'kn': name, 'al': address,
  /// 'pic': contact}.
  static final Map<String, Map<String, String>> draftCustomer =
      <String, Map<String, String>>{};

  /// In-flight vehicle data keyed by wizard key.
  /// Set from P3 (PickerList capture), read by P4 (TaskDraftInfo +
  /// TaskCreateSubmit). Shape: {'vv': id, 'vn': displayName}.
  static final Map<String, Map<String, String>> draftVehicle =
      <String, Map<String, String>>{};

  /// Snapshot of the last successfully created task, keyed by wizard key.
  /// Shape: {'tnm': String, 'kn': String, 'vn': String,
  ///         'totalDrop': int, 'totalPickup': int}.
  ///
  /// NOT cleared by clearDraft / clearAllDrafts -- outlives the draft for
  /// the success screen (P5 reads it AFTER clearDraft fires on submit).
  /// Overwritten on the next successful create. Memory cost is negligible
  /// (5 small fields per wizard key; wizard keys are reused).
  static final Map<String, Map<String, dynamic>> lastCreated =
      <String, Map<String, dynamic>>{};

  /// Set the customer for a wizard key. Overwrites any prior value (user
  /// re-picked a different customer on P1).
  static void setCustomer(
    String wizardKey, {
    required String kl,
    required String kn,
    required String al,
    String pic = '',
  }) {
    registerScreenSession();
    draftCustomer[wizardKey] = <String, String>{
      'kl': kl,
      'kn': kn,
      'al': al,
      'pic': pic,
    };
  }

  /// Get the customer map for a wizard key. Returns null if not set.
  static Map<String, String>? getCustomer(String wizardKey) {
    return draftCustomer[wizardKey];
  }

  /// Set the vehicle for a wizard key.
  static void setVehicle(
    String wizardKey, {
    required String vv,
    required String vn,
  }) {
    draftVehicle[wizardKey] = <String, String>{'vv': vv, 'vn': vn};
  }

  /// Get the vehicle map for a wizard key. Returns null if not set.
  static Map<String, String>? getVehicle(String wizardKey) {
    return draftVehicle[wizardKey];
  }

  /// Stash a snapshot for the success screen. Called from
  /// task_create_submit after a successful create, before clearDraft.
  static void setLastCreated(
    String wizardKey, {
    required String tnm,
    required String kn,
    required String vn,
    required int totalDrop,
    required int totalPickup,
  }) {
    lastCreated[wizardKey] = <String, dynamic>{
      'tnm': tnm,
      'kn': kn,
      'vn': vn,
      'totalDrop': totalDrop,
      'totalPickup': totalPickup,
    };
  }

  /// Read the last-created snapshot. Returns null if no task has been
  /// created for this wizard key (or after app restart -- in-memory only).
  static Map<String, dynamic>? getLastCreated(String wizardKey) {
    return lastCreated[wizardKey];
  }

  /// Get or create the draft list for a wizard key.
  static List<DraftItem> getDraft(String wizardKey) {
    registerScreenSession();
    return draftItems.putIfAbsent(wizardKey, () => <DraftItem>[]);
  }

  static void registerScreenSession() {
    // Registered for audit; never auto-cleared. Flow-boundary clearDraft
    // calls stay as-is. The ponytail comment from ui_component.dart's clear
    // block (explaining why clearAllDrafts is NOT in buildPage) now lives
    // here as the design rationale for persistent:true.
    //
    // ponytail: do NOT clear drafts on buildPage(clear:true). That runs once
    // per screen on every readSettings refresh (constructPageElements), so a
    // background refresh mid-wizard wiped the in-flight customer/vehicle and
    // P4 rendered null. The real resets are per-wizardKey and already covered:
    // P1 customer-pick clearDraft (task_feed_list) + submit-success clearDraft
    // (task_create_submit). Re-add a scoped clear only if a tenant switch must
    // drop a half-done draft.
    ScreenSession.ensure(
      'AdminCreateTaskSupport.drafts',
      (_) => AdminCreateTaskSupport.clearAllDrafts(),
      persistent: true,
    );
  }

  /// Clear the draft for a wizard key.
  static void clearDraft(String wizardKey) {
    draftItems.remove(wizardKey);
    draftCustomer.remove(wizardKey);
    draftVehicle.remove(wizardKey);
  }

  /// Clear ALL drafts (used by ui_component.dart clearData when it cannot
  /// know which wizard key is active).
  static void clearAllDrafts() {
    draftItems.clear();
    draftCustomer.clear();
    draftVehicle.clear();
  }

  // ── Pure helpers ──────────────────────────────────────────────────────

  /// Convert draft items to the it[] array shape for Firestore.
  ///
  /// Returns an explicitly typed `List<Map<String, dynamic>>`.
  /// Empty draft -> empty list.
  static List<Map<String, dynamic>> draftToItArray(List<DraftItem> items) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final DraftItem item in items) {
      out.add(item.toItMap());
    }
    return out;
  }

  /// Convert draft items to the nota li[] array shape for Firestore.
  ///
  /// Returns an explicitly typed `List<Map<String, dynamic>>`.
  /// Each element: {ii:String, in:String, qt:int, hg:int, sub:int}.
  /// Empty draft -> empty list.
  static List<Map<String, dynamic>> draftToLiArray(List<DraftItem> items) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final DraftItem item in items) {
      out.add(item.toLiMap());
    }
    return out;
  }

  /// Convert draft items to the supplier nota li[] array shape for Firestore.
  ///
  /// Each element: {ii:String, in:String, tx:String, qo:int, qi:int, hrg:int}.
  /// Empty draft -> empty list.
  static List<Map<String, dynamic>> draftToSupplierLiArray(
    List<DraftItem> items,
  ) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final DraftItem item in items) {
      out.add(item.toSupplierLiMap());
    }
    return out;
  }

  /// Compute supplier total: sum of hrg * max(qo, qi) across all items.
  ///
  /// Subtotal per line = hrg * max(qo, qi). Total = sum of all subtotals.
  /// Pure function.
  static int computeSupplierTotal(List<DraftItem> items) {
    int total = 0;
    for (final DraftItem item in items) {
      final int qty = item.qo > item.qi ? item.qo : item.qi;
      total += item.hg * qty;
    }
    return total;
  }

  /// Check if all supplier draft lines are valid for submission.
  ///
  /// buy: qi >= 1 AND hg > 0
  /// sale: qo >= 1 AND hg > 0
  /// refill: qo >= 1 AND qi >= 1 (hg >= 0 always true for int)
  ///
  /// Unknown tx -> false (fail-safe).
  static bool allSupplierLinesValid(List<DraftItem> items) {
    return items.every((DraftItem item) {
      switch (item.tx) {
        case 'buy':
          return item.qi >= 1 && item.hg > 0;
        case 'sale':
          return item.qo >= 1 && item.hg > 0;
        case 'refill':
          return item.qo >= 1 && item.qi >= 1;
        default:
          return false;
      }
    });
  }

  /// Convert draft items to the seed nota li[] array shape for Firestore.
  ///
  /// Each element: {ii:String, in:String, qt:int, cd:String}.
  /// Empty draft -> empty list.
  static List<Map<String, dynamic>> draftToSeedLiArray(List<DraftItem> items) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final DraftItem item in items) {
      out.add(item.toSeedLiMap());
    }
    return out;
  }

  /// Compute seed total qty: sum of ps (the qt holder) across all items.
  ///
  /// Pure function. Returns 0 for empty list.
  static int computeSeedTotalQty(List<DraftItem> items) {
    int total = 0;
    for (final DraftItem item in items) {
      total += item.ps;
    }
    return total;
  }

  /// Check if all seed draft lines are valid for submission.
  ///
  /// Every line must have ps >= 1 (at least 1 unit of this item at customer).
  /// Empty list -> true (vacuously; submit guards empty liArray separately).
  static bool allSeedLinesValid(List<DraftItem> items) {
    return items.every((DraftItem item) => item.ps >= 1);
  }

  /// Compute aggregate totals across all draft items.
  static TaskTotals computeTotals(List<DraftItem> items) {
    int drop = 0, pickup = 0, sale = 0, purchase = 0, refill = 0;
    int salePrice = 0;
    for (final DraftItem item in items) {
      switch (item.tx) {
        case 'deliver':
          drop += item.pd;
          pickup += item.pp;
          break;
        case 'sale':
          sale += item.ps;
          salePrice += item.hg * item.ps;
          break;
        case 'purchase':
          purchase += item.pb;
          break;
        case 'refill':
          refill += item.pr;
          break;
      }
    }
    return TaskTotals(
      totalDrop: drop,
      totalPickup: pickup,
      totalSale: sale,
      totalPurchase: purchase,
      totalRefill: refill,
      totalSalePrice: salePrice,
      lineCount: items.length,
    );
  }

  /// Format an integer amount as Indonesian Rupiah.
  ///
  /// Examples: 0 -> "Rp 0", 45000 -> "Rp 45.000", 1250000 -> "Rp 1.250.000".
  /// Negative amounts are prefixed with minus: -5000 -> "Rp -5.000".
  /// Pure function, no intl locale dependency.
  static String formatRupiah(int amount) {
    if (amount == 0) return 'Rp 0';
    final bool negative = amount < 0;
    final String raw = amount.abs().toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) buf.write('.');
      buf.write(raw[i]);
    }
    return negative ? 'Rp -${buf.toString()}' : 'Rp ${buf.toString()}';
  }

  /// Generate a deterministic task id: TASK-{kl7}-{yyyyMMdd}-{HHmmss}.
  ///
  /// [kl] -- customer id. Uses up to 7 chars (truncated if longer).
  /// [nowMs] -- optional override for testing; defaults to
  ///   getNowMillisecondFromEpoch().
  ///
  /// Mirrors genOpeningCnm in driver_home_support.dart (WIB-aware date).
  /// The HHmmss suffix provides per-second uniqueness for same-client
  /// same-day tasks. Collision is astronomically unlikely in practice
  /// (admin creates ~10 tasks/day).
  static String generateTnm(String kl, {int? nowMs}) {
    const int wibOffsetMs = 25200000; // UTC+7
    final int now = nowMs ?? getNowMillisecondFromEpoch();
    final DateTime wibNow = DateTime.fromMillisecondsSinceEpoch(
      now + wibOffsetMs,
      isUtc: true,
    );
    final String dateStr =
        '${wibNow.year}${wibNow.month.toString().padLeft(2, '0')}${wibNow.day.toString().padLeft(2, '0')}';
    final String timeStr =
        '${wibNow.hour.toString().padLeft(2, '0')}${wibNow.minute.toString().padLeft(2, '0')}${wibNow.second.toString().padLeft(2, '0')}';
    final String klShort = kl.length > 7 ? kl.substring(0, 7) : kl;
    return 'TASK-$klShort-$dateStr-$timeStr';
  }

  /// Look up the outstanding qty for a (client, item, condition) tuple from
  /// asset_cache docs.
  ///
  /// Returns 0 when no matching row exists (genesis pending / CF undeployed).
  /// Pure -- caller passes the already-loaded asset_cache list.
  ///
  /// Convention #7: dynamic guards on all field reads.
  static int lookupOutstanding(
    List<Map<String, dynamic>> assetCacheDocs, {
    required String clientLv,
    required String itemIi,
    required String condition,
    String locationField = 'lv',
    String locationTypeField = 'lt',
    String itemField = 'ii',
    String conditionField = 'cd',
    String qtyField = 'qt',
  }) {
    for (final Map<String, dynamic> doc in assetCacheDocs) {
      final String lv = (doc[locationField] ?? '').toString().trim();
      final String ii = (doc[itemField] ?? '').toString().trim();
      final String cd = (doc[conditionField] ?? '').toString().trim();
      if (lv == clientLv && ii == itemIi && cd == condition) {
        return coerceNum(doc[qtyField]).toInt();
      }
    }
    return 0; // no row = suggestion off (genesis pending)
  }

  /// Whether asset_cache has ANY row for this client. Used to determine
  /// if Model B suggestion should be active.
  static bool hasOutstandingData(
    List<Map<String, dynamic>> assetCacheDocs,
    String clientLv, {
    String locationField = 'lv',
  }) {
    for (final Map<String, dynamic> doc in assetCacheDocs) {
      if ((doc[locationField] ?? '').toString().trim() == clientLv) {
        return true;
      }
    }
    return false;
  }

  /// Compute the suggested pickup qty (Model B).
  ///
  /// Returns null when suggestion is off (no asset_cache data for client).
  /// Returns max(0, pd + outstanding) otherwise.
  static int? suggestPickup({
    required int pd,
    required List<Map<String, dynamic>> assetCacheDocs,
    required String clientLv,
    required String itemIi,
    required String condition,
  }) {
    if (!hasOutstandingData(assetCacheDocs, clientLv)) return null;
    final int outstanding = lookupOutstanding(
      assetCacheDocs,
      clientLv: clientLv,
      itemIi: itemIi,
      condition: condition,
    );
    final int suggested = pd + outstanding;
    return suggested > 0 ? suggested : 0;
  }

  /// Assemble the complete task doc map for Firestore.
  ///
  /// Pure -- all inputs are explicit parameters.
  /// Convention #7: all values are explicitly typed (no dynamic leaks).
  ///
  /// [tst] defaults to 'assigned'. Pass the component's `unassignedStatus`
  /// value to write an unassigned task.
  ///
  /// [vv] and [tdt] are required so a caller cannot silently omit them (their
  /// absence makes the task invisible to every driver feed and manifest --
  /// load-bearing semantics). Pass `vv: ''` and `tdt: null` explicitly to
  /// write an unassigned task.
  ///
  /// [vv], [ln], [tdt] use the omit-when-empty idiom (mirrors assembleNotaDoc
  /// below): when empty/null the key is ABSENT from the doc, not blank.
  /// Rationale (D4): downstream consumers (vehicle_feed_support, evaluateGate,
  /// opening-check manifest) tolerate absent fields via `?? ''` guards, and
  /// the unassigned task must NOT appear in any vehicle's manifest or feed.
  ///
  /// [ln] is the vehicle plate (display name). Emitted only on the assigned
  /// path so AdminTaskList can render `subtitle:"<ln>"`.
  static Map<String, dynamic> assembleTaskDoc({
    required String tnm,
    required String kl,
    required String kn,
    required String al,
    required String vv,
    required String gl,
    required String cv,
    required String cn,
    required int? tdt,
    required int t,
    required List<Map<String, dynamic>> itArray,
    required String tableVid,
    String tst = 'assigned',
    String ln = '',
  }) {
    final Map<String, dynamic> doc = <String, dynamic>{
      'tnm': tnm,
      'tty': 'delivery',
      'tst': tst,
      'kl': kl,
      'kn': kn,
      'al': al,
      'gl': gl,
      'cv': cv,
      'cn': cn,
      't': t,
      'it': itArray,
      'tablevid': tableVid,
      'search': 'tnm\u{2605}$tnm',
    };
    if (vv.isNotEmpty) doc['vv'] = vv;
    if (ln.isNotEmpty) doc['ln'] = ln;
    if (tdt != null) doc['tdt'] = tdt;
    return doc;
  }

  /// Assemble the complete nota doc map for Firestore.
  ///
  /// Pure -- all inputs are explicit parameters.
  /// Canon: tot/qt/hg/sub/t = int (Number); everything else = String.
  /// li[] elements carry ALL fields (shape depends on src/mode).
  ///
  /// Optional supplier params:
  ///   sv -- supplier id (omitted when empty -> walkin doc unchanged).
  ///   sn -- supplier name (omitted when empty).
  ///   d  -- note text (omitted when empty).
  ///
  /// Optional seed params:
  ///   kl -- customer id (replaces hardcoded ''; empty default preserves
  ///         walkin/supplier doc shape).
  ///   kn -- customer name (omitted when empty).
  ///   days -- age in days (omitted when null).
  static Map<String, dynamic> assembleNotaDoc({
    required String nno,
    required String src,
    required String by,
    required String bym,
    required String gl,
    required int tot,
    required List<Map<String, dynamic>> liArray,
    required String cv,
    required String cn,
    required int t,
    required String ts,
    required String tableVid,
    String sv = '',
    String sn = '',
    String d = '',
    String kl = '',
    String kn = '',
    int? days,
  }) {
    final Map<String, dynamic> doc = <String, dynamic>{
      'nno': nno,
      'src': src,
      'ref': '',
      'kl': kl,
      'by': by,
      'bym': bym,
      'st': 'LUNAS',
      'gl': gl,
      'tot': tot,
      'li': liArray,
      'cv': cv,
      'cn': cn,
      't': t,
      'ts': ts,
      'tablevid': tableVid,
      'search': 'nno\u{2605}$nno',
    };
    if (sv.isNotEmpty) doc['sv'] = sv;
    if (sn.isNotEmpty) doc['sn'] = sn;
    if (d.isNotEmpty) doc['d'] = d;
    if (kn.isNotEmpty) doc['kn'] = kn;
    if (days != null) doc['days'] = days;
    return doc;
  }

  /// Format an epoch-ms timestamp as a WIB (UTC+7) human-readable string.
  ///
  /// Returns "yyyy-MM-dd HH:mm" in WIB timezone.
  /// Used for the nota `ts` field (human-readable receipt timestamp).
  static String formatWibTimestamp(int epochMs) {
    const int wibOffsetMs = 25200000; // UTC+7
    final DateTime wibNow = DateTime.fromMillisecondsSinceEpoch(
      epochMs + wibOffsetMs,
      isUtc: true,
    );
    final String y = wibNow.year.toString();
    final String mo = wibNow.month.toString().padLeft(2, '0');
    final String d = wibNow.day.toString().padLeft(2, '0');
    final String h = wibNow.hour.toString().padLeft(2, '0');
    final String mi = wibNow.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  /// Whether [action] indicates savesend mode.
  ///
  /// Returns true when the action field (from component config) is 'savesend'
  /// (case-insensitive, trimmed). Returns false for null, empty, or any other
  /// value. Used as the branch gate in task_create_submit for clean rollback
  /// (remove the config field server-side to revert to legacy path).
  static bool isSavesendMode(dynamic action) {
    if (action == null) return false;
    return action.toString().trim().toLowerCase() == 'savesend';
  }

  /// Parse the numberPos config field to an integer position.
  ///
  /// Returns the parsed int, or 0 if the value is null, empty, or non-numeric.
  /// Position 0 is a safe default (txfControllerCheck will create the slot).
  static int parseNumberPos(dynamic value) {
    if (value == null) return 0;
    final String s = value.toString().trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? 0;
  }

  /// Whether a generated tnm value is usable (not empty, not a no-data
  /// marker, not a sentinel).
  ///
  /// Returns false when:
  /// - [value] is empty (generate never ran or returned nothing)
  /// - [value] is the app empty-marker [emptyString] ('--') or the string
  ///   'null' -- a freshly-created/unpopulated txfController slot seeds
  ///   finalData with emptyString (global2.dart txfControllerCheck), so a
  ///   read from the wrong/undeployed numberPos returns '--', NOT ''. Mirrors
  ///   FtzAutoNumber's own no-data test (ftz_autonumber.dart:59-61). Without
  ///   this, a config-drift read (numberPos absent->0, numberPos != run
  ///   position, or NUMBER widget not deployed) silently writes tnm='--'.
  /// - [value] contains 'COUNTER_ERR' (firestoreSequential failed)
  /// - [value] contains 'POS_ERR' (POS token parse error)
  /// - [value] contains 'POS_NODATA' (POS references empty slot)
  /// - [value] contains '{{' (unresolved template token)
  ///
  /// Sentinel substrings come from global2.dart _getTokenValue / _getCounterValue.
  static bool isGeneratedTnmValid(String value) {
    if (value.isEmpty) return false;
    if (value == emptyString) return false; // '--' no-data marker
    if (value == 'null') return false;
    if (value.contains('COUNTER_ERR')) return false;
    if (value.contains('POS_ERR')) return false;
    if (value.contains('POS_NODATA')) return false;
    if (value.contains('{{')) return false;
    return true;
  }
}
