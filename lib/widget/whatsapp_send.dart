import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // phoneCanonical62, diamondTextToList, mapTableContent, transactionStore, autheniumDecode
import 'driver_home_support.dart'; // resolveAppVid, resolveDriverCurlyTokens, resolveRowCurlyTokens, writeNativeFields
import 'ftz_contact_picker.dart'; // chooseContactAndGetPhoneNumber
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'statistic_card_support.dart'; // filterByCharCodeEquality, resolveScreenTxTokens
import '../screen_session.dart';

/// WHATSAPP_SEND -- generic WhatsApp message sender with editable bottom sheet.
///
/// Reads a doc by search, renders a message template, normalizes the phone
/// number, and opens wa.me. Optionally writes a marker field after successful
/// launch.
///
/// text[] slots (spec defines 0-6; plan adds 7-8 for completeness):
///   0: main button label          (default "Kirim WhatsApp")
///   1: phone number label         (default "Nomor WhatsApp")
///   2: contact pick button label  (default "Pilih Kontak")
///   3: message label              (default "Pesan")
///   4: open-WA button label       (default "Buka WhatsApp")
///   5: invalid number error       (default "Nomor tidak valid")
///   6: sent badge                 (default "Terkirim WA")
///   7: write fail error           (default "Gagal menyimpan")
///   8: sheet title                (default "Kirim WhatsApp")
class WhatsAppSend extends StatefulWidget {
  const WhatsAppSend({
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

  // ── Per-invoice sent state (C3 fix) ──────────────────────────────
  // Keyed by resolved messageSearch string so the same cached widget
  // instance distinguishes invoice A from invoice B. Cleared on route
  // change via clearSentState(scrName) called from buildPage(clear:true)
  // in ui_component.dart (same pattern as ApproverStickyBar.clearConfigs,
  // CustodyCountList.clearCountStore, etc.).
  //
  // Convention #5: static on the widget class, not global.dart.
  // Convention #4: cleared per-scrName on route change.
  static final Map<String, bool> _sentBySearch = {};

  static void registerScreenSession() {
    ScreenSession.ensure(
      'WhatsAppSend.sentState',
      WhatsAppSend.clearSentState,
    );
  }

  static void clearSentState(String scrName) {
    // Remove all entries whose key starts with the scrName prefix.
    // The key format is "$scrName::$resolvedSearch".
    _sentBySearch.removeWhere((key, _) => key.startsWith('$scrName::'));
  }

  /// Whether the OPTIONAL `phoneTable` + `phoneSearch` pair is usable
  /// (spec (3) section 6b-2.1 rule 1).
  ///
  /// BOTH must be non-empty. Either one empty falls to rule 2 -- read
  /// `phoneField` from the `messageTable` doc, which is today's behaviour and
  /// what every already-deployed config (WalkInNota, DeliveryInvoice) gets.
  /// Half-configured is NOT "try anyway": a `phoneTable` with no `phoneSearch`
  /// would match the first document in the collection, i.e. an arbitrary
  /// customer's phone number.
  ///
  /// Pure + static so a test can kill either conjunct; the read path that uses
  /// it lives inside the State and is not reachable from `flutter_test`.
  static bool phoneLookupConfigured(dynamic component) {
    final String table = (component['phoneTable'] ?? '').toString().trim();
    final String search = (component['phoneSearch'] ?? '').toString().trim();
    return table.isNotEmpty && search.isNotEmpty;
  }

  @override
  State<WhatsAppSend> createState() => _WhatsAppSendState();
}

class _WhatsAppSendState extends State<WhatsAppSend> {
  List<String> _textArray = [];
  String _msgSubCode = '';

  /// vid-scoped subscription code for the OPTIONAL `phoneTable` collection.
  /// Empty when `phoneTable`/`phoneSearch` are not both configured.
  /// Format is identical to [_msgSubCode] -- `'$appVid/$tableDocId/$subColl'` --
  /// because `subscribeToMapCollection` uses this string as BOTH the
  /// `_mapSubscribed` dedup key AND the `mapTableContent` storage key, and vid
  /// is not otherwise in it. Instance field (recreated per widget), so no clear
  /// hook is needed.
  String _phoneSubCode = '';

  // Parsed config
  String _phoneField = '';
  String _phoneFallback = '';
  bool _allowContactPick = false;
  String _messageTemplate = '';
  String _logTable = '';
  String _logSearch = '';
  String _logField = '';
  String _logValue = '';

  @override
  void initState() {
    super.initState();
    WhatsAppSend.registerScreenSession();
    _parseConfig();
    _subscribe();
  }

  void _parseConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
    // diamondTextToList('') returns [''] not [] -- collapse it
    if (_textArray.length == 1 && _textArray.first.isEmpty) _textArray = [];

    _phoneField = (widget.component['phoneField'] ?? '').toString().trim();
    _phoneFallback =
        (widget.component['phoneFallback'] ?? '').toString().trim();
    _allowContactPick =
        (widget.component['allowContactPick'] ?? '')
            .toString()
            .trim()
            .toUpperCase() ==
        'TRUE';
    // countryCode accepted but only 62 implemented (YAGNI -- same as
    // RECEIPT_DOC money param: "Only id implemented")
    _messageTemplate =
        (widget.component['messageTemplate'] ?? '').toString().trim();

    _logTable = (widget.component['logTable'] ?? '').toString().trim();
    _logSearch = (widget.component['logSearch'] ?? '').toString().trim();
    _logField = (widget.component['logField'] ?? '').toString().trim();
    _logValue = (widget.component['logValue'] ?? '').toString().trim();
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable =
        (widget.component['messageTable'] ?? '').toString().trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty && appVid.isNotEmpty) {
        _msgSubCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(
            appVid, tp.tableDocId, tp.subColl, _msgSubCode);
      }
    }

