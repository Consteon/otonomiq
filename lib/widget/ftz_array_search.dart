import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:get/get.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../otq_icons.dart';
import 'ftz_array_search_support.dart';
import 'ftz_horizontal_image_list.dart';

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
  String get _activeFilter => widget.resultController == null
      ? (widget.component['filter'] ?? '').toString()
      : (finalFilter ?? '');

  String get _imageCfg => (widget.component['image'] ?? '').toString();

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

  List<ContentLine> _linesFor(List<dynamic> row, String? template) =>
      parseContentLines(_renderContent(row, template));

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
    detailDialog(pickTable[index]);
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
