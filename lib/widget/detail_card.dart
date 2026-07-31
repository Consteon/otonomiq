import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'ftz_display_images.dart';
import 'list_card_support.dart';
import 'panel_card_support.dart';

/// DETAIL_CARD -- universal config-driven single keyed-doc detail renderer.
///
/// Subscribes to a Firestore map-collection, finds ONE doc via search filter,
/// renders: title + subtitle + badge + N key-value rows + optional photo gallery.
///
/// Read-only: NO buttons, NO actions, NO navigation, NO txfController,
/// NO history writes. RBT/workflow widgets stay separate below it in the
/// page JSON.
class DetailCard extends StatefulWidget {
  const DetailCard({
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
  State<DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends State<DetailCard> {
  String _code = '';

  // Parsed config (set once in initState)
  String _rawSearch = '';
  String _titleTpl = '';
  String _subtitleTpl = '';
  String _noteTpl = '';
  String _badgeField = '';
  List<BadgeEntry> _badgeEntries = [];
  List<RowDef> _rowDefs = [];
  bool _hideEmptyRows = true;
  List<String> _imageTpls = [];
  List<String> _imageLabels = [];
  String _notFoundText = '';

  /// Decode a component config field via autheniumDecode (server may encode
  /// special chars as _u25FC_/_u2B58_/etc).
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

    _titleTpl = _cfg('title');
    _subtitleTpl = _cfg('subtitle');
    _noteTpl = _cfg('note');
    _badgeField = _cfg('badgeField').trim();
    _badgeEntries = parseBadgeMap(_cfg('badgeMap'));
    _rowDefs = parseRowDefs(_cfg('rows'));

    // hideEmptyRows: TRUE (default) | FALSE
    final String hideRaw = _cfg('hideEmptyRows').trim().toLowerCase();
    _hideEmptyRows = hideRaw != 'false';

    // images: ◆-separated templates of url fields
    try {
      _imageTpls = diamondTextToList(
        _cfg('images'),
      ).where((s) => s.trim().isNotEmpty).toList();
    } catch (_) {
      _imageTpls = [];
    }

    // imageLabels: ◆-separated captions
    try {
      _imageLabels = diamondTextToList(_cfg('imageLabels'));
    } catch (_) {
      _imageLabels = [];
    }

    // text: notFoundText
    _notFoundText = _cfg('text').trim();
    if (_notFoundText.isEmpty) _notFoundText = 'Data tidak ditemukan';
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

  /// Find the single doc via the component's search filter.
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
        child: doc == null ? _buildNotFound() : _buildCard(doc),
      );
    });
  }

  // ── Card layout ───────────────────────────────────────────────────

  Widget _buildNotFound() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        _notFoundText,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> doc) {
    final String title = resolveMapTokens(
      _titleTpl,
      doc,
      const <String, String>{},
    );
    final String subtitle = resolveMapTokens(
      _subtitleTpl,
      doc,
      const <String, String>{},
    );
    final String note = resolveNoteTemplate(_noteTpl, doc);

    // Badge
    final String badgeValue = _badgeField.isNotEmpty
        ? (doc[_badgeField] ?? '').toString().trim()
        : '';
    final BadgeEntry? badge = badgeValue.isNotEmpty
        ? lookupBadge(_badgeEntries, badgeValue)
        : null;

    // Visible rows
    final List<_ResolvedRow> visibleRows = [];
    for (final rd in _rowDefs) {
      final String resolved = resolveMapTokens(
        rd.template,
        doc,
        const <String, String>{},
      );
      if (_hideEmptyRows && resolved.trim().isEmpty) continue;
      visibleRows.add(
        _ResolvedRow(
          label: rd.label,
          value: resolved.trim().isEmpty ? '-' : resolved,
        ),
      );
    }

    // Image gallery: resolve each template, pair with label, skip empty urls
    final List<_ImageSlot> imageSlots = [];
    for (int i = 0; i < _imageTpls.length; i++) {
      final String url = resolveMapTokens(
        _imageTpls[i],
        doc,
        const <String, String>{},
      ).trim();
      if (url.isEmpty) continue;
      final String caption = _imageLabels.length > i
          ? _imageLabels[i].trim()
          : '';
      imageSlots.add(_ImageSlot(url: url, caption: caption));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Title + badge ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusBgColor(badge.tier),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor(badge.tier),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // ── Subtitle ──
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
          // ── Note ──
          if (note.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              note,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
          // ── KV rows ──
          if (visibleRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 12),
            for (final row in visibleRows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        row.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.value,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          // ── Image gallery ──
          if (imageSlots.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final slot in imageSlots) _buildImageSlot(slot)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageSlot(_ImageSlot slot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FullScreenImageView(imageUrl: slot.url),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              slot.url,
              width: 90,
              height: 90,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
        ),
        if (slot.caption.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: 90,
            child: Text(
              slot.caption,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Private data classes ──────────────────────────────────────────────

class _ResolvedRow {
  final String label;
  final String value;
  const _ResolvedRow({required this.label, required this.value});
}

class _ImageSlot {
  final String url;
  final String caption;
  const _ImageSlot({required this.url, required this.caption});
}
