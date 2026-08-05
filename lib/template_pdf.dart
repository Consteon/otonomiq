// template_pdf.dart
import 'dart:typed_data';

import 'package:expressions/expressions.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders a PRN-dialect template to a PDF document.
///
/// Supports the same template language as [TemplatePrinter] (template_printer.dart):
/// `;`-separated lines, tags TEXT/QRCODE/HR/FEED/ROW+COL/LOOP,
/// `{{field}}` interpolation with |idr/|usd/|default:X formatters.
///
/// Silently ignores: CUT, GROUP_BY, ACCUMULATE, unknown tags.
/// ponytail: subset walker -- GROUP_BY/ACCUMULATE add when a consumer needs them.
///
/// Divergences from template_printer.dart (intentional, documented in
/// docs/widgets/share_pdf.md):
///   1. _formatIdr passes non-numeric input through unchanged; the ESC/POS
///      renderer returns '0'. This is the better behavior (avoids silent data
///      loss on pre-formatted strings like '1.250.000').
///   2. interpolate's expression branch falls back to path resolution on parse
///      failure; the ESC/POS renderer emits '!ERR!'. This resolves the known
///      '-' false-positive (field names containing hyphens) instead of surfacing
///      an error token in a shared PDF.
class TemplatePdf {
  final String template;
  final PdfPageFormat pageFormat;
  final Map<String, dynamic> tables;

  /// Resolves a named color string (e.g. 'blue') to a PdfColor.
  /// Caller wraps stringToColor (global2.dart) with PdfColor.fromInt conversion.
  /// Null -> _resolveColor falls back to PdfColors.black.
  final PdfColor Function(String)? colorResolver;

  /// Thick border color for every page edge. Null -> no border.
  final PdfColor? borderColor;

  /// Loads image bytes by key for IMAGE tags. Null -> IMAGE tags silently skipped.
  /// The key is either an `asset` bundle key OR a network `url` (the caller's
  /// loader decides); signature `(key) => Future<Uint8List?>`, null = not found.
  final Future<Uint8List?> Function(String)? assetLoader;

  /// Border stroke width in points. Used by single-mode page-edge border
  /// and grid-mode per-card border. Default 8.0 (spec §3).
  final double borderWidth;

  final List<String> _lines;
  // ponytail: _variables is write-never today (ACCUMULATE is out of scope v1).
  // The branch in interpolate() that reads it is kept for parity with
  // template_printer.dart; it activates when ACCUMULATE support lands.
  final Map<String, dynamic> _variables = {};

  /// Pre-loaded images from the asset bundle, keyed by asset name.
  /// Populated in generateBytes() before processBlock() runs.
  final Map<String, pw.MemoryImage> _images = {};

  /// Base font size in points. Scaled by the `height` TEXT attribute.
  static const double _baseFontSize = 10.0;

  /// Points per QR size unit. size=8 -> 160pt (~56mm), suitable for A6.
  static const double _qrSizeScale = 20.0;

  /// Points per FEED line unit.
  static const double _feedLineHeight = 10.0;

  TemplatePdf({
    required this.template,
    required this.pageFormat,
    this.tables = const {},
    this.colorResolver,
    this.borderColor,
    this.assetLoader,
    this.borderWidth = 8.0,
  }) : _lines = template.split(';');

