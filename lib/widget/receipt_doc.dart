import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';

// ── Pure helpers (exported for tests) ─────────────────────────────────

/// Format an integer with dot-separated thousands (Indonesian locale).
///
/// Examples: 0 -> "0", 71000 -> "71.000", 1250000 -> "1.250.000",
/// -5000 -> "-5.000". Same grouping loop as AdminCreateTaskSupport.formatRupiah
/// but without the "Rp " prefix.
String formatThousands(int amount) {
  if (amount == 0) return '0';
  final bool negative = amount < 0;
  final String raw = amount.abs().toString();
  final StringBuffer buf = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buf.write('.');
    buf.write(raw[i]);
  }
  return negative ? '-${buf.toString()}' : buf.toString();
}

/// Format epoch-ms as "dd Mon yyyy HH:mm" in WIB (UTC+7).
///
/// Example: 1783481940000 -> "08 Jul 2026 09:39".
String formatReceiptDate(int epochMs) {
  const int wibOffsetMs = 25200000; // UTC+7
  const List<String> months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final DateTime dt = DateTime.fromMillisecondsSinceEpoch(
    epochMs + wibOffsetMs,
    isUtc: true,
  );
  final String d = dt.day.toString().padLeft(2, '0');
  final String mon = months[dt.month];
  final String y = dt.year.toString();
  final String h = dt.hour.toString().padLeft(2, '0');
  final String mi = dt.minute.toString().padLeft(2, '0');
  return '$d $mon $y $h:$mi';
}

// ── View model (pure, testable) ───────────────────────────────────────

class ReceiptLine {
  final String name;
  final int qty;
  final int price;
  final int sub;
  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.price,
    required this.sub,
  });
}

class ReceiptData {
  final String no;
  final String dateFormatted;
  final String buyer;
  final String payment;
  final String status;
  final int total;
  final String gl;
  final List<ReceiptLine> lines;
  const ReceiptData({
    required this.no,
    required this.dateFormatted,
    required this.buyer,
    required this.payment,
    required this.status,
    required this.total,
    required this.gl,
    required this.lines,
  });
}

/// Extract a [ReceiptData] view model from a raw nota doc using config-driven
/// field names. Pure function -- no Firestore, no globals -- unit-testable.
///
/// [fieldConfig] keys: noField, buyerField, buyerEmpty, dateField,
/// paymentField, statusField, totalField, linesField, lineNameField,
/// lineQtyField, linePriceField, lineSubField.
ReceiptData extractReceiptData(
  Map<String, dynamic> doc,
  Map<String, String> fieldConfig,
) {
  final String noField = fieldConfig['noField'] ?? '';
  final String buyerField = fieldConfig['buyerField'] ?? '';
  final String buyerEmpty = fieldConfig['buyerEmpty'] ?? '';
  final String dateField = fieldConfig['dateField'] ?? '';
  final String paymentField = fieldConfig['paymentField'] ?? '';
  final String statusField = fieldConfig['statusField'] ?? '';
  final String totalField = fieldConfig['totalField'] ?? '';
  final String linesField = fieldConfig['linesField'] ?? '';
  final String lineNameField = fieldConfig['lineNameField'] ?? '';
  final String lineQtyField = fieldConfig['lineQtyField'] ?? '';
  final String linePriceField = fieldConfig['linePriceField'] ?? '';
  final String lineSubField = fieldConfig['lineSubField'] ?? '';

  // Scalar fields
  final String noVal = (doc[noField] ?? '').toString();
  final String rawBuyer = (doc[buyerField] ?? '').toString().trim();
  final String buyer = rawBuyer.isEmpty ? buyerEmpty : rawBuyer;
  final String payment = (doc[paymentField] ?? '').toString();
  final String status = (doc[statusField] ?? '').toString();
  // `gl` (depo id) is an intentionally fixed field name — it is the value the
  // `{gl}` header-search token resolves to (nota doc -> stock_location lookup).
  // Not config-driven like the scalar fields; generalize only if a future nota
  // driver (src:delivery) needs a different depo field.
  final String gl = (doc['gl'] ?? '').toString();

  // Date: field `t` (epoch-ms) -> "08 Jul 2026 09:39". Tolerant: an int or a
  // numeric string is formatted; a non-numeric preformatted string (e.g. `ts`
  // = "2026-07-08 09:39") is shown verbatim. Never render the 1970 epoch from a
  // failed parse.
  final dynamic rawDate = doc[dateField];
  final String dateFormatted;
  if (rawDate is int) {
    dateFormatted = formatReceiptDate(rawDate);
  } else {
    final String rawDateStr = (rawDate ?? '').toString().trim();
    final int? parsedMs = int.tryParse(rawDateStr);
    dateFormatted = parsedMs != null ? formatReceiptDate(parsedMs) : rawDateStr;
  }

  // Total: int (may arrive as String from some tenants)
  final dynamic rawTotal = doc[totalField];
  final int total = rawTotal is int
      ? rawTotal
      : (int.tryParse(rawTotal?.toString() ?? '') ?? 0);

  // Lines: li[] is a native Firestore array of maps
  final List<ReceiptLine> lines = <ReceiptLine>[];
  final dynamic rawLines = doc[linesField];
  if (rawLines is List) {
    for (final dynamic item in rawLines) {
      if (item is Map) {
        final String name = (item[lineNameField] ?? '').toString();
        final dynamic rawQty = item[lineQtyField];
        final int qty = rawQty is int
            ? rawQty
            : (int.tryParse(rawQty?.toString() ?? '') ?? 0);
        final dynamic rawPrice = item[linePriceField];
        final int price = rawPrice is int
            ? rawPrice
            : (int.tryParse(rawPrice?.toString() ?? '') ?? 0);
        final dynamic rawSub = item[lineSubField];
        final int sub = rawSub is int
            ? rawSub
            : (int.tryParse(rawSub?.toString() ?? '') ?? 0);
        lines.add(ReceiptLine(name: name, qty: qty, price: price, sub: sub));
      }
    }
  }

  return ReceiptData(
    no: noVal,
    dateFormatted: dateFormatted,
    buyer: buyer,
    payment: payment,
    status: status,
    total: total,
    gl: gl,
    lines: lines,
  );
}

