import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'driver_home_support.dart';
import 'ftz_display_images.dart';
import 'list_card_support.dart';
import 'panel_card_support.dart';

/// Text and border roles for this card.
///
/// `Colors.grey.shade500` (#9E9E9E) was 2.68:1 on white -- well under the WCAG
/// AA floor of 4.5:1 for normal text, which is why the secondary column read as
/// washed out rather than merely quiet. #6B7280 is 4.83:1 and stays visibly
/// secondary against the 10.3:1 primary. Do NOT reintroduce a `grey.shadeNNN`
/// here without measuring it.
const Color _kTextPrimary = Color(0xFF374151); // 10.31:1 on white
const Color _kTextSecondary = Color(0xFF6B7280); // 4.83:1 on white
const Color _kBorder = Color(0xFFE5E7EB);

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
  List<ImageBlock> _imageBlocks = [];
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

    // images/imageLabels + OPTIONAL images2/imageLabels2: ◆-separated url
    // templates and their captions, merged into ordered label blocks. Each
    // block renders as one header + one horizontal strip. Config keys are the
    // sheet's exact names — `images2`/`imageLabels2` are already LIVE.
    _imageBlocks = buildImageBlocks(
      _cfg('images'),
      _cfg('imageLabels'),
      _cfg('images2'),
      _cfg('imageLabels2'),
    );

    // text: notFoundText
    _notFoundText = _cfg('text').trim();
    if (_notFoundText.isEmpty) _notFoundText = 'Data tidak ditemukan';
  }

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);
    final String rawTable =
        (widget.component['table'] ?? '').toString().trim();
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
    final List<Map<String, dynamic>> docs =
        List<Map<String, dynamic>>.from(
            mapTableContent[_code] ?? const []);
    if (_code.isEmpty) return null;
    if (_rawSearch.isEmpty) return docs.isNotEmpty ? docs.first : null;
    final List<Map<String, dynamic>> matched =
        filterDriverHomeDocs(docs, _rawSearch, widget.scrName);
    return matched.isNotEmpty ? matched.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final Map<String, dynamic>? doc = _findDoc();

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
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
        border: Border.all(color: _kBorder),
      ),
      child: Text(
        _notFoundText,
        style: const TextStyle(color: _kTextSecondary, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> doc) {
    final String title =
        resolveMapTokens(_titleTpl, doc, const <String, String>{});
    final String subtitle =
        resolveMapTokens(_subtitleTpl, doc, const <String, String>{});
    final String note = resolveNoteTemplate(_noteTpl, doc);

    // Badge
    final String badgeValue = _badgeField.isNotEmpty
        ? (doc[_badgeField] ?? '').toString().trim()
        : '';
    final BadgeEntry? badge =
        badgeValue.isNotEmpty ? lookupBadge(_badgeEntries, badgeValue) : null;

    // Visible rows. Two shapes (Perubahan 3):
    //   Label◼<f>  -> literal label, today's 120px-label layout (wide: false)
    //   <f>        -> label-less; the RESOLVED value is split at the last
    //                 " | " into title + value and drawn wide (wide: true)
    final List<_ResolvedRow> visibleRows = [];
    for (final rd in _rowDefs) {
      final String resolved =
          resolveMapTokens(rd.template, doc, const <String, String>{});
      if (_hideEmptyRows && resolved.trim().isEmpty) continue;
      if (rd.label.isEmpty) {
        final PipeSplit ps = splitPipeValue(resolved);
        visibleRows.add(_ResolvedRow(
          label: ps.title,
          value: ps.value.isEmpty ? '-' : ps.value,
          wide: true,
        ));
      } else {
        visibleRows.add(_ResolvedRow(
          label: rd.label,
          value: resolved.trim().isEmpty ? '-' : resolved,
          wide: false,
        ));
      }
    }

    // Image gallery: one strip per label block. A field can hold several
    // ◇-joined urls (separator[5], the processData joiner — NOT ◆, and
    // stringCleanUp deliberately exempts it); splitImageUrls unpacks them so
    // the joined string never reaches Image.network. A block whose templates
    // all resolve empty is dropped entirely, header included.
    final List<_ResolvedImageBlock> resolvedBlocks = [];
    for (final ImageBlock blk in _imageBlocks) {
      final List<String> urls = [];
      for (final String tpl in blk.templates) {
        urls.addAll(splitImageUrls(
            resolveMapTokens(tpl, doc, const <String, String>{})));
      }
      if (urls.isEmpty) continue;
      resolvedBlocks.add(_ResolvedImageBlock(label: blk.label, urls: urls));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
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
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              style: const TextStyle(fontSize: 13, color: _kTextSecondary),
            ),
          ],
          // ── Note ──
          if (note.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              note,
              style: const TextStyle(fontSize: 12, color: _kTextSecondary),
            ),
          ],
          // ── KV rows ──
          //
          // Two constructs share this list: labelled rows are a key/value
          // TABLE (secondary key left, primary value right), label-less rows
          // are a LIST of results (primary text left, secondary tag right).
          // Read as one continuous block those two conventions look like an
          // inverted table, so the first labelled -> label-less transition gets
          // a divider and a wider gap. Only that first crossing is separated;
          // a config that interleaves the shapes separates at each crossing,
          // which is the same rule, not a special case.
          if (visibleRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: _kBorder),
            const SizedBox(height: 12),
            for (int r = 0; r < visibleRows.length; r++) ...[
              if (r > 0 && visibleRows[r].wide && !visibleRows[r - 1].wide) ...[
                const SizedBox(height: 4),
                const Divider(height: 1, color: _kBorder),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: visibleRows[r].wide
                    ? _buildSplitRow(visibleRows[r])
                    : _buildLabelledRow(visibleRows[r]),
              ),
            ],
          ],
          // ── Image gallery ──
          if (resolvedBlocks.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Divider(height: 1, color: _kBorder),
            const SizedBox(height: 12),
            for (int b = 0; b < resolvedBlocks.length; b++) ...[
              if (b > 0) const SizedBox(height: 12),
              if (resolvedBlocks[b].label.isNotEmpty) ...[
                Text(
                  resolvedBlocks[b].label,
                  style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                ),
                const SizedBox(height: 6),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int u = 0; u < resolvedBlocks[b].urls.length; u++) ...[
                      if (u > 0) const SizedBox(width: 10),
                      _buildThumb(resolvedBlocks[b].urls[u]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Row from a `Label◼template` entry — today's layout, unchanged.
  Widget _buildLabelledRow(_ResolvedRow row) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            row.label,
            style: const TextStyle(fontSize: 13, color: _kTextSecondary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            row.value,
            style: const TextStyle(fontSize: 13, color: _kTextPrimary),
          ),
        ),
      ],
    );
  }

  /// Row from a label-less entry (D2): wide title left, value right-aligned,
  /// no fixed 120px label column.
  ///
  /// An empty title means the resolved value carried no " | " — render it
  /// plain. It must NOT be wrapped in Expanded: the parent here is a Padding,
  /// not a Flex, and a stray Expanded asserts at runtime.
  Widget _buildSplitRow(_ResolvedRow row) {
    if (row.label.isEmpty) {
      return Text(
        row.value,
        style: const TextStyle(fontSize: 13, color: _kTextPrimary),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            row.label,
            style: const TextStyle(fontSize: 13, color: _kTextPrimary),
          ),
        ),
        const SizedBox(width: 8),
        // The status is a TAG on a list item, not the value half of a table:
        // smaller and heavier so it reads as a distinct class of thing rather
        // than as body text that lost its contrast fight with the title.
        Expanded(
          flex: 2,
          child: Text(
            row.value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _kTextSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// One 90x90 thumbnail. The caption lives on the block header now (D1), so a
  /// thumb is just the tappable image. `errorBuilder` is mandatory: a
  /// NetworkImage that fails to load without one is a FATAL, not a blank box.
  Widget _buildThumb(String url) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullScreenImageView(imageUrl: url),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
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
            // Non-text contrast rule (3:1): this icon carries state ("the photo
            // failed to load"), so it is not decorative. #9CA3AF on the #F3F4F6
            // placeholder was 2.31:1; _kTextSecondary is 4.39:1.
            child: const Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: _kTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Private data classes ──────────────────────────────────────────────

class _ResolvedRow {
  final String label;
  final String value;

  /// True when this row came from a label-less `rows` entry: draw it wide
  /// (title Expanded left, value right-aligned) instead of the 120px-label
  /// layout. [label] then holds the part BEFORE the last " | ", or '' when the
  /// resolved value had no separator.
  final bool wide;
  const _ResolvedRow({
    required this.label,
    required this.value,
    required this.wide,
  });
}

class _ResolvedImageBlock {
  final String label;
  final List<String> urls;
  const _ResolvedImageBlock({required this.label, required this.urls});
}
