import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import 'panel_card_support.dart';
import 'statistic_card_support.dart';
import 'timeline_periodic_support.dart';

/// TIMELINE variant `periodic` — config-driven event timeline. Default
/// behavior derives `{method}` and `{evidence}` from the `evidenceField` doc
/// field (default `lq`, for patrol QR-scan). Generic reuse: put `<charcode>`
/// tokens in `badge`/`text` instead of `{method}`/`{evidence}`, and set
/// `statusField` for dot/badge coloring from a doc field.
///
/// Binds to a Firestore map collection via `table` / `vidtable`, filters by
/// `conditions`, windows by a period selector, and renders newest-first
/// vertical timeline entries with gap pills, image galleries, and a
/// configurable footer.
class TimelinePeriodic extends StatefulWidget {
  const TimelinePeriodic({
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
  State<TimelinePeriodic> createState() => _TimelinePeriodicState();
}

const String _kDefaultFooter =
    'Catatan tak bisa diubah. Setiap kunjungan terkunci sejak dibuat. '
    'Sistem tidak menyajikan "rata-rata" atau "frekuensi normal" — itu bisa '
    'dibaca sebagai standar.';

class _TimelinePeriodicState extends State<TimelinePeriodic> {
  List<PeriodOption> _periods = [];
  int _selectedMs = 604800000;
  int _gapMs = 43200000;
  String _eventCode = '';
  int _nowMs = 0;
  int _windowStartMs = 0;
  String _evidenceField = 'lq';
  String? _statusField;
  String _emptyText = 'Belum ada kunjungan';

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribe();
  }

  void _initConfig() {
    final String periodRaw = (widget.component['period'] ?? '').toString();
    _periods = parsePeriods(autheniumDecode(periodRaw) ?? periodRaw);
    _gapMs =
        int.tryParse((widget.component['gapMs'] ?? '').toString()) ?? 43200000;
    final int def =
        int.tryParse((widget.component['periodDefault'] ?? '').toString()) ?? 0;
    _selectedMs = _periods.any((p) => p.ms == def)
        ? def
        : (_periods.isNotEmpty ? _periods.first.ms : 604800000);
    _evidenceField =
        (widget.component['evidenceField'] ?? '').toString().trim().isEmpty
        ? 'lq'
        : widget.component['evidenceField'].toString().trim();
    final String sfRaw = (widget.component['statusField'] ?? '')
        .toString()
        .trim();
    _statusField = sfRaw.isEmpty ? null : sfRaw;
    final String emptyRaw = (widget.component['empty'] ?? '').toString().trim();
    _emptyText = emptyRaw.isEmpty ? 'Belum ada kunjungan' : emptyRaw;
  }

  void _subscribe() {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    final String appVid = (widget.component['vidtable'] ?? '')
        .toString()
        .trim();
    if (tp.tableDocId.isEmpty || appVid.isEmpty) return;
    // vid-scoped: mapTableContent/_mapSubscribed key by code; without vid a
    // same tableDocId/subColl on another tenant dedups our stream away.
    _eventCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
    subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _eventCode);
  }

  Map<String, dynamic> get _screenTx => transactionStore.state.screenTx;

