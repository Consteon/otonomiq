import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart'; // getNowMillisecondFromEpoch, internetConnected
import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // transactionStore, routeStack, gotoRoute, routeExist, errorReport, diamondTextToList, autheniumDecode, emptyString, mapTableContent
import '../global2.dart'; // txfController, txfControllerCheck, addToTxfController, generateAutoNumber, WidgetUpdateController
import '../redux/screen_transaction.dart'; // UpdateScreenTxAction, ScreenTransaction
import 'admin_create_task_support.dart';
import 'admin_home_support.dart'; // AdminTierColors
import 'do_chain.dart';
import 'driver_home_support.dart'; // createNativeDocAutoId, resolveAppVid, stripRouteWrapper, listActiveWarehouses
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'task_item_builder.dart'; // TaskItemBuilder.draftRev

/// NOTA_CREATE_SUBMIT -- submit button for the Walk-in POS wizard.
///
/// Reads the draft from AdminCreateTaskSupport, assembles a nota doc
/// (scalars + li[] native array), and writes via createNativeDocAutoId.
///
/// Above the button: renders TOTAL Rp (sum of all li[].sub).
/// On success: injects {nno} bare screenTx key, clears draft, navigates.
///
/// Clone of TaskCreateSubmit with seams changed for nota fields.
/// NO movement written -- CF OnNotaCreated handles movement per li[] line.
///
/// Submit is blocked (button disabled) unless the draft is non-empty AND
/// every sale line carries a price (hg > 0) -- a zero-priced line can never
/// be committed (spec section 1).
class NotaCreateSubmit extends StatefulWidget {
  const NotaCreateSubmit({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });

  final dynamic component;
  final String scrName;
  final double lPad, tPad, rPad, bPad;

  /// Per-scrName writing-in-progress flag to prevent double taps.
  static final Map<String, bool> _writing = {};

  /// Reset the writing-in-progress flag for a screen. Called from
  /// ui_component.dart clearData so a disposed-mid-await widget cannot leave
  /// the button permanently disabled.
  static void resetWriting(String scrName) => _writing.remove(scrName);

  @override
  State<NotaCreateSubmit> createState() => _NotaCreateSubmitState();
}

class _NotaCreateSubmitState extends State<NotaCreateSubmit> {
  List<String> _textArray = [];
  String _stockLocationCode =
      ''; // warehouse subscription code (empty when config gl is literal)
  String? _selectedWarehouseLv; // user-picked warehouse (>1 case)

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribeStockLocation();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Subscribe to the `stock_location` collection so the widget can resolve
  /// `gl` from the warehouse registry when config gl is empty. Gated: when
  /// config gl is a non-empty literal, no subscription is opened and the
  /// widget runs byte-identically to before this feature.
  ///
  /// Table path: optional `warehouseTable` config override (escape hatch),
  /// else derived from the nota `table` config's tableDocId + the
  /// `stock_location` subcollection (same container). Mirrors
  /// CustodyCountSubmit._subscribeStockLocation (custody_count_submit:129).
  void _subscribeStockLocation() {
    final String configGl = (widget.component['gl'] ?? '').toString().trim();
    if (configGl.isNotEmpty) return; // literal gl: no subscription needed

    final String appVid = resolveAppVid(widget.component);
    final String rawWhTable = (widget.component['warehouseTable'] ?? '')
        .toString()
        .trim();
    TablePath? tp;
    if (rawWhTable.isNotEmpty) {
      tp = parseTablePath(rawWhTable);
    } else {
      final String rawTable = (widget.component['table'] ?? '')
          .toString()
          .trim();
      final String docId = parseTablePath(rawTable).tableDocId;
      if (docId.isNotEmpty) tp = TablePath(docId, 'stock_location');
    }
    if (tp != null && tp.tableDocId.isNotEmpty && tp.subColl.isNotEmpty) {
      _stockLocationCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(
        appVid,
        tp.tableDocId,
        tp.subColl,
        _stockLocationCode,
      );
    }
  }

