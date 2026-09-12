import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:get/get.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../otq_icons.dart';
import '../theme_tokens.dart';
import 'ftz_array_search_support.dart';
import 'ftz_horizontal_image_list.dart';
import 'report_detail_sheet.dart';

// Card palette. Same tokens list_card.dart / task_feed_list.dart already use,
// so every card surface in the app reads as one system.
const Color _cardBorder = Color(0xFFE5E7EB);
const Color _textDim = Color(0xFF9CA3AF);
const Color _textMid = Color(0xFF6B7280);
const Color _textStrong = Color(0xFF111827);
const Color _chipBg = Color(0xFFE0E7FF);
const Color _chipFg = Color(0xFF4338CA);

class FtzArraySearch extends StatefulWidget {
  const FtzArraySearch({
    super.key,
    required this.localTable,
    this.resultController,
    required this.component,
    this.startPosition = 0,
  });
  final List<dynamic> localTable;
  final TextEditingController? resultController;
  final dynamic component;
  final int startPosition;

  @override
  State<FtzArraySearch> createState() => _FtzArraySearchState();
}

class _FtzArraySearchState extends State<FtzArraySearch> {
  // Initialised at declaration, not `late`: every assignment below sits inside
  // a try/catch, so a throw would otherwise leave the field unset and turn a
  // swallowed parse error into a LateInitializationError at build/dispose.
  List<dynamic> initialTable = [];
  List<dynamic> pickTable = []; // searched localTable
  TextEditingController searchController = TextEditingController();
  List<dynamic> textArray = [];
  var displayObject = {};
  String title = '', searchLabel = '', hint = '';
  String searchValue = '';
  String? finalFilter;
  Worker? _tableWorker;
  String _tableCode = '';

  /// Label whose value is lifted out of the meta rows and shown as a chip.
  /// Optional config (`chipLabel`); empty = no chip, meta rows unchanged.
  String _chipLabel = '';

  /// In DISPLAY mode (no resultController), use the raw component filter
  /// string — mirrors display_list.dart:108 searchTable grammar.
  /// In PICKER mode, use the existing autheniumDecode + separator[8] split
  /// result (finalFilter). The autheniumDecode asymmetry is deliberate:
  /// display-mode filters are raw free-text, not server-encoded search fields.
  /// Still true now that searchTable is multi-clause: searchTable normalizes
  /// ONLY the ◆ clause separator (real ◆, `_u25C6_`, `_25C6_`) and decodes
  /// nothing else. What changed for BOTH modes is that ◆ is now reserved — a
  /// filter containing ◆ is an OR of its clauses. See searchTable, global.dart.
  /// Mind the split personality of ◆ in a PICKER filter: LEFT of the ⭘ it
  /// separates the indexTableString conditions that createInternalTableDynamic
  /// applies as successive `query.where(...)` — i.e. AND (see
  /// table_repository.dart) — while RIGHT of the ⭘ it is searchTable's OR.
  /// Two parsers, never the same string, opposite meanings.
  String get _activeFilter => widget.resultController == null
      ? (widget.component['filter'] ?? '').toString()
      : (finalFilter ?? '');

  String get _imageCfg => (widget.component['image'] ?? '').toString();

  /// Optional `rowSplit` separator (see docs/widgets/display_list.md).
  ///
  /// Blank or whitespace-only = OFF, and OFF is structural: [_linesFor] then
  /// takes the original single-pass `_renderContent` + `parseContentLines`
  /// call, so every `displayList` that does not author `rowSplit` — and every
  /// PICKER-mode instance, which passes a txf component — renders exactly as
  /// before. Read raw, like every other key in this widget; SduiSpec adoption
  /// here is on-touch only and one new key does not justify a sweep.
  ///
  /// NOT trimmed when non-blank: `rowSplit: " | "` is a legal separator.
  String get _rowSplit => (widget.component['rowSplit'] ?? '').toString();