    // Optional second collection: where the phone number lives (spec (3)
    // section 6b-2.1). Gated on BOTH params, so a half-configured component
    // opens no stream at all. When phoneTable == messageTable the two codes
    // are equal and subscribeToMapCollection dedups via _mapSubscribed --
    // harmless, one stream.
    if (WhatsAppSend.phoneLookupConfigured(widget.component)) {
      final String rawPhoneTable =
          (widget.component['phoneTable'] ?? '').toString().trim();
      final TablePath tp = parseTablePath(rawPhoneTable);
      if (tp.tableDocId.isNotEmpty && appVid.isNotEmpty) {
        _phoneSubCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(
            appVid, tp.tableDocId, tp.subColl, _phoneSubCode);
      }
    }
  }

  /// Length-guarded text slot accessor. Same pattern as coordination_signal_list.
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  /// Resolve the search key for the current invoice (used to key _sentBySearch).
  String get _sentKey {
    final String rawSearch =
        (widget.component['messageSearch'] ?? '').toString().trim();
    if (rawSearch.isEmpty) return '${widget.scrName}::_default';
    // Byte-identical to the previous inline chain (row == null skips step 1,
    // and steps 2/3 are no-ops on a token-free string) -- routed through the
    // shared resolver so the sent-key and the doc lookup can never disagree
    // about which invoice is "this one".
    final String fullyResolved = resolveSearchWithRow(
      rawSearch,
      null,
      widget.scrName,
      transactionStore.state.screenTx,
    );
    return '${widget.scrName}::$fullyResolved';
  }

  bool get _sent => WhatsAppSend._sentBySearch[_sentKey] == true;

  void _markSent() {
    WhatsAppSend._sentBySearch[_sentKey] = true;
    if (mounted) setState(() {});
  }

  /// One doc lookup, two callers. Same pipeline as receipt_doc.dart L296-306,
  /// with the search resolved by [resolveSearchWithRow].
  ///
  /// [subCode]    -- vid-scoped `mapTableContent` key.
  /// [rawSearch]  -- `field◼value` DSL; empty means "first doc in the
  ///                 collection", which is the pre-existing messageSearch-less
  ///                 behaviour. The phone caller never reaches that branch --
  ///                 it requires a non-empty phoneSearch first.
  /// [rowContext] -- when non-null, `{field}` tokens resolve from THIS map
  ///                 before any session/screenTx source.
  Map<String, dynamic>? _findDocIn({
    required String subCode,
    required String rawSearch,
    Map<String, dynamic>? rowContext,
  }) {
    if (subCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs =
        List<Map<String, dynamic>>.from(mapTableContent[subCode] ?? const []);
    if (docs.isEmpty) return null;
    if (rawSearch.isEmpty) return docs.first;

    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
    final String fullyResolved =
        resolveSearchWithRow(rawSearch, rowContext, widget.scrName, screenTx);
    final List<Map<String, dynamic>> matched =
        filterByCharCodeEquality(docs, fullyResolved, screenTx);
    return matched.isNotEmpty ? matched.first : null;
  }

  /// Find the MAIN doc: source for the message template, and the phoneField
  /// fallback. Unchanged behaviour -- no row context.
  Map<String, dynamic>? _findDoc() => _findDocIn(
        subCode: _msgSubCode,
        rawSearch:
            (widget.component['messageSearch'] ?? '').toString().trim(),
      );

  /// Find the doc that holds the phone number, when `phoneTable` +
  /// `phoneSearch` are configured (spec (3) section 6b-2.1 rule 1).
  ///
  /// Returns null -- meaning "fall back to rule 2, read phoneField from the
  /// main doc" -- for every not-configured / not-found case.
  ///
  /// [mainDoc] is REQUIRED to be non-null, mirroring
  /// `writeRouteParamsFromRow`'s own `if (row == null) return;`. Without that
  /// guard a `phoneSearch` of `lv◼{kl}` with a missing main doc falls through
  /// to a STALE bare screenTx `kl` -- and `kl` really is dispatched as a bare
  /// key by this wizard (docs/admin_runtime/admin-create-task-op1screen.md:22,
  /// "P1 deposits kl (customer id) via routeParams"). The failure that guard
  /// prevents is prefilling the PREVIOUS customer's phone number next to an
  /// empty message; skipping the lookup instead leaves the number blank, which
  /// the admin cannot mistake for correct.
  Map<String, dynamic>? _findPhoneDoc(Map<String, dynamic>? mainDoc) {
    if (!WhatsAppSend.phoneLookupConfigured(widget.component)) return null;
    if (_phoneSubCode.isEmpty) return null;
    if (mainDoc == null) return null;
    return _findDocIn(
      subCode: _phoneSubCode,
      rawSearch: (widget.component['phoneSearch'] ?? '').toString().trim(),
      rowContext: mainDoc,
    );
  }

  /// Resolve initial phone from doc phoneField + token fallback.
  String _resolvePhone(Map<String, dynamic>? doc) {
    // Primary: doc field
    if (doc != null && _phoneField.isNotEmpty) {
      final String val = (doc[_phoneField] ?? '').toString().trim();
      if (val.isNotEmpty) return val;
    }
    // Fallback: resolve {token} from screenTx
    if (_phoneFallback.isNotEmpty) {
      String key = _phoneFallback;
      if (key.startsWith('{') && key.endsWith('}')) {
        key = key.substring(1, key.length - 1);
      }
      final String val =
          (transactionStore.state.screenTx[key] ?? '').toString().trim();
      if (val.isNotEmpty) return val;
    }
    return '';
  }

  void _openSheet() {
    final Map<String, dynamic>? doc = _findDoc();
    // Rule 1 (phoneTable+phoneSearch) > rule 2 (main doc) > rule 3
    // (phoneFallback / manual), spec (3) section 6b-2.1. A configured lookup
    // that finds nothing degrades to rule 2 rather than to "no number": for a
    // `task` main doc that simply reads an absent `hpic` and lands on rule 3,
    // which is exactly today's behaviour.
    final Map<String, dynamic>? phoneDoc = _findPhoneDoc(doc);
    final String initialPhone = _resolvePhone(phoneDoc ?? doc);
    final String initialMessage =
        doc != null && _messageTemplate.isNotEmpty
            ? renderWhatsAppTemplate(_messageTemplate, doc)
            : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _WhatsAppSheet(
        initialPhone: initialPhone,
        initialMessage: initialMessage,
        allowContactPick: _allowContactPick,
        phoneLabel: _t(1, 'Nomor WhatsApp'),
        contactLabel: _t(2, 'Pilih Kontak'),
        messageLabel: _t(3, 'Pesan'),
        openWaLabel: _t(4, 'Buka WhatsApp'),
        errorLabel: _t(5, 'Nomor tidak valid'),
        writeFailLabel: _t(7, 'Gagal menyimpan'),
        sheetTitle: _t(8, 'Kirim WhatsApp'),
        logTable: _logTable,
        logSearch: _logSearch,
        logField: _logField,
        logValue: _logValue,
        component: widget.component,
        scrName: widget.scrName,
        onSent: _markSent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Touch reactive dep so Obx repaints when doc data arrives
      mapTableContent[_msgSubCode];
      // Second reactive dep: the OPTIONAL phoneTable stream (spec (3) section
      // 6b-2.1). Without it an arriving customer doc triggers no repaint.
      // `mapTableContent['']` is a harmless null read when the pair is not
      // configured, so this is byte-neutral for every already-deployed config.
      mapTableContent[_phoneSubCode];

      final bool sent = _sent;

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: sent ? null : _openSheet,
            icon: Icon(
              sent ? Icons.check_circle_outline : Icons.send_outlined,
              size: 18,
              color: sent ? Colors.green : Colors.white,
            ),
            label: Text(
              sent ? _t(6, 'Terkirim WA') : _t(0, 'Kirim WhatsApp'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: sent ? Colors.green : Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  sent ? const Color(0xFFE8F5E9) : const Color(0xFF25D366),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ),
      );
    });
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────

class _WhatsAppSheet extends StatefulWidget {
  const _WhatsAppSheet({
    required this.initialPhone,
    required this.initialMessage,
    required this.allowContactPick,
    required this.phoneLabel,
    required this.contactLabel,
    required this.messageLabel,
    required this.openWaLabel,
    required this.errorLabel,
    required this.writeFailLabel,
    required this.sheetTitle,
    required this.logTable,
    required this.logSearch,
    required this.logField,
    required this.logValue,
    required this.component,
    required this.scrName,
    required this.onSent,
  });

  final String initialPhone;
  final String initialMessage;
  final bool allowContactPick;
  final String phoneLabel;
  final String contactLabel;
  final String messageLabel;
  final String openWaLabel;
  final String errorLabel;
  final String writeFailLabel;
  final String sheetTitle;
  final String logTable;
  final String logSearch;
  final String logField;
  final String logValue;
  final dynamic component;
  final String scrName;
  final VoidCallback onSent;

  @override
  State<_WhatsAppSheet> createState() => _WhatsAppSheetState();
}

class _WhatsAppSheetState extends State<_WhatsAppSheet> {
  late TextEditingController _phoneCtrl;
  late TextEditingController _msgCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
    _msgCtrl = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  String get _normalized => phoneCanonical62(_phoneCtrl.text.trim());
  bool get _phoneValid => _normalized.isNotEmpty;

  Future<void> _pickContact() async {
    final String? picked =
        await chooseContactAndGetPhoneNumber(widget.contactLabel);
    if (picked != null && picked.isNotEmpty) {
      _phoneCtrl.text = picked;
      setState(() {});
    }
  }

  Future<void> _launch() async {
    if (!_phoneValid || _busy) return;
    setState(() => _busy = true);

    try {
      // 1. Build URL and launch FIRST (C4 fix: launch before marker)
      final String phone = _normalized;
      final String message = _msgCtrl.text;
      final String url =
          'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';

      final bool launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak bisa membuka WhatsApp')),
          );
        }
        // Keep sheet open, do NOT write marker, do NOT badge
        return;
      }

      // 2. Launch succeeded -- write marker (online-only, non-blocking)
      if (widget.logTable.isNotEmpty &&
          widget.logSearch.isNotEmpty &&
          widget.logField.isNotEmpty &&
          widget.logValue.isNotEmpty) {
        final bool ok = await writeNativeFields(
          component: widget.component,
          rawTable: widget.logTable,
          rawSearch: widget.logSearch,
          scrName: widget.scrName,
          patch: {widget.logField: widget.logValue},
        );
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.writeFailLabel)),
          );
          // Marker write failed but WA already opened -- still mark sent so
          // the admin sees the badge for THIS session. Nothing is queued:
          // writeNativeFields is online-only and returns false on 0-match /
          // >1-match, so `iv` stays empty and the coordination tier KEEPS
          // showing the signal. That is deliberate -- the admin will see it
          // again and retry. A duplicate WhatsApp message beats a lost
          // invoice.
        }
      }

      // 3. Pop sheet and notify parent
      widget.onSent();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Launch threw -- keep sheet open, do NOT write marker, do NOT badge
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WhatsApp error: $e')),
        );
      }
    } finally {
      // W1 fix: always reset _busy so button never deadlocks
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Title
            Text(
              widget.sheetTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Phone field
            Text(widget.phoneLabel,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '08xxxxxxxxxx',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      errorText:
                          _phoneCtrl.text.trim().isNotEmpty && !_phoneValid
                              ? widget.errorLabel
                              : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (widget.allowContactPick) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _pickContact,
                      icon: const Icon(Icons.contacts_outlined, size: 16),
                      label: Text(
                        widget.contactLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // Message field
            Text(widget.messageLabel,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Flexible(
              child: TextField(
                controller: _msgCtrl,
                maxLines: null,
                minLines: 5,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Launch button
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _phoneValid && !_busy ? _launch : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.open_in_new,
                        size: 16, color: Colors.white),
                label: Text(
                  widget.openWaLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _phoneValid ? const Color(0xFF25D366) : Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Template renderer (top-level, exported for tests) ─────────────────

/// Render a WhatsApp message template against a document map.
///
/// Syntax mirrors template_printer.dart's _interpolate dialect (same authoring
/// language for sheet operators) but produces plain String, not ESC/POS bytes.
///
///   {{field}}        -> doc[field]
///   {{field|idr}}    -> dot-thousands formatted (Indonesian locale)
///   `<LOOP source='li'>...{{item.x}}...</LOOP>` -> iterate doc['li'] array
///   `<IFSET source='tot'>...</IFSET>` -> emit the body ONLY when doc['tot']
///                      is SET (see [_ifSetIsSet]); otherwise the whole block
///                      disappears, literal separator text included
///   \n               -> literal newline
///
/// Missing fields -> empty string. Null doc -> empty for all fields.
String renderWhatsAppTemplate(String template, Map<String, dynamic> doc) {
  // 1. Process \n to real newlines
  String result = template.replaceAll(r'\n', '\n');

  // 1b. Process <IFSET source='x'>...</IFSET> conditional blocks.
  //
  // RUNS BEFORE THE <LOOP> PASS ON PURPOSE. The <LOOP> pass substitutes
  // {{item.*}} VALUES into `result`, so while <IFSET> ran after it, a catalog
  // item whose name contained a literal <IFSET ...>...</IFSET> was EXECUTED as
  // control flow and could delete itself from the customer's message with no
  // error anywhere. Running first means an injected tag leaks VERBATIM into the
  // editable preview sheet, where the admin can see it -- visible garbage beats
  // silent loss. (Phase-2 code review, Warning W1.)
  //
  // The SAME reason keeps it above the {{field}} pass, and it is the only
  // reason: whatever an earlier pass substitutes into `result` becomes control
  // flow for a later one, so <IFSET> must precede BOTH substitution passes --
  // not just <LOOP>.
  //
  // Do NOT justify the placement by "a KEPT body still needs its {{tot|idr}}
  // substituted". A kept body does still get it below, but that holds under
  // EVERY ordering: kept- and dropped-body output is byte-identical with this
  // pass at 1b, at 2b, and after the {{field}} pass (all three measured). That
  // claim would wave 2b back in -- the position this move just removed.
  //
  // Control structure now comes only from the TEMPLATE, never from doc data,
  // for BOTH tags and for both top-level and item fields.
  //
  // The attribute grammar is _loopSource's, called verbatim -- one parser for
  // both tags, so a template that works on <LOOP> works here. That includes
  // the `<IFSET tot>` bare shorthand, inherited rather than designed.
  //
  // NESTING: <IFSET> inside a <LOOP> body, and <LOOP> inside an <IFSET> body,
  // both produce the same output they did before this pass was moved (verified
  // by running both orders over each shape). What is genuinely undefined is
  // INTERLEAVED tags -- `<IFSET ...>A<LOOP ...>B</IFSET>C</LOOP>` - because the
  // lazy `*?` here pairs the FIRST </IFSET> with the FIRST <IFSET>. Do not
  // interleave.
  result = result.replaceAllMapped(
    RegExp(r'<IFSET([^>]*)>([\s\S]*?)</IFSET>', multiLine: true),
    (Match m) {
      final String field = _loopSource(m.group(1)!);
      // No source= (or an empty one) -> drop the block. Fail-closed: a
      // mis-typed tag prints nothing rather than an unconditional line.
      if (field.isEmpty) return '';
      return _ifSetIsSet(doc[field]) ? m.group(2)! : '';
    },
  );

  // 2. Process <LOOP ...>...</LOOP> blocks
  result = result.replaceAllMapped(
    RegExp(r'<LOOP([^>]*)>([\s\S]*?)</LOOP>', multiLine: true),
    (Match m) {
      final String arrayField = _loopSource(m.group(1)!);
      final String body = m.group(2)!;
      if (arrayField.isEmpty) return '';
      final dynamic rawList = doc[arrayField];
      if (rawList == null || rawList is! List || rawList.isEmpty) return '';
      final StringBuffer buf = StringBuffer();
      for (final dynamic item in rawList) {
        String line = body;
        // Replace {{item.field}} and {{item.field|idr}}
        line = line.replaceAllMapped(
          RegExp(r'\{\{item\.(\w+)(?:\|(\w+))?\}\}'),
          (Match im) {
            final String field = im.group(1)!;
            final String? formatter = im.group(2);
            final dynamic val = item is Map ? item[field] : '';
            final String s = (val ?? '').toString();
            if (formatter == 'idr') return _formatIdrWa(s);
            return s;
          },
        );
        buf.write(line);
      }
      return buf.toString();
    },
  );

  // 3. Replace {{field}} and {{field|idr}} (non-item, top-level)
  result = result.replaceAllMapped(
    RegExp(r'\{\{(\w+)(?:\|(\w+))?\}\}'),
    (Match m) {
      final String field = m.group(1)!;
      final String? formatter = m.group(2);
      final dynamic val = doc[field];
      final String s = (val ?? '').toString();
      if (formatter == 'idr') return _formatIdrWa(s);
      return s;
    },
  );

  return result;
}

/// Resolve the array field name from a `<LOOP …>` tag's attribute string.
///
/// The authoring dialect is template_printer.dart's, whose `_parseAttributes`
/// (L517) accepts `source='li'`, `source="li"` and bare `source=li`. Sheet
/// operators write the PRN form, so that is what must work here — an earlier
/// build only matched the shorthand `<LOOP li>` and rendered the raw tag into
/// the customer's WhatsApp message.
///
/// The `<LOOP li>` shorthand is still accepted; it costs one alternation and
/// keeps any template already written against the dev spec working.
String _loopSource(String attributeString) {
  final String attrs = attributeString.trim();
  if (attrs.isEmpty) return '';

  final RegExpMatch? kv =
      RegExp('''source\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s/>]+))''')
          .firstMatch(attrs);
  if (kv != null) {
    return (kv.group(1) ?? kv.group(2) ?? kv.group(3) ?? '').trim();
  }

  // Shorthand: <LOOP li>
  final RegExpMatch? bare = RegExp(r'^(\w+)$').firstMatch(attrs);
  return bare != null ? bare.group(1)! : '';
}

/// Whether an `<IFSET source='x'>` field counts as SET.
///
/// Three ways to be UNSET, all of which drop the block:
///   * `null`                    -- the key is absent from the doc;
///   * blank after `trim()`      -- `''`, `'   '`;
///   * NUMERICALLY ZERO          -- `0`, `'0'`, `0.0`, `'0.00'`.
///
/// The third clause is the reason this tag exists: a pickup-only task
/// (purchase/refill only) has `tot == 0`, and `*Perkiraan total: Rp 0*` is not
/// something to send a customer. One template serves every task on the
/// destination page, so the operator cannot solve it by dropping the cell --
/// that would strip the total from priced tasks too.
///
/// The ORDER matters. Parse first, and only THEN test for zero: a non-numeric
/// value like `LUNAS` yields `num.tryParse == null`, falls through both zero
/// clauses and stays SET. Do NOT reach for `coerceNum` here -- it maps an
/// unparseable String to 0, which would silently delete a `<IFSET source='st'>`
/// block whose value is `LUNAS`.
///
/// Firestore is dynamic by design (Convention #7): the same field arrives as
/// int, double or String depending on whether it was written by this app or
/// typed into a sheet, which is why the numeric test runs on the STRING form.
bool _ifSetIsSet(dynamic value) {
  if (value == null) return false;
  final String s = value.toString().trim();
  if (s.isEmpty) return false;
  final num? parsed = num.tryParse(s);
  return !(parsed != null && parsed == 0);
}

/// Format a numeric string with dot-separated thousands (Indonesian locale).
/// Mirrors receipt_doc.dart formatThousands / template_printer _formatIdr
/// but standalone -- no ESC/POS dependency.
// ponytail: mirrors _formatIdr; merge when a shared format lib exists
String _formatIdrWa(String numberString) {
  try {
    // Unparseable input (e.g. a tenant sheet that already stores "1.250.000")
    // passes through UNCHANGED. Falling back to 0.0 here would have sent the
    // customer "*TOTAL: 0*" with no exception raised. Deliberately NOT
    // stripping dots and re-parsing -- that guesses at the separator and would
    // misread a genuine decimal.
    final double? number = double.tryParse(numberString.replaceAll(',', ''));
    if (number == null) return numberString;
    final String integerPart = number.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return integerPart;
  } catch (_) {
    return numberString;
  }
}

// ── Search resolution (top-level, exported for tests) ─────────────────

/// Resolve a `field◼value` search DSL, main-doc fields FIRST.
///
/// Spec (3) section 6b-2.1: `phoneSearch` must be able to point at a field of
/// the MAIN doc -- `lv◼{kl}` where `kl` is the customer FK ON THE TASK. That is
/// the only genuinely new step; the rest is the chain `_findDoc` has always
/// used, factored out so the message search and the phone search can never
/// drift apart.
///
///   0. [autheniumDecode]           -- server sends ◼/⭘ as _25FC_/_2B58_.
///   1. [resolveRowCurlyTokens]     -- `{kl}` -> row['kl'].            (NEW)
///   2. [resolveDriverCurlyTokens]  -- session tokens ({tnm}, {today}, …).
///   3. [resolveScreenTxTokens]     -- bare screenTx keys (route params).
///
/// Steps 2 and 3 run only while a `{` remains. That is behaviour-preserving --
/// both helpers are no-ops on a `{`-free string -- and it keeps the common
/// fully-row-resolved case from touching the GetX driver state at all. It is
/// also the same short-circuit shape as `writeRouteParamsFromRow`.
///
/// `row == null` (or an empty map) reproduces today's message-search chain
/// BYTE FOR BYTE.
///
/// Unresolvable tokens are left LITERAL on purpose: `filterByCharCodeEquality`
/// is fail-closed on a value still containing `{` (returns no match), so a
/// half-resolved search can never silently match the wrong document.
///
/// KNOWN CEILING: [resolveRowCurlyTokens] leaves a token literal when the row
/// value is present but EMPTY, so step 3 can still fill it from a stale bare
/// key. That is the shared helper's documented contract (writeRouteParamsFromRow
/// depends on it) and is not changed here. In practice `assembleTaskDoc` always
/// writes a non-empty `kl`.
///
/// Pure over its arguments except for the GetX read inside
/// [resolveDriverCurlyTokens]; [screenTx] is passed in rather than read, so the
/// row-resolved path is directly unit-testable.
String resolveSearchWithRow(
  String rawSearch,
  Map<String, dynamic>? row,
  String scrName,
  Map<String, dynamic> screenTx,
) {
  String resolved = autheniumDecode(rawSearch) ?? rawSearch;
  if (row != null && row.isNotEmpty) {
    resolved = resolveRowCurlyTokens(resolved, row);
  }
  if (resolved.contains('{')) {
    resolved = resolveDriverCurlyTokens(resolved, scrName);
  }
  if (resolved.contains('{')) {
    resolved = resolveScreenTxTokens(resolved, screenTx);
  }
  return resolved;
}