  /// Read the current stock_location docs and return only active warehouses.
  /// Returns const [] when no subscription is active (config gl is literal).
  List<Map<String, String>> _resolveActiveWarehouses() {
    if (_stockLocationCode.isEmpty) return const [];
    final List<Map<String, dynamic>> stockDocs =
        List<Map<String, dynamic>>.from(
          mapTableContent[_stockLocationCode] ?? const [],
        );
    return listActiveWarehouses(stockDocs);
  }

  /// Text slot accessors:
  ///  [0] "Buat Nota"             (enabled label)
  ///  [1] "TOTAL"                 (total label)
  ///  [2] "Lengkapi item dulu"    (disabled / empty-items / unpriced label)
  ///  [3] "Gagal membuat nota"    (error snackbar)
  ///  [4] "Pilih gudang"          (warehouse dropdown hint/label, gl fallback)
  ///  [5] "Tidak ada gudang aktif" (no-warehouse error, gl fallback)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'walkin_pos').toString().trim();

  /// True when the component src is 'supplier'.
  bool get _isSupplier =>
      (widget.component['src'] ?? '').toString().trim() == 'supplier';

  /// True when the component src is 'seed'.
  bool get _isSeed =>
      (widget.component['src'] ?? '').toString().trim() == 'seed';

  /// True when every sale line carries a positive price. A zero-priced line
  /// (master hrg absent/0 and no manual override) must never be committed.
  bool _allLinesPriced(List<DraftItem> draft) =>
      draft.every((item) => item.hg > 0);