  @override
  void initState() {
    try {
      if (widget.component['filter'] != null) {
        List<String> parts = (autheniumDecode(widget.component['filter']) ?? '')
            .split(separator[8]); // white hollow circle
        if (parts.length > 1) {
          finalFilter = parts[1];
        }
      }
    } catch (e) {
      // do nothing}
    }
    try {
      textArray = (widget.component['text'] == null)
          ? []
          : diamondTextToList(widget.component['text']);
    } catch (e) {
      // do nothing}
    }
    try {
      if (widget.component['content'] != null) {
        displayObject = {
          "searchDisplayType": "text1",
          "content": widget.component['content'],
        };
        title = textArray[0];
        searchLabel = textArray[1];
        hint = textArray[2];
      } else if (textArray.length > 6) {
        displayObject = jsonDecode(textArray[6]);
        title = textArray[0];
        searchLabel = textArray[4];
        hint = textArray[5];
      }
    } catch (e) {
      // do nothing}
    }
    _chipLabel = (widget.component['chipLabel'] ?? '').toString().trim();
    try {
      searchValue = '';
      _tableCode = normalizeTableName(
        autheniumDecode(widget.component['table'] ?? 'default') ?? '',
      );
      List<dynamic> source = List.from(tableContent[_tableCode] ?? []);
      if (source.isEmpty) {
        source = List.from(widget.localTable);
      }
      initialTable = searchTable(_activeFilter, source);
      if (widget.resultController == null) {
        initialTable = _applySort(
          initialTable,
        ); // DISPLAY mode: sort on first paint
      }
      pickTable = searchTable(searchValue, initialTable);
    } catch (e) {
      // do nothing}
    }
    _tableWorker = ever(tableContent, (_) {
      _rebuildTableData();
    });
    super.initState();
  } // end of initState

