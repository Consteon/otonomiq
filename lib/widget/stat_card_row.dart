import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

// ─── STAT_CARD_ROW — pure parsers (top-level for testability) ───────────────

/// Recognised tone keywords. An unrecognised tone is normalized to `muted`
/// (with a one-time WARN) inside [parseStatCardDefs].
const Set<String> _knownTones = {'ok', 'warn', 'danger', 'accent', 'muted'};

/// Parsed card definition from the `cards` config field.
class StatCardDef {
  final String label;
  final String field;
  final String tone; // ok|warn|danger|accent|muted
  const StatCardDef(this.label, this.field, this.tone);
}

/// Parse `cards`: `Label◼field◼tone★Label2◼field2◼tone2★…`.
///
/// Split on ★ (U+2605), then each entry split on ◼ (U+25FC).
/// Length-guarded: missing field → '', missing tone → 'muted'.
/// Empty/blank entries are skipped. An unrecognised tone is normalized to
/// `muted` (warned once here, not per-rebuild).
///
/// CONFIG RULE: a label must NOT contain ◼ (U+25FC). Because parsing is a
/// plain positional split, an extra ◼ in the label shifts `field` and `tone`
/// by one segment (e.g. `Batch◼siap◼bt◼ok` → label `Batch`, field `siap`,
/// tone `bt`). This is intentional; keep labels ◼-free.
///
/// Caller MUST `autheniumDecode` the raw string BEFORE calling.
List<StatCardDef> parseStatCardDefs(String raw) {
  if (raw.trim().isEmpty) return const [];
  final List<StatCardDef> out = [];
  for (final part in raw.split('\u{2605}')) {
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    // Split at ◼ — up to 3 segments: label, field, tone
    final List<String> segs = trimmed.split('\u{25FC}');
    final String label = segs.isNotEmpty ? segs[0].trim() : '';
    if (label.isEmpty) continue;
    final String field = segs.length > 1 ? segs[1].trim() : '';
    String tone = segs.length > 2 ? segs[2].trim().toLowerCase() : 'muted';
    if (tone.isEmpty) tone = 'muted';
    if (!_knownTones.contains(tone)) {
      debugPrint(
        'WARN StatCardRow: unknown tone "$tone" for label "$label", '
        'falling back to muted',
      );
      tone = 'muted';
    }
    out.add(StatCardDef(label, field, tone));
  }
  return out;
}

/// Resolve tone to foreground color. Unknown tone → muted (silent safety net;
/// unknown tones are already normalized in [parseStatCardDefs]).
Color statCardFgColor(String tone) {
  switch (tone) {
    case 'ok':
      return statusColor('ok');
    case 'warn':
      return statusColor('warn');
    case 'danger':
      return statusColor('danger');
    case 'accent':
      return statusColor('info');
    case 'muted':
      return const Color(0xFF6B7280);
    default:
      return const Color(0xFF6B7280);
  }
}

/// Resolve tone to background color. Unknown tone → muted bg (silent safety net).
Color statCardBgColor(String tone) {
  switch (tone) {
    case 'ok':
      return statusBgColor('ok');
    case 'warn':
      return statusBgColor('warn');
    case 'danger':
      return statusBgColor('danger');
    case 'accent':
      return statusBgColor('info');
    case 'muted':
      return const Color(0xFFF3F4F6);
    default:
      return const Color(0xFFF3F4F6);
  }
}

/// Read a field value from doc, defaulting absent/null to '0'.
/// Non-null values are returned as-is (widget does not judge type).
String resolveStatValue(Map<String, dynamic> doc, String field) {
  if (field.isEmpty) return '0';
  final dynamic raw = doc[field];
  if (raw == null) return '0';
  return raw.toString();
}

// ─── STAT_CARD_ROW widget ───────────────────────────────────────────────────

/// STAT_CARD_ROW -- horizontal row of N stat cards from ONE keyed cache doc.
///
/// Read-only: NO buttons, NO actions, NO navigation, NO txfController,
/// NO history writes. Numbers are precomputed by Cloud Functions.
class StatCardRow extends StatefulWidget {
  const StatCardRow({
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
  State<StatCardRow> createState() => _StatCardRowState();
}

class _StatCardRowState extends State<StatCardRow> {
  String _code = '';

  // Parsed config
  List<StatCardDef> _cards = [];
  String _highlight = '';
  String _rawSearch = '';
  String _notFoundText = '';

  /// Decode a component config field via autheniumDecode.
  String _cfg(String key) {
    final String raw = (widget.component[key] ?? '').toString();
    return autheniumDecode(raw) ?? raw;
  }

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    // search: stored raw — filterDriverHomeDocs decodes internally
    _rawSearch = (widget.component['search'] ?? '').toString().trim();

    _cards = parseStatCardDefs(_cfg('cards'));
    _highlight = _cfg('highlight').trim();

    _notFoundText = _cfg('text').trim();
    if (_notFoundText.isEmpty) _notFoundText = 'Belum ada data';
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (rawTable.isEmpty) return;
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty) return;
    // vid-scoped key (prevents cross-tenant subscription collision)
    _code = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _code);
  }

  Map<String, dynamic>? _findDoc() {
    // Read the observable UNCONDITIONALLY — Obx needs >=1 observable per build
    // or it throws ObxError. Do NOT move this below the _code guard.
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_code] ?? const [],
    );
    if (_code.isEmpty) return null;
    if (_rawSearch.isEmpty) return docs.isNotEmpty ? docs.first : null;
    final List<Map<String, dynamic>> matched = filterDriverHomeDocs(
      docs,
      _rawSearch,
      widget.scrName,
    );
    return matched.isNotEmpty ? matched.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Map<String, dynamic>? doc = _findDoc();

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: doc == null ? _buildNotFound() : _buildRow(doc),
      );
    });
  }

  Widget _buildNotFound() {
    // No cards configured → nothing to render (intentional, not an oversight).
    if (_cards.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        _notFoundText,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> doc) {
    if (_cards.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final int count = _cards.length;
        const double spacing = 10;
        // Equal-width cards: fill available width with spacing
        final double cardWidth = count > 0
            ? (constraints.maxWidth - spacing * (count - 1)) / count
            : constraints.maxWidth;
        // Clamp minimum so cards don't get absurdly narrow on 5+ cards
        final double effectiveWidth = cardWidth < 70 ? 70.0 : cardWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final def in _cards) _buildCard(doc, def, effectiveWidth),
          ],
        );
      },
    );
  }

  Widget _buildCard(Map<String, dynamic> doc, StatCardDef def, double width) {
    final String value = resolveStatValue(doc, def.field);
    final bool isHighlighted = _highlight.isNotEmpty && def.field == _highlight;
    final Color fgColor = statCardFgColor(def.tone);
    final Color bgColor = statCardBgColor(def.tone);

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isHighlighted ? bgColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted ? fgColor : const Color(0xFFE5E7EB),
            width: isHighlighted ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: fgColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              def.label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
