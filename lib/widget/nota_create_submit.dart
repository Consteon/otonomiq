import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart'; // getNowMillisecondFromEpoch, internetConnected
import '../global.dart'; // transactionStore, routeStack, gotoRoute, routeExist, errorReport, diamondTextToList, autheniumDecode, emptyString
import '../global2.dart'; // txfController, txfControllerCheck, addToTxfController, generateAutoNumber, WidgetUpdateController
import '../redux/screen_transaction.dart'; // UpdateScreenTxAction, ScreenTransaction
import 'admin_create_task_support.dart';
import 'admin_home_support.dart'; // AdminTierColors
import 'do_chain.dart';
import 'driver_home_support.dart'; // createNativeDocAutoId, resolveAppVid, stripRouteWrapper
import 'panel_card_support.dart'; // parseTablePath
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

  @override
  void initState() {
    super.initState();
    _parseText();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Text slot accessors:
  ///  [0] "Buat Nota"           (enabled label)
  ///  [1] "TOTAL"               (total label)
  ///  [2] "Lengkapi item dulu"  (disabled / empty-items / unpriced label)
  ///  [3] "Gagal membuat nota"  (error snackbar)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'walkin_pos').toString().trim();

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

      // 1. Read draft + validate
      final List<DraftItem> draft = AdminCreateTaskSupport.getDraft(_wizardKey);
      final List<Map<String, dynamic>> liArray =
          AdminCreateTaskSupport.draftToLiArray(draft);

      if (liArray.isEmpty) {
        if (context.mounted) {
          _showSnackBar(context, _t(2, 'Lengkapi item dulu'));
        }
        return;
      }

      // 1b. Price guard (spec section 1): a zero-priced line can never be
      //     committed. The button is already disabled when this is true, but
      //     re-check here to close any race (draft mutated mid-await).
      if (!_allLinesPriced(draft)) {
        if (context.mounted) {
          _showSnackBar(context, _t(2, 'Lengkapi item dulu'));
        }
        return;
      }

      // 2. Savesend mode gate
      final bool savesendMode = AdminCreateTaskSupport.isSavesendMode(
        widget.component['action'],
      );

      if (!savesendMode) {
        // Nota requires savesend mode (counter-based nno). Non-savesend is a
        // config error -- fail gracefully.
        if (context.mounted) {
          _showSnackBar(context, _t(3, 'Gagal membuat nota'));
        }
        return;
      }

      // 3. Re-seed the nno slot to empty (anti-stale, same as task_create_submit)
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

      // 7. Read buyer (by) from txfController position
      final int buyerPos =
          int.tryParse(
            (widget.component['buyerPosition'] ?? '').toString().trim(),
          ) ??
          12;
      txfControllerCheck(widget.scrName, buyerPos);
      final String by =
          txfController[widget.scrName]?[buyerPos]?.finalData ?? '';
      // Normalize: emptyString marker ('--') -> empty string
      final String byClean = (by == emptyString || by == 'null')
          ? ''
          : by.trim();

      // 8. Read payment method (bym) from txfController position
      final int paymentPos =
          int.tryParse(
            (widget.component['paymentPosition'] ?? '').toString().trim(),
          ) ??
          1;
      txfControllerCheck(widget.scrName, paymentPos);
      final String bymRaw =
          txfController[widget.scrName]?[paymentPos]?.finalData ?? '';
      final String bymClean = (bymRaw == emptyString || bymRaw == 'null')
          ? ''
          : bymRaw.trim();
      // Map display value to stored value
      final String bym;
      if (bymClean == 'Tunai' || bymClean == 'tunai') {
        bym = 'tunai';
      } else if (bymClean == 'Transfer' || bymClean == 'transfer') {
        bym = 'transfer';
      } else {
        bym = bymClean.toLowerCase();
      }

      // 9. Session fields
      final String cv = (screenTx['#VID'] ?? '').toString().trim();
      final String cn = (screenTx['#NAME'] ?? '').toString().trim();

      // 10. Time
      final int nowMs = getNowMillisecondFromEpoch();
      final String ts = AdminCreateTaskSupport.formatWibTimestamp(nowMs);

      // 11. gl (origin warehouse/depo -- baked literal from component param)
      final String gl = (widget.component['gl'] ?? '').toString().trim();

      // 12. src (source identifier -- baked literal from component param)
      final String src = (widget.component['src'] ?? 'walkin')
          .toString()
          .trim();

      // 13. tot (total Rp = sum of all li[].sub)
      final TaskTotals totals = AdminCreateTaskSupport.computeTotals(draft);
      final int tot = totals.totalSalePrice;

      // 14. tableVid
      final String tableVid =
          (widget.component['vidtable'] ?? '').toString().trim().isNotEmpty
          ? (widget.component['vidtable'] ?? '').toString().trim()
          : parseTablePath(
              (widget.component['table'] ?? '').toString().trim(),
            ).tableDocId;

      // 15. Assemble nota doc
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
          );

      // 16. Write native auto-id doc
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

      // 17. Inject {nno} token for the destination page (W3).
      // Uses bare screenTx key 'nno' -- resolveDriverCurlyTokens default case
      // resolves {nno} from screenTx['nno'].
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'nno': nno})),
      );

      // 18. Clear draft
      AdminCreateTaskSupport.clearDraft(_wizardKey);

      // 19. Navigate (chain-aware)
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
      final bool allPriced = _allLinesPriced(draft);

      final TaskTotals totals = AdminCreateTaskSupport.computeTotals(draft);
      final int tot = totals.totalSalePrice;

      // Enabled only when the draft has items AND every line is priced
      // (spec section 1: no zero-priced line may be committed).
      final bool enabled = hasItems && allPriced;
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
                      AdminCreateTaskSupport.formatRupiah(tot),
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