  /// Split the resolved image field into individual URLs (mirrors getImageList:
  /// normalize ◆/space → ◇ separator, then split). Skips blanks + the default.
  List<String> _splitImages(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .replaceAll(separator[6], separator[5])
        .replaceAll(' ', separator[5])
        .split(separator[5])
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && u != defaultImage)
        .toList();
  }

  void _showFullImage(BuildContext ctx, List<String> urls, int initial) {
    Navigator.of(ctx).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) =>
            _FullImageViewer(urls: urls, initialIndex: initial),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final List<Map<String, dynamic>> events = List<Map<String, dynamic>>.from(
        mapTableContent[_eventCode] ?? const [],
      );
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _windowStartMs = _nowMs - _selectedMs;

      final String conditionsRaw = (widget.component['conditions'] ?? '')
          .toString();
      final String conditions = autheniumDecode(conditionsRaw) ?? conditionsRaw;
      final List<Map<String, dynamic>> matched = filterEventsByConditions(
        events,
        conditions,
        _screenTx,
      );
      final List<Map<String, dynamic>> windowed =
          matched.where((e) => eventEpoch(e) >= _windowStartMs).toList()
            ..sort((a, b) => eventEpoch(b).compareTo(eventEpoch(a)));

      final String pointName =
          (_screenTx['point'] ??
                  (windowed.isNotEmpty ? windowed.first['ln'] : '') ??
                  '')
              .toString();
      final String title = resolveMapTokens(
        (widget.component['title'] ?? '').toString(),
        {'ln': pointName},
        const {},
      );
      final String subtitle = resolveMapTokens(
        (widget.component['subtitle'] ?? '').toString(),
        const {},
        {'visitCount': '${windowed.length}'},
      );

      final List<Widget> entries = [];
      for (int i = 0; i < windowed.length; i++) {
        entries.add(_buildEntry(windowed[i]));
        if (i < windowed.length - 1) {
          final String gap = gapLabel(
            eventEpoch(windowed[i]),
            eventEpoch(windowed[i + 1]),
            _gapMs,
          );
          if (gap.isNotEmpty) entries.add(_buildGapPill(gap));
        }
      }

      final double availableH = MediaQuery.of(context).size.height * 0.82;

      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2233),
                  ),
                ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9AA1AD),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_periods.isNotEmpty) _buildPeriodTabs(),
              const SizedBox(height: 14),
              Expanded(
                child: windowed.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          ...entries,
                          const SizedBox(height: 14),
                          _buildFooter(),
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildPeriodTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final p in _periods)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedMs = p.ms),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.ms == _selectedMs
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: p.ms == _selectedMs
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    p.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.ms == _selectedMs
                          ? const Color(0xFF1A2233)
                          : const Color(0xFF8A93A6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        _emptyText,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
    );
  }

  /// Left rail: a continuous vertical line with a hollow status-colored dot.
  Widget _rail(Color ringColor, {IconData? icon}) {
    return SizedBox(
      width: 30,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: Center(
              child: Container(width: 2, color: const Color(0xFFE5E7EB)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: icon != null
                ? Icon(icon, size: 16, color: ringColor)
                : Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: ringColor, width: 3),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(Map<String, dynamic> e) {
    final String textTemplate = (widget.component['text'] ?? '').toString();
    final String badgeTemplate =
        (widget.component['badge'] ?? '').toString().trim().isEmpty
        ? '{evidence}'
        : widget.component['badge'].toString();

    final String rawLq = (e[_evidenceField] ?? '').toString();
    final String evidence = deriveEvidence(rawLq);
    final MethodInfo method = deriveMethod(rawLq);
    final Color dotColor = resolveStatusColor(_statusField, e, evidence);

    final Map<String, String> computed = {
      'method': method.label,
      'evidence': evidence,
    };
    final Map<String, dynamic> doc = Map<String, dynamic>.from(e)
      ..['ts'] = relativeTimestamp(eventEpoch(e), _nowMs);
    final List<String> seg = diamondTextToList(
      resolveMapTokens(textTemplate, doc, computed),
    );
    String at(int i) => seg.length > i ? seg[i] : '';
    final List<String> imageUrls = _splitImages(
      resolveMapTokens(
        (widget.component['image'] ?? '').toString(),
        doc,
        const {},
      ),
    );

    final String resolvedBadge = resolveMapTokens(badgeTemplate, doc, computed);
    final bool showShieldIcons = badgeContainsEvidence(badgeTemplate);
    final bool showMethodIcon = textContainsMethod(textTemplate);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(dotColor),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEEF0F2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            at(0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A2233),
                            ),
                          ),
                        ),
                        if (resolvedBadge.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _evidenceBadge(
                            resolvedBadge,
                            evidence,
                            showShieldIcons,
                            e,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          at(1),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        if (showMethodIcon) ...[
                          const SizedBox(width: 10),
                          Icon(
                            method.isQr ? Icons.qr_code_2 : Icons.text_fields,
                            size: 15,
                            color: const Color(0xFF9AA1AD),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            at(2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (at(3).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '"${at(3)}"',
                        style: const TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF9AA1AD),
                        ),
                      ),
                    ],
                    if (imageUrls.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: imageUrls.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (ctx, idx) => GestureDetector(
                            onTap: () => _showFullImage(ctx, imageUrls, idx),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                imageUrls[idx],
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 96,
                                  height: 96,
                                  color: const Color(0xFFF1F3F5),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    size: 20,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGapPill(String label) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(const Color(0xFFD97706), icon: Icons.hourglass_bottom),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF1D08A)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _evidenceBadge(
    String resolvedText,
    String evidence,
    bool showShieldIcons,
    Map<String, dynamic> doc,
  ) {
    final Color fg = resolveStatusColor(_statusField, doc, evidence);
    final Color bg = resolveStatusBgColor(_statusField, doc, evidence);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showShieldIcons) ...[
            Icon(
              evidence == 'Bukti kuat'
                  ? Icons.verified_user_rounded
                  : Icons.gpp_maybe_rounded,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            resolvedText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final String raw = (widget.component['footer'] ?? '').toString().trim();
    if (raw == '-') return const SizedBox.shrink();
    final String footer = raw.isNotEmpty ? raw : _kDefaultFooter;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 16, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              footer,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen swipeable + zoomable image viewer (mirrors item_card_detail).
class _FullImageViewer extends StatefulWidget {
  const _FullImageViewer({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<_FullImageViewer> {
  late PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    widget.urls[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