  @override
  void didUpdateWidget(covariant FtzArraySearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localTable.length != oldWidget.localTable.length) {
      _rebuildTableData();
    }
  }

  /// Sort [rows] in place by the integer key at index 0 per the component's
  /// `sort` param ('asc'/'desc'). No-op when sort is unset/other, or when keys
  /// are non-integer (mirrors the block previously inline in _rebuildTableData).
  List<dynamic> _applySort(List<dynamic> rows) {
    String sortParam = widget.component['sort'] ?? '';
    if (sortParam == 'asc' || sortParam == 'desc') {
      int sortFactor = sortParam == 'asc' ? 1 : -1;
      try {
        rows.sort(
          (a, b) =>
              sortFactor *
              int.parse(a[0].toString()).compareTo(int.parse(b[0].toString())),
        );
      } catch (e) {
        devPrint(e);
      }
    }
    return rows;
  }

  void _rebuildTableData() {
    List<dynamic> currentTableData = List.from(tableContent[_tableCode] ?? []);
    List<dynamic> newInitial = searchTable(_activeFilter, currentTableData);
    newInitial = _applySort(newInitial);
    if (mounted) {
      setState(() {
        initialTable = newInitial;
        pickTable = searchTable(searchValue, initialTable);
      });
    }
  }

  @override
  void dispose() {
    _tableWorker?.dispose();
    pickTable.clear();
    textArray.clear();
    searchController.dispose();
    super.dispose();
  } // end of dispose

  /// Render a row through a `content`/`detail` template.
  ///
  /// Literal `\n` (backslash + n, as authored by older sheets) is folded into a
  /// real line break instead of the legacy ' -- ' join, so both spellings feed
  /// the same parser. Falls back to the row's own leading columns when no
  /// template is configured.
  String _renderContent(List<dynamic> row, String? template) {
    if (template == null || template.trim().isEmpty) {
      return [
        row.length > 1 ? row[1] : '',
        row.length > 2 ? row[2] : '',
        row.length > 5 ? row[5] : '',
      ].where((v) => v.toString().trim().isNotEmpty).join('\n');
    }
    final String res = replaceMarker(
      template,
      row,
      widget.component['indexStart'] ?? 0,
      true,
    );
    return res.replaceAll('\\n', '\n');
  }

  /// Parse a row through a `content`/`detail` template.
  ///
  /// The single seam both renderers share: `detailDialog` passes `detail`,
  /// `_buildCard` passes `content`. When `rowSplit` is blank — every screen but
  /// LogChecklist, plus every PICKER-mode instance — this is the untouched
  /// pre-`rowSplit` call, which is what makes the non-breaking guarantee
  /// structural rather than argued.
  ///
  /// A blank template also stays on the old path on purpose: `_renderContent`
  /// owns the `row[1]/row[2]/row[5]` fallback, which is a whole-blob concept
  /// and must never fire once per template line.
  List<ContentLine> _linesFor(List<dynamic> row, String? template) {
    final String separator = _rowSplit;
    if (separator.trim().isEmpty ||
        template == null ||
        template.trim().isEmpty) {
      return parseContentLines(_renderContent(row, template));
    }
    return parseContentLinesSplit(
      template,
      separator,
      (String line) => replaceMarker(
        line,
        row,
        widget.component['indexStart'] ?? 0,
        true,
      ).replaceAll('\\n', '\n'),
    );
  }

  List<String> _imagesFor(List<dynamic> row) {
    if (_imageCfg.isEmpty) return const [];
    final List<String> urls = getImageList(row, _imageCfg);
    return urls.isEmpty ? const [] : urls;
  }

  void _onRowTap(int index) {
    if (widget.resultController != null) {
      widget.resultController!.text = pickTable[index][1].toString();
      Get.back();
      return;
    }
    if (_isV6) {
      _openV6Detail(pickTable[index]);
      return;
    }
    detailDialog(pickTable[index]);
  }

  /// v6 opens the modal sheet in `report_detail_sheet.dart`.
  ///
  /// Same `detail` template, same `_linesFor` parse and the same images as the
  /// v1 dialog — only the container and the layout differ, so a screen that
  /// switches variants shows the same fields either way.
  void _openV6Detail(List<dynamic> row) {
    final String template =
        (widget.component['detail'] ?? displayObject['content'] ?? '')
            .toString();
    final String head = title.trim();
    unawaited(
      showReportDetailSheet(
        context: context,
        lines: _linesFor(row, template),
        images: _imagesFor(row),
        chipLabel: _chipLabel,
        epochMs: reportEpoch(row, DateTime.now()),
        title: head.isEmpty ? 'Detail laporan' : 'Detail ${head.toLowerCase()}',
      ),
    );
  }

  // ---------------------------------------------------------------- detail

  Future<void> detailDialog(List<dynamic> row) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final String template =
        (widget.component['detail'] ?? displayObject['content'] ?? '')
            .toString();
    final List<ContentLine> lines = _linesFor(row, template);
    final List<String> images = _imagesFor(row);
    final double imageHeight = min(260, max(160, screenWidth - 110));

    return Get.dialog(
      Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (images.isNotEmpty)
                      HorizontalImageList(
                        imageUrls: images,
                        height: imageHeight,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < lines.length; i++) ...[
                            if (i > 0) const SizedBox(height: 14),
                            if (lines[i].label.isNotEmpty)
                              Text(
                                lines[i].label.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w600,
                                  color: _textDim,
                                ),
                              ),
                            if (lines[i].label.isNotEmpty)
                              const SizedBox(height: 2),
                            SelectableText(
                              lines[i].value.isEmpty ? '-' : lines[i].value,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: _textStrong,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: _cardBorder),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('Tutup'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  } // end of detailDialog

  // ------------------------------------------------------------------ card

  Widget _buildThumb(List<dynamic> row) {
    final List<String> urls = _imagesFor(row);
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              // cached: true -> CachedNetworkImage, which has an errorWidget and
              // reuses bytes on scroll. The old cached:false path was a raw
              // FadeInImage.memoryNetwork: no error handling, re-fetched on
              // every rebuild.
              child: displayImage(
                imageUrl: urls[0],
                cached: true,
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (urls.length > 1)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+${urls.length - 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaRow(ContentLine line) {
    final IconData? icon = metaIcon(line.label);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 14, color: _textDim),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  // No icon matched the label -> keep the label as text so the
                  // field is still identifiable.
                  if (icon == null && line.label.isNotEmpty)
                    TextSpan(
                      text: '${line.label}: ',
                      style: const TextStyle(fontSize: 12, color: _textDim),
                    ),
                  TextSpan(
                    text: line.value.isEmpty ? '-' : line.value,
                    style: const TextStyle(fontSize: 12, color: _textMid),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
    margin: const EdgeInsets.only(left: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _chipBg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: _chipFg,
      ),
    ),
  );

  Widget _buildCard(int index) {
    final List<dynamic> row = pickTable[index];
    final List<ContentLine> lines = _linesFor(
      row,
      displayObject['content']?.toString(),
    );

    final ContentRoles roles = splitContentRoles(lines, _chipLabel);
    final ContentLine? eyebrow = roles.eyebrow;
    final ContentLine? titleLine = roles.title;
    final ContentLine? note = roles.note;
    final List<ContentLine> meta = roles.meta;
    final String chipText = roles.chip;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onRowTap(index),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildThumb(row),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Eyebrow (timestamp) + affordance
                      if (eyebrow != null)
                        Row(
                          children: [
                            Icon(
                              metaIcon(eyebrow.label) ?? Icons.schedule,
                              size: 13,
                              color: _textDim,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                eyebrow.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: _textDim,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: _textDim,
                            ),
                          ],
                        ),
                      // Title + chip
                      if (titleLine != null)
                        Padding(
                          padding: EdgeInsets.only(
                            top: eyebrow == null ? 0 : 3,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  titleLine.value.isEmpty
                                      ? '-'
                                      : titleLine.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: _textStrong,
                                  ),
                                ),
                              ),
                              if (chipText.isNotEmpty) _chip(chipText),
                            ],
                          ),
                        ),
                      // Fields
                      for (final ContentLine line in meta) _metaRow(line),
                      // Free text — wraps to 2 lines instead of the old
                      // single-line fade, full text on tap.
                      if (note != null && note.value.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            note.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: _textMid,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- v6
  //
  // `variant: "tableCardInteractiveV6"`. Everything above stays the renderer
  // for `tableCardInteractive`, so a screen that does not author the V6 name
  // is byte-for-byte unchanged -- including PICKER mode, which passes a `txf`
  // component whose `variant` is `qrScan`/`text` and can never be v6.

  /// v6 drops the card-in-a-card for plain rows with a 1 dp rule, groups them
  /// by day like the Log tab, and gives the range filter its own chips.
  bool get _isV6 =>
      (widget.component['variant'] ?? '').toString().trim().toLowerCase() ==
      'tablecardinteractivev6';

  /// Active time window. Default `7 hari`, per the v6 spec; session-scoped
  /// because the widget is rebuilt from the page JSON on every navigation.
  ReportRange _range = ReportRange.week;

  /// v6 hides the search field behind an app-bar-style icon: a permanent 52 dp
  /// box above a two-row list is most of the screen spent on a control that is
  /// rarely used.
  bool _searchOpen = false;

  Color _toneFg(ReportTone tone) {
    switch (tone) {
      case ReportTone.ok:
        return OtqPalette.successText;
      case ReportTone.warn:
        return OtqPalette.warningText;
      case ReportTone.err:
        return OtqPalette.dangerText;
      case ReportTone.neutral:
        return OtqPalette.v6MutedFg;
    }
  }

  Color _toneBg(ReportTone tone) {
    switch (tone) {
      case ReportTone.ok:
        return OtqPalette.v6SuccessSoft;
      case ReportTone.warn:
        return OtqPalette.v6WarningSoft;
      case ReportTone.err:
        return OtqPalette.v6DangerSoft;
      case ReportTone.neutral:
        return OtqPalette.v6Muted;
    }
  }

  Widget _v6Chip(String text) {
    final ReportTone tone = reportTone(text);
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _toneBg(tone),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _toneFg(tone),
        ),
      ),
    );
  }

  /// 64 dp thumbnail, or a muted placeholder box.
  ///
  /// The placeholder is not optional: without it the text column of a row with
  /// no photo starts 76 dp left of every other row, and the list stops being a
  /// column. Its icon is [OtqPalette.v6BorderStrong] (3.20:1 on the muted
  /// ground) rather than the mock's `--color-disabled-fg`, which measures
  /// 2.38:1 there and misses the 3:1 non-text bar.
  Widget _v6Thumb(List<dynamic> row) {
    final List<String> urls = _imagesFor(row);
    if (urls.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: OtqPalette.v6Muted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.image_outlined,
          size: 24,
          color: OtqPalette.v6BorderStrong,
        ),
      );
    }
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 64,
            height: 64,
            child: displayImage(
              imageUrl: urls[0],
              cached: true,
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (urls.length > 1)
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '+${urls.length - 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// [text] with the live search query marked, the way the v6 search frame
  /// draws it. Falls back to a plain `Text` when nothing is being searched.
  Widget _v6Marked(String text, TextStyle style, {required int maxLines}) {
    if (searchValue.trim().isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: highlightSpans(text, searchValue)
            .map(
              (HighlightSpan s) => TextSpan(
                text: s.text,
                style: s.hit
                    ? const TextStyle(backgroundColor: OtqPalette.v6WarningSoft)
                    : null,
              ),
            )
            .toList(),
      ),
    );
  }

  /// One report row. 12 dp of padding around a 64 dp thumb makes the whole row
  /// an 88 dp target, which is why there is no chevron: the affordance is the
  /// row, not a 18 dp glyph in its corner.
  Widget _v6Row(int index, {required bool last, required DateTime now}) {
    final List<dynamic> row = pickTable[index];
    final ContentRoles roles = splitContentRoles(
      _linesFor(row, displayObject['content']?.toString()),
      _chipLabel,
    );
    final int? epochMs = reportEpoch(row, now);
    // No usable stamp -> the eyebrow's own rendered text keeps the slot, so the
    // row still says when it happened even on a table keyed by something else.
    final String stamp = epochMs != null
        ? reportClock(DateTime.fromMillisecondsSinceEpoch(epochMs))
        : (roles.eyebrow?.value ?? '');
    final String subline = reportSubline(roles);
    final String note = roles.note?.value.trim() ?? '';
    final String chip = roles.chip;

    return Semantics(
      button: true,
      label: <String>[
        if (stamp.isNotEmpty) 'Laporan $stamp',
        if (chip.isNotEmpty) chip,
        if (subline.isNotEmpty) subline,
        'Buka detail',
      ].join(', '),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _onRowTap(index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: last
                  ? null
                  : const Border(
                      bottom: BorderSide(color: OtqPalette.v6Border),
                    ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _v6Thumb(row),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          // ★ ONE flex child, and it is tight. `Flexible` for
                          // the clock plus a `Spacer` plus `Flexible` for the
                          // chip divides the free space three ways BEFORE the
                          // children are measured, and the clock's unused share
                          // is never given back -- the chip ends up floating
                          // mid-row instead of flush right. The chip is laid
                          // out first at its natural width (bounded, so a long
                          // value ellipsises rather than overflowing) and the
                          // clock takes whatever is left.
                          Expanded(
                            child: Text(
                              stamp.isEmpty ? '-' : stamp,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: OtqPalette.foreground,
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          if (chip.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 170),
                              child: _v6Chip(chip),
                            ),
                        ],
                      ),
                      if (subline.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        // Two lines, not the mock's one. The mock's own sample
                        // always fits because it carries two fields; a real
                        // screen can carry three, or one long site name. Wrap
                        // costs nothing when the text fits -- the second line
                        // only exists when the alternative is hiding text.
                        // (ui-ux-pro-max `Essential Text Truncation`, Critical:
                        // wrap or give a full-detail path rather than clamp
                        // meaning away. Tapping the row does give that path,
                        // which is why two lines is the ceiling and not four.)
                        _v6Marked(
                          subline,
                          const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: OtqPalette.v6MutedFg,
                          ),
                          maxLines: 2,
                        ),
                      ],
                      const SizedBox(height: 6),
                      if (note.isEmpty)
                        // v6MutedFg, not the mock's --color-disabled-fg: this
                        // is live content (2.72:1 would fail the text bar).
                        const Text(
                          'Tanpa catatan',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                            color: OtqPalette.v6MutedFg,
                          ),
                        )
                      else
                        _v6Marked(
                          note,
                          const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: OtqPalette.foreground,
                          ),
                          maxLines: 2,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [shown] is the number of rows the RANGE let through, not `pickTable`
  /// length: the subtitle sits directly above the list and may not claim rows
  /// the chips are hiding.
  Widget _v6Header(BuildContext context, int shown) {
    final String heading = title.trim().isEmpty ? 'Laporan' : title.trim();
    final String sub = _searchOpen
        ? (shown == 0
              ? 'Hasil pencarian'
              : '$shown laporan cocok · ${kReportRangeSummary[_range.index]}')
        : shown == 0
        ? 'Belum ada laporan'
        : '$shown laporan · ${kReportRangeSummary[_range.index]}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                heading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: OtqPalette.foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: _searchOpen ? 'Tutup pencarian' : 'Cari laporan',
            icon: Icon(
              _searchOpen ? Icons.close : Icons.search,
              size: 22,
              color: OtqPalette.foreground,
            ),
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  searchController.clear();
                  searchValue = '';
                  pickTable = searchTable('', initialTable);
                }
              });
            },
          ),
        ),
      ],
    );
  }

  /// Range chips. `Wrap`, not a horizontal scroller: the v6 mock scrolls this
  /// row, and at 200 % text scale a scroller clips the labels it is supposed
  /// to preserve (ui-ux-pro-max `Chip Collection Reflow`, severity High).
  Widget _v6Filters(BuildContext context) {
    final Color primary = Theme.of(context).primaryColor;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List<Widget>.generate(kReportRangeChips.length, (int i) {
        final bool on = _range.index == i;
        return Semantics(
          button: true,
          selected: on,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _range = ReportRange.values[i]),
            child: Container(
              // ★ NOT `alignment: Alignment.center`. A Container with an
              // alignment and no width expands to its maximum constraint, and
              // inside a Wrap that maximum is the whole row -- every chip then
              // takes a line of its own. `Center(widthFactor: 1)` centres
              // vertically while still shrink-wrapping the width.
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: on ? primary : OtqPalette.v6Muted,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  kReportRangeChips[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: on ? otqOn(primary) : OtqPalette.v6MutedFg,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _v6SearchField(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: OtqPalette.v6Muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          // Honours the component's `icon` key exactly as the v1 field does:
          // it is authored on every live screen, and a redesign that silently
          // stops reading a configured key is dead config by another name.
          Icon(
            otqIcons[(widget.component['icon'] ?? '').toString()] ??
                Icons.search,
            size: 20,
            color: OtqPalette.v6MutedFg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: OtqPalette.foreground,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: searchLabel.isNotEmpty ? searchLabel : hint,
                hintStyle: const TextStyle(
                  fontSize: 16,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
              onChanged: (String value) {
                setState(() {
                  searchValue = value;
                  pickTable = searchTable(searchValue, initialTable);
                });
              },
            ),
          ),
          if (searchValue.isNotEmpty)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Hapus pencarian',
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: OtqPalette.v6MutedFg,
                ),
                onPressed: () {
                  searchController.clear();
                  setState(() {
                    searchValue = '';
                    pickTable = searchTable('', initialTable);
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _v6Empty() {
    final bool filtered = searchValue.trim().isNotEmpty;
    final String headline = filtered
        ? 'Tidak ada hasil'
        : 'Belum ada laporan ${kReportRangeSummary[_range.index]}';
    final String sub = filtered
        ? 'Coba kata kunci lain, atau pilih rentang waktu yang lebih panjang.'
        : 'Laporan pekerjaan yang Anda buat akan muncul di sini.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: OtqPalette.v6Muted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                filtered ? Icons.search_off : Icons.description_outlined,
                size: 34,
                color: OtqPalette.v6MutedFg,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: OtqPalette.foreground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: OtqPalette.v6MutedFg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Flatten the visible rows into day headers + row indexes.
  ///
  /// Grouping is CONSECUTIVE, not a bucket-by-key: the list is already ordered
  /// by the component's `sort`, and re-ordering it here would silently override
  /// what the sheet asked for. On an unsorted table a day can therefore appear
  /// more than once, which is honest about the ordering rather than hiding it.
  List<Object> _v6Items(DateTime now) {
    final List<Object> items = <Object>[];
    String header = '';
    for (int i = 0; i < pickTable.length; i++) {
      final int? epochMs = reportEpoch(pickTable[i], now);
      if (!inReportRange(epochMs, _range, now)) continue;
      final String h = epochMs == null
          ? kReportNoDateHeader
          : reportDayHeader(DateTime.fromMillisecondsSinceEpoch(epochMs), now);
      if (h != header) {
        header = h;
        items.add(h);
      }
      items.add(i);
    }
    return items;
  }

  Widget _buildV6(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<Object> items = _v6Items(now);
    final int shown = items.whereType<int>().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _v6Header(context, shown),
        const SizedBox(height: 8),
        // The search field REPLACES the filter row, as in the v6 mock: both at
        // once would stack 90 dp of chrome over a two-row list.
        if (_searchOpen) _v6SearchField(context) else _v6Filters(context),
        const SizedBox(height: 4),
        Expanded(
          child: items.isEmpty
              ? _v6Empty()
              : ListView.builder(
                  scrollCacheExtent: ScrollCacheExtent.pixels(1000),
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int i) {
                    final Object item = items[i];
                    if (item is String) {
                      return Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 4 : 16,
                          bottom: 4,
                        ),
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            color: OtqPalette.v6MutedFg,
                          ),
                        ),
                      );
                    }
                    return _v6Row(
                      item as int,
                      // Last row of its day group: the next entry is a header
                      // or the list ends. Keeps the rule out from under a day
                      // heading, where it would read as an underline.
                      last: i + 1 >= items.length || items[i + 1] is String,
                      now: now,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- shell

  Widget _buildSearchField(BuildContext context) {
    final OutlineInputBorder base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _cardBorder),
    );
    final String placeholder = searchLabel.isNotEmpty ? searchLabel : hint;
    return TextFormField(
      controller: searchController,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        setState(() {
          searchValue = value;
          pickTable = searchTable(searchValue, initialTable);
        });
      },
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        prefixIcon: Icon(
          otqIcons[(widget.component['icon'] ?? '').toString()] ?? Icons.search,
          size: 20,
          color: _textDim,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: searchValue.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18, color: _textDim),
                tooltip: 'Hapus pencarian',
                onPressed: () {
                  searchController.clear();
                  setState(() {
                    searchValue = '';
                    pickTable = searchTable('', initialTable);
                  });
                },
              ),
        hintText: placeholder,
        hintStyle: const TextStyle(fontSize: 14, color: _textDim),
        border: base,
        enabledBorder: base,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _chipFg, width: 1.4),
        ),
      ),
      style: TextStyle(
        fontSize: 14,
        color: (widget.component['color'] ?? 'default') != 'default'
            ? Color(int.parse(widget.component['color']))
            : _textStrong,
      ),
    );
  }

  Widget _buildCountRow() {
    final String label = searchValue.isEmpty
        ? '${pickTable.length} data'
        : '${pickTable.length} dari ${initialTable.length} data';
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: _textDim,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool filtered = searchValue.isNotEmpty && initialTable.isNotEmpty;
    final String headline = filtered
        ? 'Tidak ada hasil'
        : (textArray.length > 3 && textArray[3].toString().trim().isNotEmpty
              ? textArray[3].toString()
              : 'Tidak ada data');
    final String sub = filtered
        ? 'Coba kata kunci lain'
        : 'Laporan yang masuk akan tampil di sini';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: _chipBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                filtered ? Icons.search_off : Icons.inbox_outlined,
                size: 26,
                color: _chipFg,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textMid,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _textDim),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isV6) return _buildV6(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchField(context),
        const SizedBox(height: 10),
        if (pickTable.isNotEmpty) _buildCountRow(),
        Expanded(
          child: pickTable.isEmpty
              ? _buildEmptyState()
              // No prototypeItem: cards are intentionally variable-height now
              // (the free-text line wraps), and prototypeItem forces one fixed
              // extent on every row.
              : ListView.builder(
                  scrollCacheExtent: ScrollCacheExtent.pixels(1000),
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: pickTable.length,
                  itemBuilder: (context, index) => _buildCard(index),
                ),
        ),
      ],
    );
  }
}
