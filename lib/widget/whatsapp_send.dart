import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firestore_repository/table_repository.dart'; // subscribeToMapCollection
import '../global.dart'; // phoneCanonical62, diamondTextToList, mapTableContent, transactionStore, autheniumDecode
import 'driver_home_support.dart'; // resolveAppVid, resolveDriverCurlyTokens, writeNativeFields
import 'ftz_contact_picker.dart'; // chooseContactAndGetPhoneNumber
import 'panel_card_support.dart'; // parseTablePath, TablePath
import 'statistic_card_support.dart'; // filterByCharCodeEquality, resolveScreenTxTokens

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

  static void clearSentState(String scrName) {
    // Remove all entries whose key starts with the scrName prefix.
    // The key format is "$scrName::$resolvedSearch".
    _sentBySearch.removeWhere((key, _) => key.startsWith('$scrName::'));
  }

  @override
  State<WhatsAppSend> createState() => _WhatsAppSendState();
}

class _WhatsAppSendState extends State<WhatsAppSend> {
  List<String> _textArray = [];
  String _msgSubCode = '';

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
    _phoneFallback = (widget.component['phoneFallback'] ?? '')
        .toString()
        .trim();
    _allowContactPick =
        (widget.component['allowContactPick'] ?? '')
            .toString()
            .trim()
            .toUpperCase() ==
        'TRUE';
    // countryCode accepted but only 62 implemented (YAGNI -- same as
    // RECEIPT_DOC money param: "Only id implemented")
    _messageTemplate = (widget.component['messageTemplate'] ?? '')
        .toString()
        .trim();

    _logTable = (widget.component['logTable'] ?? '').toString().trim();
    _logSearch = (widget.component['logSearch'] ?? '').toString().trim();
    _logField = (widget.component['logField'] ?? '').toString().trim();
    _logValue = (widget.component['logValue'] ?? '').toString().trim();
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['messageTable'] ?? '')
        .toString()
        .trim();
    if (rawTable.isNotEmpty) {
      final TablePath tp = parseTablePath(rawTable);
      if (tp.tableDocId.isNotEmpty && appVid.isNotEmpty) {
        _msgSubCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
        subscribeToMapCollection(
          appVid,
          tp.tableDocId,
          tp.subColl,
          _msgSubCode,
        );
      }
    }
  }

  /// Length-guarded text slot accessor. Same pattern as coordination_signal_list.
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  /// Resolve the search key for the current invoice (used to key _sentBySearch).
  String get _sentKey {
    final String rawSearch = (widget.component['messageSearch'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return '${widget.scrName}::_default';
    final String decoded = autheniumDecode(rawSearch) ?? rawSearch;
    final String driverResolved = resolveDriverCurlyTokens(
      decoded,
      widget.scrName,
    );
    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
    final String fullyResolved = resolveScreenTxTokens(
      driverResolved,
      screenTx,
    );
    return '${widget.scrName}::$fullyResolved';
  }

  bool get _sent => WhatsAppSend._sentBySearch[_sentKey] == true;

  void _markSent() {
    WhatsAppSend._sentBySearch[_sentKey] = true;
    if (mounted) setState(() {});
  }

  /// Find the source doc for message template + phone field.
  Map<String, dynamic>? _findDoc() {
    if (_msgSubCode.isEmpty) return null;
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_msgSubCode] ?? const [],
    );
    if (docs.isEmpty) return null;

    final String rawSearch = (widget.component['messageSearch'] ?? '')
        .toString()
        .trim();
    if (rawSearch.isEmpty) return docs.first;

    // Same search pipeline as receipt_doc.dart L296-306
    final String decoded = autheniumDecode(rawSearch) ?? rawSearch;
    final String driverResolved = resolveDriverCurlyTokens(
      decoded,
      widget.scrName,
    );
    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;
    final String fullyResolved = resolveScreenTxTokens(
      driverResolved,
      screenTx,
    );

    final List<Map<String, dynamic>> matched = filterByCharCodeEquality(
      docs,
      fullyResolved,
      screenTx,
    );
    return matched.isNotEmpty ? matched.first : null;
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
      final String val = (transactionStore.state.screenTx[key] ?? '')
          .toString()
          .trim();
      if (val.isNotEmpty) return val;
    }
    return '';
  }

  void _openSheet() {
    final Map<String, dynamic>? doc = _findDoc();
    final String initialPhone = _resolvePhone(doc);
    final String initialMessage = doc != null && _messageTemplate.isNotEmpty
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

      final bool sent = _sent;

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
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
              backgroundColor: sent
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFF25D366),
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
    final String? picked = await chooseContactAndGetPhoneNumber(
      widget.contactLabel,
    );
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(widget.writeFailLabel)));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('WhatsApp error: $e')));
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Phone field
            Text(
              widget.phoneLabel,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
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
                        horizontal: 12,
                        vertical: 12,
                      ),
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
            Text(
              widget.messageLabel,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
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
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                    : const Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Colors.white,
                      ),
                label: Text(
                  widget.openWaLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _phoneValid
                      ? const Color(0xFF25D366)
                      : Colors.grey,
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
///   \n               -> literal newline
///
/// Missing fields -> empty string. Null doc -> empty for all fields.
String renderWhatsAppTemplate(String template, Map<String, dynamic> doc) {
  // 1. Process \n to real newlines
  String result = template.replaceAll(r'\n', '\n');

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
  result = result.replaceAllMapped(RegExp(r'\{\{(\w+)(?:\|(\w+))?\}\}'), (
    Match m,
  ) {
    final String field = m.group(1)!;
    final String? formatter = m.group(2);
    final dynamic val = doc[field];
    final String s = (val ?? '').toString();
    if (formatter == 'idr') return _formatIdrWa(s);
    return s;
  });

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

  final RegExpMatch? kv = RegExp(
    '''source\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s/>]+))''',
  ).firstMatch(attrs);
  if (kv != null) {
    return (kv.group(1) ?? kv.group(2) ?? kv.group(3) ?? '').trim();
  }

  // Shorthand: <LOOP li>
  final RegExpMatch? bare = RegExp(r'^(\w+)$').firstMatch(attrs);
  return bare != null ? bare.group(1)! : '';
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
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return integerPart;
  } catch (_) {
    return numberString;
  }
}