  Future<void> _onSubmit(BuildContext context) async {
    if (NotaCreateSubmit._writing[widget.scrName] == true) return;

    // Online gate: generate_number needs the ONLINE counter transaction.
    if (!internetConnected()) {
      _showSnackBar(context, 'Butuh koneksi untuk membuat nota');
      return;
    }

    NotaCreateSubmit._writing[widget.scrName] = true;
    TaskItemBuilder.draftRev.value++; // trigger rebuild to show spinner

    try {
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
      final String src = (widget.component['src'] ?? 'walkin')
          .toString()
          .trim();
      final bool isSupplier = src == 'supplier';
      final bool isSeed = src == 'seed';

      // 1. Read draft + validate
      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);

      // SEED: use seed li[] shape; SUPPLIER: supplier shape; else walkin.
      final List<Map<String, dynamic>> liArray = isSeed
          ? AdminCreateTaskSupport.draftToSeedLiArray(draft)
          : isSupplier
          ? AdminCreateTaskSupport.draftToSupplierLiArray(draft)
          : AdminCreateTaskSupport.draftToLiArray(draft);

      if (liArray.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, _t(2, 'Lengkapi item dulu'));
        }
        return;
      }

      // 1b. Validation.
      // SEED: every line has qt >= 1.
      // SUPPLIER: per-line qty + price guard (refill allows hrg=0).
      // Walkin: every line must have hg > 0 (existing behavior).
      if (isSeed) {
        if (!AdminCreateTaskSupport.allSeedLinesValid(draft)) {
          if (context.mounted) {
            _showSnackBar(context, _t(2, 'Lengkapi item dulu'));
          }
          return;
        }
      } else if (isSupplier) {
        if (!AdminCreateTaskSupport.allSupplierLinesValid(draft)) {
          if (context.mounted) {
            _showSnackBar(context, _t(2, 'Lengkapi barang dulu'));
          }
          return;
        }
      } else {
        if (!_allLinesPriced(draft)) {
          if (context.mounted) {
            _showSnackBar(context, _t(2, 'Lengkapi item dulu'));
          }
          return;
        }
      }

      // 2. Savesend mode gate
      final bool savesendMode = AdminCreateTaskSupport.isSavesendMode(
        widget.component['action'],
      );

      if (!savesendMode) {
        if (context.mounted) {
          _showSnackBar(context, _t(3, 'Gagal membuat nota'));
        }
        return;
      }

      // 3. Re-seed the nno slot to empty (anti-stale)
      final int numPos = AdminCreateTaskSupport.parseNumberPos(
        widget.component['numberPos'],
      );
      txfControllerCheck(widget.scrName, numPos);
      addToTxfController(numPos, widget.scrName, emptyString);

      // 4. Process run field (trigger generate_number)
      await _processRunCommands(widget.scrName);

      // 5. Read generated nno from numberPos
      final String nno =
          txfController[widget.scrName]?[numPos]?.finalData ?? '';

      // 6. Validate nno
      if (!AdminCreateTaskSupport.isGeneratedTnmValid(nno)) {
        if (context.mounted) {
          _showSnackBar(context, _t(3, 'Gagal membuat nota'));
        }
        return;
      }

      // 7. Read buyer (by) from txfController position.
      // SUPPLIER: empty buyerPosition -> session #NAME.
      // Walkin: reads from txfController at buyerPosition (default 12).
      final String buyerPosRaw = (widget.component['buyerPosition'] ?? '')
          .toString()
          .trim();
      final String byClean;
      if (buyerPosRaw.isEmpty) {
        // Empty buyerPosition: use session #NAME (supplier flow, or
        // any future config that omits the field).
        byClean = (screenTx['#NAME'] ?? '').toString().trim();
      } else {
        final int buyerPos = int.tryParse(buyerPosRaw) ?? 12;
        txfControllerCheck(widget.scrName, buyerPos);
        final String by =
            txfController[widget.scrName]?[buyerPos]?.finalData ?? '';
        byClean = (by == emptyString || by == 'null') ? '' : by.trim();
      }

      // 8. Read payment method (bym) from txfController position.
      // SUPPLIER: empty paymentPosition -> skip (bym = '').
      // Walkin: reads from txfController at paymentPosition (default 1).
      final String paymentPosRaw = (widget.component['paymentPosition'] ?? '')
          .toString()
          .trim();
      final String bym;
      if (paymentPosRaw.isEmpty) {
        bym = '';
      } else {
        final int paymentPos = int.tryParse(paymentPosRaw) ?? 1;
        txfControllerCheck(widget.scrName, paymentPos);
        final String bymRaw =
            txfController[widget.scrName]?[paymentPos]?.finalData ?? '';
        final String bymClean = (bymRaw == emptyString || bymRaw == 'null')
            ? ''
            : bymRaw.trim();
        // Map display value to stored value
        if (bymClean == 'Tunai' || bymClean == 'tunai') {
          bym = 'tunai';
        } else if (bymClean == 'Transfer' || bymClean == 'transfer') {
          bym = 'transfer';
        } else {
          bym = bymClean.toLowerCase();
        }
      }

      // 9. Session fields
      final String cv = (screenTx['#VID'] ?? '').toString().trim();
      final String cn = (screenTx['#NAME'] ?? '').toString().trim();

      // 10. Time
      final int nowMs = getNowMillisecondFromEpoch();
      final String ts = AdminCreateTaskSupport.formatWibTimestamp(nowMs);

      // 11. gl (origin warehouse/depo)
      // Config gl non-empty → literal (existing behavior, zero regression).
      // Config gl empty → registry fallback: resolve from stock_location.
      final String configGl = (widget.component['gl'] ?? '').toString().trim();
      final String gl;
      if (configGl.isNotEmpty) {
        gl = configGl;
      } else if (_stockLocationCode.isNotEmpty) {
        final List<Map<String, String>> activeWh = _resolveActiveWarehouses();
        if (activeWh.length == 1) {
          gl = activeWh.first['lv']!;
        } else if (_selectedWarehouseLv != null &&
            _selectedWarehouseLv!.isNotEmpty &&
            activeWh.any((w) => w['lv'] == _selectedWarehouseLv)) {
          // I1: the picked warehouse must still be in the freshly-resolved
          // active set (a stock_location doc may have flipped inactive while
          // the form was open); otherwise treat selection as unresolved.
          gl = _selectedWarehouseLv!;
        } else {
          // Defensive: button should already be disabled.
          if (context.mounted) {
            _showSnackBar(context, _t(5, 'Tidak ada gudang aktif'));
          }
          return;
        }
      } else {
        gl = ''; // degenerate: no table config, gl stays empty
      }

      // 12. SUPPLIER: resolve sv/sn tokens from component config.
      // resolveDriverCurlyTokens (driver_home_support.dart:274) resolves
      // {supplierId} from bare screenTx key 'supplierId' (set by PICKER_LIST
      // routeParams). Unresolved tokens (still contain '{') -> ''.
      String sv = '';
      String sn = '';
      if (isSupplier) {
        final String svRaw = (widget.component['sv'] ?? '').toString().trim();
        if (svRaw.isNotEmpty) {
          final String svResolved = resolveDriverCurlyTokens(
            svRaw,
            widget.scrName,
          );
          sv = svResolved.contains('{') ? '' : svResolved;
        }
        final String snRaw = (widget.component['sn'] ?? '').toString().trim();
        if (snRaw.isNotEmpty) {
          final String snResolved = resolveDriverCurlyTokens(
            snRaw,
            widget.scrName,
          );
          sn = snResolved.contains('{') ? '' : snResolved;
        }
      }

      // 12b. SEED: resolve kl/kn tokens from component config.
      // resolveDriverCurlyTokens default case resolves bare screenTx keys
      // (customerId/customerName set by LIST_CARD writeRouteParamsFromRow).
      // Unresolved tokens (still contain '{') -> ''.
      String klVal = '';
      String knVal = '';
      if (isSeed) {
        final String klRaw = (widget.component['kl'] ?? '').toString().trim();
        if (klRaw.isNotEmpty) {
          final String klResolved = resolveDriverCurlyTokens(
            klRaw,
            widget.scrName,
          );
          klVal = klResolved.contains('{') ? '' : klResolved;
        }
        final String knRaw = (widget.component['kn'] ?? '').toString().trim();
        if (knRaw.isNotEmpty) {
          final String knResolved = resolveDriverCurlyTokens(
            knRaw,
            widget.scrName,
          );
          knVal = knResolved.contains('{') ? '' : knResolved;
        }
      }

      // 13. Read note from notePosition -> doc field 'd'.
      // Shared by supplier and seed. Empty notePosition or empty value -> skip.
      String d = '';
      {
        final String notePosRaw = (widget.component['notePosition'] ?? '')
            .toString()
            .trim();
        if (notePosRaw.isNotEmpty) {
          final int notePos = int.tryParse(notePosRaw) ?? -1;
          if (notePos >= 0) {
            txfControllerCheck(widget.scrName, notePos);
            final String dRaw =
                txfController[widget.scrName]?[notePos]?.finalData ?? '';
            d = (dRaw == emptyString || dRaw == 'null') ? '' : dRaw.trim();
          }
        }
      }

      // 13b. SEED: read days from daysPosition -> doc field 'days'.
      // Empty daysPosition, empty value, or non-numeric -> null -> OMIT.
      int? daysVal;
      if (isSeed) {
        final String daysPosRaw = (widget.component['daysPosition'] ?? '')
            .toString()
            .trim();
        if (daysPosRaw.isNotEmpty) {
          final int daysPos = int.tryParse(daysPosRaw) ?? -1;
          if (daysPos >= 0) {
            txfControllerCheck(widget.scrName, daysPos);
            final String daysRaw =
                txfController[widget.scrName]?[daysPos]?.finalData ?? '';
            final String daysClean =
                (daysRaw == emptyString || daysRaw == 'null')
                ? ''
                : daysRaw.trim();
            if (daysClean.isNotEmpty) {
              daysVal = int.tryParse(daysClean);
              // Non-numeric -> null -> omit from doc
            }
          }
        }
      }

      // 14. tot: seed = 0 (no money); supplier = computeSupplierTotal;
      // walkin = totalSalePrice.
      final int tot = isSeed
          ? 0
          : isSupplier
          ? AdminCreateTaskSupport.computeSupplierTotal(draft)
          : AdminCreateTaskSupport.computeTotals(draft).totalSalePrice;

      // 15. tableVid
      final String tableVid =
          (widget.component['vidtable'] ?? '').toString().trim().isNotEmpty
          ? (widget.component['vidtable'] ?? '').toString().trim()
          : parseTablePath(
              (widget.component['table'] ?? '').toString().trim(),
            ).tableDocId;

      // 16. Assemble nota doc (sv/sn/d/kl/kn/days are optional -- omitted
      // when empty/null, so walkin/supplier doc shapes are byte-identical).
      final Map<String, dynamic> notaDoc =
          AdminCreateTaskSupport.assembleNotaDoc(
            nno: nno,
            src: src,
            by: byClean,
            bym: bym,
            gl: gl,
            tot: tot,
            liArray: liArray,
            cv: cv,
            cn: cn,
            t: nowMs,
            ts: ts,
            tableVid: tableVid,
            sv: sv,
            sn: sn,
            d: d,
            kl: klVal,
            kn: knVal,
            days: daysVal,
          );

      // 17. Write native auto-id doc
      final String rawTable = (widget.component['table'] ?? '')
          .toString()
          .trim();
      if (rawTable.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, _t(3, 'Gagal membuat nota'));
        }
        return;
      }

      final bool created = await createNativeDocAutoId(
        component: widget.component,
        rawTable: rawTable,
        docMap: notaDoc,
      );

      if (!created) {
        if (context.mounted) {
          _showSnackBar(context, _t(3, 'Gagal membuat nota'));
        }
        return;
      }

      // 18. Inject {nno} token for the destination page.
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'nno': nno})),
      );

      // 19. Clear draft
      AdminCreateTaskSupport.clearDraft(_wizardKey);

      // 20. Navigate (chain-aware)
      // Convention #1: routeStack.push BEFORE gotoRoute.
      final dynamic chain = widget.component['chain'];
      if (chain != null && chain.toString().trim().isNotEmpty) {
        if (context.mounted) {
          await doChain(context, widget.scrName, chain);
        }
      } else {
        final String rawRoute = (widget.component['route'] ?? '')
            .toString()
            .trim();
        final String route = stripRouteWrapper(rawRoute);
        if (route.isNotEmpty && routeExist(route)) {
          routeStack.push(route);
          gotoRoute(route);
        }
      }
    } catch (e) {
      errorReport(e);
      if (context.mounted) {
        _showSnackBar(context, '${_t(3, 'Gagal membuat nota')}: $e');
      }
    } finally {
      NotaCreateSubmit._writing[widget.scrName] = false;
      TaskItemBuilder.draftRev.value++;
    }
  }

  /// Process the `run` config field (trigger generate_number at the run position).
  /// Clone of TaskCreateSubmit._processRunCommands -- identical logic.
  Future<void> _processRunCommands(String scrName) async {
    final String runField =
        (autheniumDecode((widget.component['run'] ?? '').toString()) ?? '')
            .trim()
            .toLowerCase();
    if (runField.isEmpty) return;

    final List<String> commands = runField.split('\u{25C6}'); // diamond
    final List<String> widgetsToUpdate = [];

    for (final String cmd in commands) {
      final List<String> parts = cmd.split(':');
      if (parts.length != 2) continue;

      final int? targetPosition = int.tryParse(parts[0].trim());
      final String action = parts[1].trim().toLowerCase();

      if (targetPosition == null) continue;
      if (action != 'generate_number') continue;

      txfControllerCheck(scrName, targetPosition);
      final controller = txfController[scrName]?[targetPosition];
      if (controller == null) continue;

      final List<dynamic> execute1Actions =
          controller.execute1
              ?.where(
                (item) =>
                    item != null &&
                    item.length >= 2 &&
                    item[1].toString().toLowerCase() == 'generate_number',
              )
              .toList() ??
          [];

      for (final actionItem in execute1Actions) {
        if (actionItem != null && actionItem.length >= 3) {
          final String template = actionItem[2] as String;
          final String generatedString = await generateAutoNumber(
            template,
            scrName,
          );
          addToTxfController(targetPosition, scrName, generatedString);
          widgetsToUpdate.add('$scrName-$targetPosition');
        }
      }
    }

    if (widgetsToUpdate.isNotEmpty) {
      Get.find<WidgetUpdateController>().update(widgetsToUpdate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch revision signal for cross-widget reactivity
      TaskItemBuilder.draftRev.value;

      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
      final bool hasItems = draft.isNotEmpty;

      // SEED: total qty count (plain number).
      // SUPPLIER: supplier total = sum of hrg*max(qo,qi).
      // Walkin: total = totalSalePrice (sum of hg*ps).
      final int tot = _isSeed
          ? AdminCreateTaskSupport.computeSeedTotalQty(draft)
          : _isSupplier
          ? AdminCreateTaskSupport.computeSupplierTotal(draft)
          : AdminCreateTaskSupport.computeTotals(draft).totalSalePrice;

      // ── Warehouse registry fallback (EXTEND #3) ──────────────────────
      // When config gl is a non-empty literal, ALL warehouse logic is
      // skipped and the widget renders byte-identically to before.
      final String configGl = (widget.component['gl'] ?? '').toString().trim();
      final bool hasLiteralGl = configGl.isNotEmpty;
      final bool needsWarehouse =
          !hasLiteralGl && _stockLocationCode.isNotEmpty;

      List<Map<String, String>> activeWarehouses = const [];
      if (needsWarehouse) {
        // W2: bare touch registers the GetX dependency so this Obx rebuilds
        // when stock_location subscription data lands after first paint
        // (mirror asset_stock_list.dart:625).
        mapTableContent[_stockLocationCode];
        activeWarehouses = _resolveActiveWarehouses();
      }

      final bool warehouseResolved =
          !needsWarehouse ||
          activeWarehouses.length == 1 ||
          (activeWarehouses.length > 1 && _selectedWarehouseLv != null);
      // ── End warehouse block ──────────────────────────────────────────

      // SEED: every line has qt >= 1.
      // SUPPLIER: per-line qty + price validation (refill allows hrg=0).
      // Walkin: every line must have hg > 0.
      final bool enabled =
          hasItems &&
          warehouseResolved &&
          (_isSeed
              ? AdminCreateTaskSupport.allSeedLinesValid(draft)
              : _isSupplier
              ? AdminCreateTaskSupport.allSupplierLinesValid(draft)
              : _allLinesPriced(draft));
      final bool isWriting = NotaCreateSubmit._writing[widget.scrName] ?? false;

      final String label = enabled
          ? _t(0, 'Buat Nota')
          : _t(2, 'Lengkapi item dulu');

      final Color bgColor = enabled && !isWriting
          ? AdminTierColors
                .okAction // #2563EB (admin blue)
          : const Color(0xFFD1D5DB); // gray-300
      final Color textColor = enabled && !isWriting
          ? Colors.white
          : const Color(0xFF6B7280);

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // TOTAL line (visible when draft has items)
            if (hasItems) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _t(1, 'TOTAL'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B), // slate-800
                      ),
                    ),
                    Text(
                      _isSeed
                          ? tot.toString()
                          : AdminCreateTaskSupport.formatRupiah(tot),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B), // slate-800
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // ── Warehouse picker / error (EXTEND #3) ───────────────────
            // Rendered only when config gl is empty AND subscription is
            // active. When config gl is literal, this block is skipped.
            if (needsWarehouse && activeWarehouses.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _t(5, 'Tidak ada gudang aktif'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFEF4444), // red-500
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (needsWarehouse && activeWarehouses.length > 1) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(4, 'Pilih gudang'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280), // gray-500
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFD1D5DB)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        // W1: guard against the "exactly one item" assertion —
                        // if the picked warehouse left the active set, show the
                        // hint (null) instead of an orphan value.
                        value:
                            activeWarehouses.any(
                              (w) => w['lv'] == _selectedWarehouseLv,
                            )
                            ? _selectedWarehouseLv
                            : null,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        hint: Text(_t(4, 'Pilih gudang')),
                        items: activeWarehouses.map((wh) {
                          final String display = wh['ln']!.isNotEmpty
                              ? wh['ln']!
                              : wh['lv']!;
                          return DropdownMenuItem<String>(
                            value: wh['lv'],
                            child: Text(display),
                          );
                        }).toList(),
                        onChanged: (v) =>
                            setState(() => _selectedWarehouseLv = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // ── End warehouse picker ───────────────────────────────────
            // Submit button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (enabled && !isWriting)
                    ? () => _onSubmit(context)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: bgColor,
                  disabledBackgroundColor: const Color(0xFFD1D5DB),
                  foregroundColor: textColor,
                  disabledForegroundColor: const Color(0xFF6B7280),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isWriting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