  /// Generate PDF bytes from the template.
  ///
  /// Uses [pw.MultiPage] so content that exceeds one page flows automatically
  /// (the queued DeliveryInvoice consumer has multi-item LOOPs that can exceed
  /// a single A6/A4 page). Still produces one PDF document from one doc.
  ///
  /// Throws [StateError] when the template yields NO widgets or when a QRCODE
  /// tag's data resolves to empty (a QR-less PDF is never shareable).
  Future<Uint8List> generateBytes() async {
    _variables.clear();
    _images.clear();
    await _preloadImages();

    final widgets = processBlock(0, _lines.length - 1, tables);
    if (widgets.isEmpty) {
      throw StateError('Template produced no content (no pages to render).');
    }
    final doc = pw.Document();

    // Single-mode margin: ensure content inset >= borderWidth when border
    // present. Floors at 28.35pt (A6 default = 1cm; note A4 default is
    // 2cm = 56.69pt). Keeps content clear of the border stroke.
    final pw.EdgeInsets? effectiveMargin = borderColor != null
        ? pw.EdgeInsets.all(
            borderWidth + 4.0 > 28.35 ? borderWidth + 4.0 : 28.35,
          )
        : null;

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pageFormat,
          margin: effectiveMargin,
          buildBackground: borderColor != null
              ? (pw.Context context) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: borderColor!,
                        width: borderWidth,
                      ),
                    ),
                  ),
                )
              : null,
        ),
        build: (pw.Context context) => widgets,
      ),
    );
    return doc.save();
  }

  /// Pre-load IMAGE tag assets from the template. Call once before any
  /// processBlock run. Populates [_images] for sync lookup during rendering.
  /// Missing/failed assets -> absent key -> silently skipped.
  Future<void> _preloadImages() async {
    if (assetLoader == null) return;
    final imageTagRegex = RegExp(r'<IMAGE\s+([^>]*?)/?>', caseSensitive: false);
    for (final line in _lines) {
      for (final match in imageTagRegex.allMatches(line)) {
        final attrs = parseAttributes(match.group(1)!);
        final primaryKey = _imgSourceKey(attrs);
        if (primaryKey.isNotEmpty && !_images.containsKey(primaryKey)) {
          // Attempt primary source (src/url/asset)
          pw.MemoryImage? img;
          try {
            final bytes = await assetLoader!(primaryKey);
            if (bytes != null) img = pw.MemoryImage(bytes);
          } catch (_) {
            // Network error, timeout, or undecodable bytes
          }
          // Fallback: if primary failed and a distinct asset key exists, try it
          if (img == null) {
            final fallbackKey = attrs['asset'] ?? '';
            if (fallbackKey.isNotEmpty && fallbackKey != primaryKey) {
              try {
                final bytes = await assetLoader!(fallbackKey);
                if (bytes != null) img = pw.MemoryImage(bytes);
              } catch (_) {
                // Asset not found or invalid -> skip silently
              }
            }
          }
          if (img != null) _images[primaryKey] = img;
        }
      }
    }
  }

  /// Generate a grid PDF: multiple cards tiled K columns x B rows per page.
  ///
  /// Each item in [items] is a doc-context map (same shape as [tables] for
  /// single mode). Template is walked once per item via [processBlock].
  /// Cards are wrapped in [pw.FittedBox] so content scales uniformly to fit
  /// each cell. Per-card border (when [borderColor] is set) is INSIDE the
  /// FittedBox, so [borderWidth] scales proportionally with the cell size.
  ///
  /// Items exceeding [gridCols] * [gridRows] overflow to additional pages.
  /// Throws [StateError] if [items] is empty (caller should guard before
  /// calling).
  Future<Uint8List> generateGridBytes({
    required List<Map<String, dynamic>> items,
    required int gridCols,
    required int gridRows,
  }) async {
    _variables.clear();
    _images.clear();
    await _preloadImages();

    if (items.isEmpty) {
      throw StateError('Grid mode: no items to render.');
    }

    // Minimal page margin for grid (maximize cell area).
    // Cell HEIGHT is not needed here -- rows/cells get their height from the
    // pw.Expanded layout below. Only cellW is used, as the SizedBox reference
    // width that lets _buildText's SizedBox(width: infinity) resolve finite
    // inside FittedBox. (The QR<25mm size warning lives at the widget layer.)
    const double gridMargin = 10.0;
    final double availW = pageFormat.width - 2 * gridMargin;
    final double cellW = availW / gridCols;

    final doc = pw.Document();
    final int cardsPerPage = gridCols * gridRows;

    for (
      int pageStart = 0;
      pageStart < items.length;
      pageStart += cardsPerPage
    ) {
      final int pageEnd = pageStart + cardsPerPage > items.length
          ? items.length
          : pageStart + cardsPerPage;
      final pageItems = items.sublist(pageStart, pageEnd);

      final List<pw.Widget> rows = [];
      for (int r = 0; r < gridRows; r++) {
        final List<pw.Widget> cells = [];
        for (int c = 0; c < gridCols; c++) {
          final int idx = r * gridCols + c;
          if (idx < pageItems.length) {
            // Build card content at cellW reference width so _buildText's
            // SizedBox(width: infinity) resolves to a finite value inside
            // FittedBox's unconstrained layout.
            final cardWidgets = processBlock(
              0,
              _lines.length - 1,
              pageItems[idx],
            );
            // W1 guard: a card that resolves to NO widgets gives its cell a
            // zero-height child. pw.FittedBox asserts `height > 0` (debug) or
            // produces a NaN transform -> blank/corrupt PDF silently shared
            // (release). Pad it, exactly like a missing trailing cell.
            if (cardWidgets.isEmpty) {
              cells.add(pw.Expanded(child: pw.SizedBox.shrink()));
              continue;
            }
            final pw.Widget cardColumn = pw.SizedBox(
              width: cellW,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: cardWidgets,
              ),
            );

            // Per-card border (inside FittedBox -> scales proportionally).
            pw.Widget cardContent;
            if (borderColor != null) {
              cardContent = pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: borderColor!,
                    width: borderWidth,
                  ),
                ),
                padding: pw.EdgeInsets.all(4),
                child: cardColumn,
              );
            } else {
              cardContent = cardColumn;
            }

            cells.add(
              pw.Expanded(
                child: pw.FittedBox(
                  fit: pw.BoxFit.contain,
                  // minHeight floor closes the residual zero-height case: a
                  // NON-empty card whose widgets all resolve to zero height
                  // (e.g. an all-empty <TEXT> with no QR/IMAGE/HR/FEED) would
                  // still trip FittedBox. Floored, FittedBox always divides by
                  // a height > 0. No-op for normal cards (natural height >> 1).
                  child: pw.ConstrainedBox(
                    constraints: const pw.BoxConstraints(minHeight: 1.0),
                    child: cardContent,
                  ),
                ),
              ),
            );
          } else {
            // Pad missing cells in the last page.
            cells.add(pw.Expanded(child: pw.SizedBox.shrink()));
          }
        }
        rows.add(pw.Expanded(child: pw.Row(children: cells)));
      }

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(gridMargin),
          build: (pw.Context context) => pw.Column(children: rows),
        ),
      );
    }

    return doc.save();
  }

  /// Process a range of template lines into a list of PDF widgets.
  /// Public for testability (interpolation is tested through this + [interpolate]).
  List<pw.Widget> processBlock(
    int start,
    int end,
    Map<String, dynamic> context,
  ) {
    final List<pw.Widget> widgets = [];
    int i = start;

    while (i <= end) {
      final line = _lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }

      final commandMatch = RegExp(r'^<(\/?\w+)\s*([^>]*)>').firstMatch(line);
      if (commandMatch != null) {
        final command = commandMatch.group(1)!.toUpperCase();
        final attributes = parseAttributes(commandMatch.group(2)!);
        final endBlockIndex = _findEndBlock(i, command);

        switch (command) {
          case 'HR':
            widgets.add(pw.Divider());
            break;
          case 'CUT':
            // ponytail: not applicable to PDF -- silently ignore
            break;
          case 'FEED':
            final linesToFeed = int.tryParse(attributes['lines'] ?? '1') ?? 1;
            widgets.add(pw.SizedBox(height: linesToFeed * _feedLineHeight));
            break;
          case 'QRCODE':
            final data = interpolate(attributes['data'] ?? '', context);
            if (data.isEmpty) {
              throw StateError(
                'QRCODE data resolved to empty '
                '(template token not yet populated or missing field).',
              );
            }
            final align = _getAlignment(attributes['align']);
            final size =
                (double.tryParse(attributes['size'] ?? '6') ?? 6.0) *
                _qrSizeScale;
            widgets.add(
              pw.Align(
                alignment: align,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: data,
                  width: size,
                  height: size,
                  drawText: false,
                ),
              ),
            );
            break;
          case 'IMAGE':
            final assetKey = _imgSourceKey(attributes);
            final img = _images[assetKey];
            if (img != null) {
              final align = _getAlignment(attributes['align']);
              widgets.add(
                pw.Align(alignment: align, child: _buildImage(img, attributes)),
              );
            }
            // else: asset not found -> skip silently (spec requirement)
            break;
          case 'TEXT':
            final singleLineContentMatch = RegExp(
              r'^<TEXT[^>]*>([\s\S]*)<\/TEXT>$',
            ).firstMatch(line);
            if (singleLineContentMatch != null) {
              final content = singleLineContentMatch.group(1)!;
              widgets.add(
                _buildText(interpolate(content, context), attributes),
              );
            } else if (endBlockIndex != -1) {
              final content = _lines.sublist(i + 1, endBlockIndex).join(';');
              widgets.add(
                _buildText(
                  interpolate(content, context).replaceAll(';', '\n'),
                  attributes,
                ),
              );
              i = endBlockIndex;
            }
            // else: unclosed TEXT -- silently skip
            break;
          case 'ROW':
            final singleLineRowMatch = RegExp(
              r'^<ROW[^>]*>([\s\S]*)<\/ROW>$',
            ).firstMatch(line);
            if (singleLineRowMatch != null) {
              widgets.add(
                _buildRow(singleLineRowMatch.group(1)!, context, attributes),
              );
            } else if (endBlockIndex != -1) {
              widgets.add(
                _buildMultiLineRow(
                  i + 1,
                  endBlockIndex - 1,
                  context,
                  attributes,
                ),
              );
              i = endBlockIndex;
            }
            break;
          case 'LOOP':
            final singleLineLoopMatch = RegExp(
              r'^<LOOP[^>]*>([\s\S]*)<\/LOOP>$',
            ).firstMatch(line);
            if (singleLineLoopMatch != null) {
              widgets.addAll(
                _processSingleLineLoop(
                  singleLineLoopMatch.group(1)!,
                  attributes,
                  context,
                ),
              );
            } else if (endBlockIndex != -1) {
              widgets.addAll(
                _processMultiLineLoop(
                  i + 1,
                  endBlockIndex - 1,
                  attributes,
                  context,
                ),
              );
              i = endBlockIndex;
            }
            break;
          case 'GROUP_BY':
            // ponytail: out of scope v1 -- silently skip block
            if (endBlockIndex != -1) {
              i = endBlockIndex;
            }
            break;
          case 'ACCUMULATE':
            // ponytail: out of scope v1 -- silently skip
            break;
          default:
            // Unknown tag -- silently ignore, never render raw tag
            break;
        }
      } else {
        // Plain text (no tag wrapper)
        final interpolated = interpolate(line, context);
        if (interpolated.isNotEmpty) {
          widgets.add(pw.Text(interpolated));
        }
      }
      i++;
    }
    return widgets;
  }

  // ── TEXT helper ──────────────────────────────────────────────────────

  pw.Widget _buildText(String content, Map<String, String> attributes) {
    final align = _getTextAlign(attributes['align']);
    final bold = (attributes['bold'] ?? 'false') == 'true';
    final underline = (attributes['underline'] ?? 'false') == 'true';
    final height = int.tryParse(attributes['height'] ?? '1') ?? 1;
    final fontSize = _baseFontSize * height;
    final color = _resolveColor(attributes['color']);

    // Wrap in SizedBox(width: infinity) to force full available width.
    // Without this, pw.Text takes intrinsic width and textAlign has no
    // visible effect (verified in pdf 3.13.0 text.dart:921-923).
    return pw.SizedBox(
      width: double.infinity,
      child: pw.Text(
        content,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          decoration: underline
              ? pw.TextDecoration.underline
              : pw.TextDecoration.none,
          color: color,
        ),
      ),
    );
  }

  // ── ROW / COL helpers ───────────────────────────────────────────────

  pw.Widget _buildRow(
    String content,
    Map<String, dynamic> context, [
    Map<String, String> rowAttributes = const {},
  ]) {
    final List<pw.Widget> cols = [];
    final colMatches = RegExp(
      r'<COL\s*([^>]*)>([\s\S]*?)<\/COL>',
    ).allMatches(content);

    for (final colMatch in colMatches) {
      final colAttrs = parseAttributes(colMatch.group(1)!);
      final rawColContent = colMatch.group(2)!;
      final colWidth = int.tryParse(colAttrs['width'] ?? '1') ?? 1;

      cols.add(
        pw.Expanded(
          flex: colWidth,
          child: _buildColChild(rawColContent, colAttrs, context),
        ),
      );
    }

    if (cols.isEmpty) return pw.SizedBox.shrink();
    return pw.Row(
      crossAxisAlignment: _getCrossAxisAlignment(rowAttributes['align']),
      children: cols,
    );
  }

  pw.Widget _buildMultiLineRow(
    int start,
    int end,
    Map<String, dynamic> context, [
    Map<String, String> rowAttributes = const {},
  ]) {
    final List<pw.Widget> cols = [];
    int i = start;
    while (i <= end) {
      final line = _lines[i].trim();
      final colMatch = RegExp(
        r'^<COL\s*([^>]*)>([\s\S]*)<\/COL>',
      ).firstMatch(line);
      if (colMatch != null) {
        final colAttrs = parseAttributes(colMatch.group(1)!);
        final rawColContent = colMatch.group(2)!;
        final colWidth = int.tryParse(colAttrs['width'] ?? '1') ?? 1;

        cols.add(
          pw.Expanded(
            flex: colWidth,
            child: _buildColChild(rawColContent, colAttrs, context),
          ),
        );
      }
      i++;
    }
    if (cols.isEmpty) return pw.SizedBox.shrink();
    return pw.Row(
      crossAxisAlignment: _getCrossAxisAlignment(rowAttributes['align']),
      children: cols,
    );
  }

  // ── LOOP helpers ────────────────────────────────────────────────────

  List<pw.Widget> _processSingleLineLoop(
    String content,
    Map<String, String> attributes,
    Map<String, dynamic> context,
  ) {
    final List<pw.Widget> widgets = [];
    final sourceName = attributes['source'];

    if (sourceName == null || sourceName.isEmpty) return widgets;

    final dynamic rawSourceData = tables[sourceName];
    // ponytail: missing/non-List source -> empty, never raw tag (Prior Correction #1)
    if (rawSourceData == null || rawSourceData is! List) return widgets;

    // Map-tolerance for keyed PRN variant: Map items pass through unchanged,
    // positional List items coerced to List<String>. Mirrors template_printer.dart L268.
    // NOTE: no `as List` -- the `is!` guard above already promotes
    // rawSourceData to List; an explicit cast trips `unnecessary_cast`.
    // Keep `rawSourceData` declared `final`: promotion is what keeps `.map` a
    // STATIC call. Make it non-final or reassign it and promotion silently
    // disappears, `.map` degrades to a dynamic invocation and the element type
    // collapses to `dynamic` -- with no analyzer error to warn you.
    final sourceData = rawSourceData.map((row) {
      if (row is Map) return row;
      return (row as List).map((cell) => cell.toString()).toList();
    }).toList();

    for (final item in sourceData) {
      final itemContext = Map<String, dynamic>.from(context)..['item'] = item;
      final commandMatches = RegExp(
        r'<(\w+)\s*([^>]*?)(?:\/>|>([\s\S]*?)<\/\1>)',
      ).allMatches(content);

      for (final match in commandMatches) {
        final command = match.group(1)!.toUpperCase();
        final attrs = parseAttributes(match.group(2)!);
        final innerContent = match.group(3);

        switch (command) {
          case 'ROW':
            if (innerContent != null) {
              widgets.add(_buildRow(innerContent, itemContext, attrs));
            }
            break;
          case 'TEXT':
            if (innerContent != null) {
              widgets.add(
                _buildText(interpolate(innerContent, itemContext), attrs),
              );
            }
            break;
          case 'IMAGE':
            final imgAssetKey = _imgSourceKey(attrs);
            final img = _images[imgAssetKey];
            if (img != null) {
              final imgAlign = _getAlignment(attrs['align']);
              widgets.add(
                pw.Align(alignment: imgAlign, child: _buildImage(img, attrs)),
              );
            }
            break;
          // Other tags inside single-line LOOP silently ignored
        }
      }
    }
    return widgets;
  }

  List<pw.Widget> _processMultiLineLoop(
    int start,
    int end,
    Map<String, String> attributes,
    Map<String, dynamic> context,
  ) {
    final List<pw.Widget> widgets = [];
    final sourceName = attributes['source'];

    if (sourceName == null || sourceName.isEmpty) return widgets;

    final dynamic rawSourceData = tables[sourceName];
    if (rawSourceData == null || rawSourceData is! List) return widgets;

    // NOTE: no `as List` -- the `is!` guard above already promotes
    // rawSourceData to List; an explicit cast trips `unnecessary_cast`.
    // Keep `rawSourceData` declared `final`: promotion is what keeps `.map` a
    // STATIC call. Make it non-final or reassign it and promotion silently
    // disappears, `.map` degrades to a dynamic invocation and the element type
    // collapses to `dynamic` -- with no analyzer error to warn you.
    final sourceData = rawSourceData.map((row) {
      if (row is Map) return row;
      return (row as List).map((cell) => cell.toString()).toList();
    }).toList();

    for (final item in sourceData) {
      final itemContext = Map<String, dynamic>.from(context)..['item'] = item;
      widgets.addAll(processBlock(start, end, itemContext));
    }
    return widgets;
  }

  // ── Block structure helper ──────────────────────────────────────────

  /// Find the matching closing tag for a block starting at [startIndex].
  /// Returns -1 if not found. Mirrors template_printer.dart L354.
  int _findEndBlock(int startIndex, String command) {
    int level = 1;
    final closeTag = '</$command>';
    for (int i = startIndex + 1; i < _lines.length; i++) {
      final line = _lines[i].trim();
      if (line.startsWith('<$command')) {
        level++;
      } else if (line == closeTag) {
        level--;
        if (level == 0) return i;
      }
    }
    return -1;
  }

  // ── Alignment helpers ───────────────────────────────────────────────

  pw.Alignment _getAlignment(String? alignStr) {
    switch (alignStr?.toLowerCase()) {
      case 'center':
        return pw.Alignment.center;
      case 'right':
        return pw.Alignment.centerRight;
      default:
        return pw.Alignment.centerLeft;
    }
  }

  pw.TextAlign _getTextAlign(String? alignStr) {
    switch (alignStr?.toLowerCase()) {
      case 'center':
        return pw.TextAlign.center;
      case 'right':
        return pw.TextAlign.right;
      default:
        return pw.TextAlign.left;
    }
  }

  // ── Cross-axis alignment helper (for ROW) ─────────────────────────

  pw.CrossAxisAlignment _getCrossAxisAlignment(String? alignStr) {
    switch (alignStr?.toLowerCase()) {
      case 'center':
        return pw.CrossAxisAlignment.center;
      case 'end':
      case 'bottom':
        return pw.CrossAxisAlignment.end;
      default:
        return pw.CrossAxisAlignment.start;
    }
  }

  // ── Color helper ──────────────────────────────────────────────────

  /// Resolve a named color string to PdfColor via [colorResolver].
  /// Returns [PdfColors.black] when name is absent/empty or resolver is null.
  PdfColor _resolveColor(String? colorName) {
    if (colorName == null || colorName.isEmpty) return PdfColors.black;
    if (colorResolver != null) return colorResolver!(colorName);
    return PdfColors.black;
  }

  // ── IMAGE helpers ─────────────────────────────────────────────────

  /// Build a pw.Image widget from a pre-loaded MemoryImage and its attributes.
  /// Width/height in pt are optional; absent -> natural size constrained by parent.
  pw.Widget _buildImage(pw.MemoryImage img, Map<String, String> attributes) {
    final imgWidth = double.tryParse(attributes['width'] ?? '');
    final imgHeight = double.tryParse(attributes['height'] ?? '');
    return pw.Image(img, width: imgWidth, height: imgHeight);
  }

  /// Image source key for an `<IMAGE>` tag: `src` (network URL) takes
  /// precedence over `url` (legacy alias) over bundle `asset` key.
  /// Both `src` and `url` resolve to the same fetch path via [assetLoader].
  String _imgSourceKey(Map<String, String> attributes) {
    final src = attributes['src'];
    if (src != null && src.isNotEmpty) return src;
    final url = attributes['url'];
    if (url != null && url.isNotEmpty) return url;
    return attributes['asset'] ?? '';
  }

  /// Build the child widget for a COL element. Detects IMAGE tag content and
  /// renders pw.Image; otherwise interpolates and renders pw.Text.
  /// Extracted to avoid duplication between _buildRow and _buildMultiLineRow.
  pw.Widget _buildColChild(
    String rawContent,
    Map<String, String> colAttrs,
    Map<String, dynamic> context,
  ) {
    final imageTagMatch = RegExp(
      r'^<IMAGE\s+([^>]*?)\s*/?>$',
    ).firstMatch(rawContent.trim());
    if (imageTagMatch != null) {
      final imgAttrs = parseAttributes(imageTagMatch.group(1)!);
      final img = _images[_imgSourceKey(imgAttrs)];
      if (img != null) {
        return pw.Align(
          alignment: _getAlignment(colAttrs['align']),
          child: _buildImage(img, imgAttrs),
        );
      }
      return pw.SizedBox.shrink();
    }

    final content = interpolate(rawContent, context);
    final bold = (colAttrs['bold'] ?? 'false') == 'true';
    final align = _getTextAlign(colAttrs['align']);
    return pw.Text(
      content,
      textAlign: align,
      style: pw.TextStyle(
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
  }

  // ── Attribute parser ────────────────────────────────────────────────

  /// Parse HTML-style attributes. Supports single, double, and bare-value quoting.
  /// Mirrors template_printer.dart L517-531 exactly.
  Map<String, String> parseAttributes(String attributeString) {
    final Map<String, String> attributes = {};
    final matches = RegExp(
      '(\\w+)\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s/>]+))',
    ).allMatches(attributeString);
    for (final match in matches) {
      final key = match.group(1)!;
      final value = match.group(2) ?? match.group(3) ?? match.group(4)!;
      attributes[key] = value;
    }
    return attributes;
  }

  // ── Interpolation ───────────────────────────────────────────────────

  /// Replace `{{key}}` / `{{key|formatter}}` tokens in [text] using [context].
  /// Mirrors template_printer.dart L404-514. Public for testability.
  ///
  /// Differences from ESC/POS version (see class doc):
  /// - On exception during path traversal, returns '' (empty) instead of the
  ///   raw `{{...}}` token. PDF must never render a raw template token.
  /// - Expression parse failure falls back to path resolution instead of '!ERR!'.
  String interpolate(
    String text,
    Map<String, dynamic> context, {
    bool evaluate = true,
    bool format = true,
  }) {
    return text.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) {
      String valueAsString;
      final String fullKey = match.group(1)!.trim();
      final keyParts = fullKey.split('|').map((p) => p.trim()).toList();
      final String key = keyParts[0];
      final String? formatter = keyParts.length > 1 ? keyParts[1] : null;

      // 1. Table array access: {{tableName[row][col]}}
      final tableAccessMatch = RegExp(
        r'^(\w+)\s*\[\s*(\d+)\s*\]\s*\[\s*(\d+)\s*\]$',
      ).firstMatch(key);
      if (tableAccessMatch != null) {
        try {
          final tableName = tableAccessMatch.group(1)!;
          final userRowIndex = int.parse(tableAccessMatch.group(2)!);
          final colIndex = int.parse(tableAccessMatch.group(3)!);
          final rowIndex = userRowIndex - 1; // Row is 1-based

          final table = context[tableName] as List?;
          if (table != null && rowIndex >= 0 && rowIndex < table.length) {
            final row = table[rowIndex] as List?;
            if (row != null && colIndex >= 0 && colIndex < row.length) {
              valueAsString = row[colIndex]?.toString() ?? '';
            } else {
              valueAsString = '';
            }
          } else {
            valueAsString = '';
          }
        } catch (e) {
          valueAsString = '';
        }
      }
      // 2. Expression evaluation (arithmetic operators)
      // ponytail: known false-positive on '-' in field names (e.g. item-name).
      // Mirrors template_printer.dart behavior. Upgrade: smarter tokenizer.
      // DIVERGENCE: on parse failure, falls back to _resolveByPath instead of
      // emitting '!ERR!' -- see class doc.
      else if (evaluate &&
          (key.contains('*') ||
              key.contains('/') ||
              key.contains('+') ||
              key.contains('-'))) {
        String processedExpression = _replaceItemPlaceholders(key, context);
        try {
          final result = const ExpressionEvaluator().eval(
            Expression.parse(processedExpression),
            {},
          );
          valueAsString = (result is num && result % 1 == 0)
              ? result.toInt().toString()
              : result.toString();
        } catch (e) {
          // Expression failed -- fall through to path traversal.
          // DIVERGENCE from template_printer.dart which emits '!ERR!'.
          valueAsString = _resolveByPath(key, context);
        }
      }
      // 3. Accumulated variables
      // ponytail: _variables is write-never today (ACCUMULATE out of scope v1).
      // Branch kept for parity; activates when ACCUMULATE support lands.
      else if (_variables.containsKey(key)) {
        valueAsString = _variables[key].toString();
      }
      // 4. Path traversal: {{field}}, {{item.field}}, {{item.field.sub}}
      else {
        valueAsString = _resolveByPath(key, context);
      }

      // Apply formatter
      if (format && formatter != null) {
        final defaultMatch = RegExp(r'^default:(.*)$').firstMatch(formatter);
        if (defaultMatch != null) {
          return valueAsString.isEmpty ? defaultMatch.group(1)! : valueAsString;
        }
        final idrMatch = RegExp(r'^idr(\d*)$').firstMatch(formatter);
        if (idrMatch != null) {
          return _formatIdr(
            valueAsString,
            idrMatch.group(1)!.isEmpty ? 0 : int.parse(idrMatch.group(1)!),
          );
        }
        final usdMatch = RegExp(r'^usd(\d*)$').firstMatch(formatter);
        if (usdMatch != null) {
          return _formatUsd(
            valueAsString,
            usdMatch.group(1)!.isEmpty ? 2 : int.parse(usdMatch.group(1)!),
          );
        }
      }
      return valueAsString;
    });
  }

  /// Resolve a dotted/bracketed key path against [context].
  /// Returns '' on any failure -- never a raw token.
  String _resolveByPath(String key, Map<String, dynamic> context) {
    var parts = key.split(RegExp(r'[.\[\]]+'))..removeWhere((p) => p.isEmpty);
    dynamic currentValue = context;
    try {
      for (final part in parts) {
        if (currentValue == null) break;
        if (currentValue is Map) {
          currentValue = currentValue[part];
        } else if (currentValue is List) {
          if (part == 'count') {
            currentValue = currentValue.length;
            break;
          }
          final userIndex = int.tryParse(part);
          if (userIndex == null || userIndex < 0) {
            currentValue = null;
            break;
          }
          currentValue = (userIndex < currentValue.length)
              ? currentValue[userIndex]
              : null;
        } else {
          currentValue = null;
          break;
        }
      }
      return currentValue?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Replace item[N] placeholders with numeric values for expression evaluation.
  /// Mirrors template_printer.dart L36-49, EXCEPT for the guard below.
  ///
  /// DIVERGENCE: type-tests `context['item']` instead of casting it. The LOOP
  /// walkers deliberately allow a Map item (keyed PRN variant), and this method
  /// is called OUTSIDE interpolate's try/catch -- so template_printer.dart's
  /// `as List<dynamic>?` throws a _TypeError straight past the renderer and
  /// kills the whole PDF for `{{item.qt * item.hg}}` or any hyphenated field
  /// name over Map items. Non-List items simply have no `item[N]` placeholders
  /// to substitute, so returning the expression unchanged is correct and lets
  /// the caller fall back to path resolution.
  String _replaceItemPlaceholders(
    String expression,
    Map<String, dynamic> context,
  ) {
    // `itemData` must stay `final` -- the `is!` test below is what promotes it
    // to List and keeps `.length`/`[]` static calls.
    final itemData = context['item'];
    if (itemData is! List) return expression;

    return expression.replaceAllMapped(RegExp(r'item\[(\d+)\]'), (match) {
      final userIndex = int.tryParse(match.group(1)!) ?? 0;
      if (userIndex < 0) return '0';
      if (userIndex < itemData.length) {
        return itemData[userIndex].toString();
      }
      return '0';
    });
  }

  // ── Number formatters ───────────────────────────────────────────────

  /// IDR format: dot thousands, comma decimals. Mirrors template_printer.dart L373.
  ///
  /// DIVERGENCE: non-numeric input is passed through unchanged (the ESC/POS
  /// renderer returns '0'). This avoids silent data loss on pre-formatted
  /// strings like '1.250.000'. See class doc.
  String _formatIdr(String numberString, int decimalDigits) {
    try {
      if (double.tryParse(numberString.replaceAll(',', '')) == null) {
        return numberString;
      }
      final number = double.tryParse(numberString.replaceAll(',', '')) ?? 0.0;
      final formattedString = number.toStringAsFixed(decimalDigits);
      final parts = formattedString.split('.');
      final integerPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      );
      return decimalDigits > 0 ? '$integerPart,${parts[1]}' : integerPart;
    } catch (e) {
      return numberString;
    }
  }

  /// USD format: comma thousands, dot decimals. Mirrors template_printer.dart L391.
  String _formatUsd(String numberString, int decimalDigits) {
    try {
      final number = double.tryParse(numberString.replaceAll(',', '')) ?? 0.0;
      final formattedString = number.toStringAsFixed(decimalDigits);
      final parts = formattedString.split('.');
      final integerPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      return decimalDigits > 0 ? '$integerPart.${parts[1]}' : integerPart;
    } catch (e) {
      return numberString;
    }
  }
}