// ── Widget ────────────────────────────────────────────────────────────

/// RECEIPT_DOC — read-only on-screen nota card.
///
/// Reads one nota doc by search, renders scalar fields by config-driven names,
/// loops li[] into line rows, looks up depo header from a second table.
/// Read-only: no write, no action, no routeStack push.
class ReceiptDoc extends StatefulWidget {
  const ReceiptDoc({
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

  @override
  State<ReceiptDoc> createState() => _ReceiptDocState();
}

class _ReceiptDocState extends State<ReceiptDoc> {
  String _notaCode = '';
  String _headerCode = '';
  List<String> _textArray = [];
  String _searchDecoded = '';
  String _headerSearchDecoded = '';
  String _headerNameLiteral = '';
  String _headerAddrLiteral = '';

  /// True when both header literals are provided — skip Firestore header lookup.
  bool get _hasLiteralHeader =>
      _headerNameLiteral.isNotEmpty && _headerAddrLiteral.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
    // diamondTextToList('') returns [''] (length 1), not [] — the repo footgun.
    // Collapse it so every _label() index (incl. the title at 0) uses its
    // fallback when `text` is absent, instead of rendering blank.
    if (_textArray.length == 1 && _textArray.first.isEmpty) _textArray = [];
    _headerNameLiteral = (widget.component['headerName'] ?? '')
        .toString()
        .trim();
    _headerAddrLiteral = (widget.component['headerAddr'] ?? '')
        .toString()
        .trim();
    // autheniumDecode BEFORE any split on ◼ (U+25FC)
    _searchDecoded = (autheniumDecode(widget.component['search']) ?? '')
        .toString()
        .trim();
    _headerSearchDecoded =
        (autheniumDecode(widget.component['headerSearch']) ?? '')
            .toString()
            .trim();
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Primary: nota table
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _notaCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      if (appVid.isNotEmpty) {
        subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _notaCode);
      }
    }

