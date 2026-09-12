//
// report_detail_sheet.dart
//
// The v6 detail view for one work report: an 88 %-height modal bottom sheet
// with a photo gallery, a three-level head, the note as a paragraph, and a
// two-column metadata table. Opened from the `tableCardInteractiveV6` list
// (`ftz_array_search.dart`); the v1 `tableCardInteractive` list keeps its
// centred `Get.dialog` untouched.
//
// Its own file rather than more of `ftz_array_search.dart`: this is a
// screen-sized surface with two stateful pieces of its own, and the list file
// is already carrying two card layouts.
//
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme_tokens.dart';
import 'ftz_array_search_support.dart';

/// Scrim over the list behind the sheet. v6 asks for 55 % of `#0F172A`.
const double _kScrimAlpha = 0.55;

/// CEILING on the sheet's height, as a fraction of the screen. The sheet is
/// sized by its content and only grows to this; it is never padded out to it.
///
/// The v6 mock specifies a flat 88 %. That is right for the frames it draws —
/// three photos and a paragraph — and wrong for a report with no photo and no
/// note, which would then sit in a third of a screen of white. A ceiling gives
/// the same result as the mock whenever the content is that long, and an
/// honest sheet when it is not.
///
/// Still not draggable-to-full: a sheet that reaches 100 % is a page, and the
/// list staying visible behind it is the whole reason this is not one.
const double _kSheetMaxHeightFactor = 0.88;

/// Open the v6 report detail sheet.
///
/// [lines] are the already-parsed `detail` template lines, [images] the row's
/// photo URLs and [epochMs] the row's `t` stamp (null when the table is not
/// keyed by one — the sheet then falls back to the template's own date text).
Future<void> showReportDetailSheet({
  required BuildContext context,
  required List<ContentLine> lines,
  required List<String> images,
  required String chipLabel,
  int? epochMs,
  String title = 'Detail laporan',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFF0F172A).withValues(alpha: _kScrimAlpha),
    // `builder:` shadows `context`, so every `Navigator.of(ctx)` below is the
    // sheet's own route and never a State context that may already be gone.
    builder: (BuildContext ctx) => _ReportDetailSheet(
      lines: lines,
      images: images,
      chipLabel: chipLabel,
      epochMs: epochMs,
      title: title,
    ),
  );
}

class _ReportDetailSheet extends StatefulWidget {
  const _ReportDetailSheet({
    required this.lines,
    required this.images,
    required this.chipLabel,
    required this.epochMs,
    required this.title,
  });

  final List<ContentLine> lines;
  final List<String> images;
  final String chipLabel;
  final int? epochMs;
  final String title;

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  final PageController _gallery = PageController();
  int _page = 0;

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

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

  // ------------------------------------------------------------------ head