// ── File name helper (top-level for testability) ────────────────────

/// Resolve `{{field}}` tokens in a file name string and sanitize for filesystem.
/// Empty/absent result defaults to 'share.pdf'.
///
/// The token pattern is `[^}]+` (not `\w+`) so a dot-path token like
/// `{{item.in}}` is CONSUMED and resolved-or-emptied rather than surviving the
/// brace strip as the bare text `item.in` -- otherwise an unresolved token
/// leaks its own NAME into the shared file name ('N-{{item.in}}.pdf' would
/// become 'N-item.in.pdf'). Only top-level scalar keys resolve; anything else
/// yields ''. Curly braces stay in the strip set for stray/unmatched braces.
String resolveAndSanitizeFileName(
  String template,
  Map<String, dynamic> context,
) {
  final resolved = template.replaceAllMapped(
    RegExp(r'\{\{([^}]+)\}\}'),
    (m) => context[m.group(1)!.trim()]?.toString() ?? '',
  );
  final sanitized = resolved
      .replaceAll(RegExp(r'[<>:"/\\|?*{}]'), '')
      .replaceAll(RegExp(r'[\x00-\x1f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // A leading '.' means every name part resolved away (e.g. '{{missing}}.pdf'
  // -> '.pdf'), which would share a nameless hidden file.
  if (sanitized.isEmpty || sanitized.startsWith('.')) return 'share.pdf';
  return sanitized.toLowerCase().endsWith('.pdf')
      ? sanitized
      : '$sanitized.pdf';
}