    // Secondary: header (stock_location) table — skip when literals cover it
    if (!_hasLiteralHeader) {
      final String rawHeaderTable = (widget.component['headerTable'] ?? '')
          .toString()
          .trim();
      final TablePath htp = parseTablePath(rawHeaderTable);
      if (htp.tableDocId.isNotEmpty) {
        _headerCode = '$appVid/${htp.tableDocId}/${htp.subColl}';
        if (appVid.isNotEmpty) {
          subscribeToMapCollection(
            appVid,
            htp.tableDocId,
            htp.subColl,
            _headerCode,
          );
        }
      }
    }
  }

  /// Build the field-config map from component JSON.
  Map<String, String> get _fieldConfig => {
    'noField': (widget.component['noField'] ?? '').toString(),
    'buyerField': (widget.component['buyerField'] ?? '').toString(),
    'buyerEmpty': (widget.component['buyerEmpty'] ?? '').toString(),
    'dateField': (widget.component['dateField'] ?? '').toString(),
    'paymentField': (widget.component['paymentField'] ?? '').toString(),
    'statusField': (widget.component['statusField'] ?? '').toString(),
    'totalField': (widget.component['totalField'] ?? '').toString(),
    'linesField': (widget.component['linesField'] ?? '').toString(),
    'lineNameField': (widget.component['lineNameField'] ?? '').toString(),
    'lineQtyField': (widget.component['lineQtyField'] ?? '').toString(),
    'linePriceField': (widget.component['linePriceField'] ?? '').toString(),
    'lineSubField': (widget.component['lineSubField'] ?? '').toString(),
  };

  /// Label from text[] with length guard.
  String _label(int i, [String fallback = '']) =>
      _textArray.length > i ? _textArray[i] : fallback;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // ── Load + filter nota docs ──
      final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
        mapTableContent[_notaCode] ?? const [],
      );
      final Map<String, dynamic> screenTx = transactionStore.state.screenTx;

      // Resolve {nno} token in search config
      final String resolvedSearch = resolveDriverCurlyTokens(
        _searchDecoded,
        widget.scrName,
      );

      final List<Map<String, dynamic>> matched = filterByCharCodeEquality(
        docs,
        resolvedSearch,
        screenTx,
      );

      if (matched.isEmpty) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Belum ada nota',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
            ),
          ),
        );
      }

      final Map<String, dynamic> doc = matched.first;
      final ReceiptData data = extractReceiptData(doc, _fieldConfig);

      // ── Header depo ──
      String headerName = '';
      String headerAddr = '';
      if (_hasLiteralHeader) {
        headerName = _headerNameLiteral;
        headerAddr = _headerAddrLiteral;
      } else if (data.gl.isNotEmpty && _headerCode.isNotEmpty) {
        final List<Map<String, dynamic>> headerDocs =
            List<Map<String, dynamic>>.from(
              mapTableContent[_headerCode] ?? const [],
            );
        // Resolve {gl} in headerSearch: replace with the actual gl value
        final String resolvedHeaderSearch = _headerSearchDecoded.replaceAll(
          '{gl}',
          data.gl,
        );
        final List<Map<String, dynamic>> headerMatched =
            filterByCharCodeEquality(
              headerDocs,
              resolvedHeaderSearch,
              screenTx,
            );
        if (headerMatched.isNotEmpty) {
          final Map<String, dynamic> hDoc = headerMatched.first;
          final String nameField = (widget.component['headerNameField'] ?? '')
              .toString();
          final String addrField = (widget.component['headerAddrField'] ?? '')
              .toString();
          headerName = nameField.isNotEmpty
              ? (hDoc[nameField] ?? '').toString()
              : '';
          headerAddr = addrField.isNotEmpty
              ? (hDoc[addrField] ?? '').toString()
              : '';
        }
      }

      // ── Render ──
      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Header depo ──
              if (headerName.isNotEmpty || headerAddr.isNotEmpty) ...[
                if (headerName.isNotEmpty)
                  Text(
                    headerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (headerAddr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    headerAddr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
              ],

              // ── Title ──
              Text(
                _label(0, 'NOTA'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Divider(color: Color(0xFFD1D5DB), height: 1),
              const SizedBox(height: 10),

              // ── Scalar fields ──
              _scalarRow(_label(1, 'No.'), data.no),
              _scalarRow(_label(2, 'Tanggal'), data.dateFormatted),
              _scalarRow(_label(3, 'Pembeli'), data.buyer),
              _scalarRow(_label(4, 'Bayar'), data.payment),

              const SizedBox(height: 8),
              const Divider(color: Color(0xFFD1D5DB), height: 1),
              const SizedBox(height: 8),

              // ── Line items ──
              ...data.lines.map((line) => _lineItem(line)),

              if (data.lines.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(color: Color(0xFFD1D5DB), height: 1),
                const SizedBox(height: 8),
              ],

              // ── Total ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _label(5, 'TOTAL'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  Text(
                    'Rp ${formatThousands(data.total)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),

              // ── Status badge ──
              if (data.status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    data.status,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF166534),
                    ),
                  ),
                ),
              ],

              // ── Footer ──
              if (_label(6).isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _label(6),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _scalarRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineItem(ReceiptLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '  ${line.qty}x ${formatThousands(line.price)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              Text(
                formatThousands(line.sub),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