  Widget _head(BuildContext ctx) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OtqPalette.v6Border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: OtqPalette.v6BorderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: OtqPalette.foreground,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Tutup',
                  icon: const Icon(
                    Icons.close,
                    size: 22,
                    color: OtqPalette.foreground,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- gallery

  Widget _pill(Widget child) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF0F172A).withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Center(widthFactor: 1, child: child),
  );

  Widget _gallerySection(BuildContext ctx, DetailRoles roles) {
    if (widget.images.isEmpty) {
      // A 4:3 box of nothing reads as a failed image. A 96 dp strip that says
      // so reads as an answer.
      return Container(
        height: 96,
        color: OtqPalette.v6Muted,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.image_outlined, size: 22, color: OtqPalette.v6MutedFg),
            SizedBox(width: 10),
            Text(
              'Tanpa foto',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: OtqPalette.v6MutedFg,
              ),
            ),
          ],
        ),
      );
    }

    final int count = widget.images.length;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFF2B2F38),
              child: PageView.builder(
                controller: _gallery,
                itemCount: count,
                onPageChanged: (int i) => setState(() => _page = i),
                itemBuilder: (BuildContext _, int i) => GestureDetector(
                  onTap: () => _openViewer(ctx, roles, i),
                  child: displayImage(
                    imageUrl: widget.images[i],
                    cached: true,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              right: 12,
              top: 12,
              child: _pill(
                Text(
                  '${_page + 1}/$count',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 10,
            child: Semantics(
              button: true,
              label: 'Perbesar foto',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openViewer(ctx, roles, _page),
                child: _pill(
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Perbesar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(count, (int i) {
                  final bool on = i == _page;
                  return Container(
                    width: on ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: on ? 1 : 0.55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  void _openViewer(BuildContext ctx, DetailRoles roles, int index) {
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => ReportPhotoViewer(
          urls: widget.images,
          initialIndex: index,
          caption: photoCaption(roles, widget.epochMs),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ body

  Widget _dhead(DetailRoles roles) {
    final int? ms = widget.epochMs;
    final String clock = ms == null
        ? ''
        : reportClock(DateTime.fromMillisecondsSinceEpoch(ms));
    final String sub = detailHeadSubline(roles, ms);
    final ReportTone tone = reportTone(roles.chip);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (roles.chip.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _toneBg(tone),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                roles.chip,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _toneFg(tone),
                ),
              ),
            ),
          if (clock.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              clock,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: OtqPalette.foreground,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (sub.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: OtqPalette.v6MutedFg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String label, ContentLine? line) {
    final String value = line?.value.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: OtqPalette.v6MutedFg,
            ),
          ),
          const SizedBox(height: 8),
          // SelectableText, as the v1 dialog had: a report number or a name is
          // the kind of thing people copy out of a detail view.
          SelectableText(
            value.isEmpty ? 'Tanpa catatan' : value,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              // v6MutedFg, not --color-disabled-fg: "Tanpa catatan" is live
              // content and 2.72:1 would miss the 4.5:1 text bar.
              color: value.isEmpty
                  ? OtqPalette.v6MutedFg
                  : OtqPalette.foreground,
              fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaTable(DetailRoles roles, List<ContentLine> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: <Widget>[
          const Divider(height: 1, thickness: 1, color: OtqPalette.v6Border),
          for (final ContentLine row in rows)
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: OtqPalette.v6Border)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 104,
                    child: Text(
                      row.label.isEmpty ? '—' : row.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                        color: OtqPalette.v6MutedFg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      row.value.isEmpty ? '-' : row.value,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: OtqPalette.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DetailRoles roles = splitDetailRoles(widget.lines, widget.chipLabel);
    // "Dibuat" is added last so the template's own fields keep their order.
    final List<ContentLine> metaRows = <ContentLine>[
      ...roles.meta,
      if (roles.stampText.trim().isNotEmpty)
        ContentLine('Dibuat', roles.stampText),
    ];
    final double maxHeight =
        MediaQuery.of(context).size.height * _kSheetMaxHeightFactor;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          // ★ `min` + `Flexible`, not the default `max` + `Expanded`.
          // `SingleChildScrollView` shrink-wraps its child in the scroll axis
          // (`_RenderSingleChildViewport.performLayout` constrains the CHILD's
          // size), so under a loose `Flexible` it takes the height it needs and
          // caps at what is left. `Expanded` is tight and would force it to the
          // ceiling, which is the empty space this replaces.
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _head(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _gallerySection(context, roles),
                    _dhead(roles),
                    _section('Keterangan', roles.note),
                    _metaTable(roles, metaRows),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen photo viewer: dark ground, pinch 1–4×, swipe between photos,
/// caption under the image instead of a stamp painted over it.
///
/// Same `PageView` + `InteractiveViewer` shape as `item_card_detail.dart`; the
/// differences are the v6 ground colour, the counter in the bar and the
/// caption.
class ReportPhotoViewer extends StatefulWidget {
  const ReportPhotoViewer({
    super.key,
    required this.urls,
    required this.initialIndex,
    this.caption = '',
  });

  final List<String> urls;
  final int initialIndex;
  final String caption;

  @override
  State<ReportPhotoViewer> createState() => _ReportPhotoViewerState();
}

class _ReportPhotoViewerState extends State<ReportPhotoViewer> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.urls.length;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 56,
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Tutup',
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Foto laporan',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (count > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '${_current + 1} / $count',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.86),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (int i) => setState(() => _current = i),
                itemBuilder: (BuildContext _, int i) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: displayImage(
                      imageUrl: widget.urls[i],
                      cached: true,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.caption.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Text(
                  widget.caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    // 0.86 white on #0B0F1A measures 15.6:1.
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
