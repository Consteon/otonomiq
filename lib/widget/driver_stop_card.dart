import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../redux/screen_transaction.dart';
import 'driver_home_support.dart';
import 'panel_card_support.dart';

/// DRIVER_STOP_CARD — "Rute Hari Ini" stop list + progress (DriverHome P4).
///
/// Pending (!confirmed): locked preview (title + stop count + hint + numbered
/// list). Confirmed: active list + progress bar + per-stop badges + CTA.
class DriverStopCard extends StatefulWidget {
  const DriverStopCard({
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
  State<DriverStopCard> createState() => _DriverStopCardState();
}

class _DriverStopCardState extends State<DriverStopCard> {
  List<String> _textArray = [];
  String _dataCode = ''; // task subscription code
  String _gateCode = ''; // vehicle_check gate subscription code

  @override
  void initState() {
    super.initState();
    _parseText();
    _subscribe();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (20 slots; 18 original + 2 reject):
  ///  [0]  "Stop Berikutnya"
  ///  [1]  "Dilaporkan Gagal"
  ///  [2]  "Sudah Selesai"
  ///  [3]  "Pilih sesuai kondisi lapangan"
  ///  [4]  "Mulai Eksekusi"
  ///  [5]  "Selesai"
  ///  [6]  "Customer confirmed"
  ///  [7]  "Dilaporkan gagal — menunggu admin reschedule"
  ///  [8]  "kirim"
  ///  [9]  "ambil"
  ///  [10] "Pickup Only"
  ///  [11] "Rute Hari Ini"
  ///  [12] "{closed} dari {total} stop"
  ///  [13] "lanjut:"
  ///  [14] "semua kelar"
  ///  [15] "{total} tujuan"
  ///  [16] "Konfirmasi muatan dulu buat mulai — ini tujuan lo hari ini:"
  ///  [17] "Buka Tasklist (eksekusi)"
  ///  [18] "Tolak"  (reject button label; gated by rejectRoute)
  ///  [19] "Ada stop nggak searah? Tolak sebelum berangkat, dikembalikan ke Admin."  (footnote)
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  void _subscribe() {
    final String appVid = resolveAppVid(widget.component);

    // Primary data table (task)
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isNotEmpty) {
      // vid-scoped: mapTableContent/_mapSubscribed key omits vid; another tenant's same tableDocId/subColl would dedup our stream away.
      _dataCode = '$appVid/${tp.tableDocId}/${tp.subColl}';
      subscribeToMapCollection(appVid, tp.tableDocId, tp.subColl, _dataCode);
    }

    // Gate table (vehicle_check) — for self-gating locked/active state
    final String rawGateTable = (widget.component['gateTable'] ?? '')
        .toString()
        .trim();
    if (rawGateTable.isNotEmpty) {
      final TablePath gtp = parseTablePath(rawGateTable);
      if (gtp.tableDocId.isNotEmpty) {
        _gateCode = '$appVid/${gtp.tableDocId}/${gtp.subColl}';
        subscribeToMapCollection(
          appVid,
          gtp.tableDocId,
          gtp.subColl,
          _gateCode,
        );
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredStops() {
    final List<Map<String, dynamic>> docs = List<Map<String, dynamic>>.from(
      mapTableContent[_dataCode] ?? const [],
    );
    final String rawSearch = (widget.component['search'] ?? '')
        .toString()
        .trim();
    final String rawExclude = (widget.component['excludeStatus'] ?? '')
        .toString()
        .trim();
    final String excludeStatus = rawExclude.isEmpty
        ? kDefaultExcludeStatus
        : rawExclude;

    List<Map<String, dynamic>> filtered = rawSearch.isEmpty
        ? docs
        : filterDriverHomeDocs(docs, rawSearch, widget.scrName);

    // Drop tasks with excluded status (e.g. load_rejected). Opt-in: empty
    // excludeStatus = no exclusion. Raw tst compare, NOT stopStatusOf.
    return excludeByStatus(filtered, excludeStatus);
  }

  void _onCtaTap() {
    final String route = (widget.component['route'] ?? '').toString().trim();
    if (route.isEmpty) return;
    if (routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Layar belum tersedia'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _onRejectTap(Map<String, dynamic> stop) {
    final String rejectRoute = (widget.component['rejectRoute'] ?? '')
        .toString()
        .trim();
    if (rejectRoute.isEmpty) return;

    final String taskIdField = (widget.component['taskIdField'] ?? 'tnm')
        .toString();
    final String taskVid = (stop[taskIdField] ?? '').toString().trim();
    if (taskVid.isEmpty) return;

    // Dispatch #REJECT_TASK so the reject sheet can resolve {rejectTaskVid}
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'#REJECT_TASK': taskVid})),
    );

    if (routeExist(rejectRoute)) {
      routeStack.push(rejectRoute);
      gotoRoute(rejectRoute);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Layar belum tersedia'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final DriverHomeState dhState = getDriverHomeState(widget.scrName);
      // Touch confirmed + vehicleId to register Obx dependency (search uses
      // vehicleId; confirmed kept reactive even though gating is self-driven).
      dhState.confirmed.value;
      dhState.vehicleId.value;
      dhState.activeTrip.value; // register activeTrip dependency (GAP B fix)

      // ── Vehicle scope gate (scope-leak prevention) ──────────────────
      // When the driver has no assigned vehicle, hide the card entirely.
      // Prevents rendering the pending "N tujuan" preview with empty data,
      // and critically prevents Tolak/Konfirmasi buttons from appearing.
      if (dhState.vehicleIdResolved.value && dhState.vehicleId.value.isEmpty) {
        return const SizedBox.shrink();
      }

      // Fix 2: self-gate on own gateTable/gateSearch for locked/active state
      final String rawGateSearch = (widget.component['gateSearch'] ?? '')
          .toString()
          .trim();
      final bool gateConfirmed = evaluateGateSearch(
        _gateCode,
        rawGateSearch,
        widget.scrName,
      );

      final List<Map<String, dynamic>> stops = _getFilteredStops();
      final StopProgress progress = computeStopProgress(stops);

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: gateConfirmed
            ? _buildConfirmed(stops, progress)
            : _buildPending(stops, progress),
      );
    });
  }

  // ── Pending (locked preview) ────────────────────────────────────────────

  Widget _buildPending(
    List<Map<String, dynamic>> stops,
    StopProgress progress,
  ) {
    final String title = _t(11, 'Rute Hari Ini');
    final String countTemplate = _t(15, '{total} tujuan');
    final String hint = _t(16, 'Konfirmasi muatan dulu buat mulai');

    final String countText = countTemplate.replaceAll(
      '{total}',
      '${progress.total}',
    );

    final String nameField = (widget.component['nameField'] ?? 'kn').toString();
    final String addressField = (widget.component['addressField'] ?? 'al')
        .toString();

    // Reject-feature gate: show Tolak buttons + footnote ONLY when
    // rejectRoute is non-empty. When absent (existing/unmigrated P4 JSON),
    // the locked render stays exactly as before (muted list, no reject UI).
    final String rejectRoute = (widget.component['rejectRoute'] ?? '')
        .toString()
        .trim();
    final bool hasReject = rejectRoute.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: lock icon + title + count
          Row(
            children: [
              const Icon(
                Icons.lock_outlined,
                size: 18,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      countText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Amber hint banner
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7), // amber-100
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hint,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFD97706), // amber-600
                height: 1.4,
              ),
            ),
          ),
          // Numbered stop list
          if (stops.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (int i = 0; i < stops.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Number circle
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF3F4F6), // gray-100
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (stops[i][nameField] ?? '').toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF9CA3AF),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            (stops[i][addressField] ?? '').toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFD1D5DB),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Trailing: Selesai chip / Tolak button / nothing
                    if (hasReject) ...[
                      const SizedBox(width: 8),
                      if (stopStatusOf(stops[i]) == 'done')
                        // Green "Selesai" chip (reuses existing badge palette)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7), // green-100
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _t(5, 'Selesai'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16A34A), // green-600
                            ),
                          ),
                        )
                      else
                        // Amber outline "Tolak" button
                        GestureDetector(
                          onTap: () => _onRejectTap(stops[i]),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFD97706), // amber-600
                              ),
                            ),
                            child: Text(
                              _t(18, 'Tolak'),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD97706), // amber-600
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
          ],
          // Footnote (once, after the list) -- only when reject is enabled
          if (hasReject && stops.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _t(
                19,
                'Ada stop nggak searah? Tolak sebelum berangkat, dikembalikan ke Admin.',
              ),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF), // gray-400
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Confirmed (active list + progress) ──────────────────────────────────

  Widget _buildConfirmed(
    List<Map<String, dynamic>> stops,
    StopProgress progress,
  ) {
    final String title = _t(11, 'Rute Hari Ini');
    final String progressTemplate = _t(12, '{closed} dari {total} stop');
    final String nextLabel = _t(13, 'lanjut:');
    final String allDoneLabel = _t(14, 'semua kelar');
    final String ctaLabel = _t(17, 'Buka Tasklist (eksekusi)');

    // R2-1: real task-doc field codes (confirmed on-device): name = `kn`,
    // address = `al`. Component-overridable for forward compat.
    final String nameField = (widget.component['nameField'] ?? 'kn').toString();
    final String addressField = (widget.component['addressField'] ?? 'al')
        .toString();
    // R2-2: per-stop kirim/ambil action is driven by `tty`
    // (values "delivery"/"pickup"), NOT `act`. Overridable for forward compat.
    final String actionField = (widget.component['actionField'] ?? 'tty')
        .toString();

    final String progressText = progressTemplate
        .replaceAll('{closed}', '${progress.closed}')
        .replaceAll('{total}', '${progress.total}');

    final double pct = progress.total > 0
        ? progress.closed / progress.total
        : 0;

    // W1: subtitle is ONLY the trailing "lanjut: {next}" / "semua kelar"
    // segment — it must NOT fall back to progressText (that would render
    // "X dari Y · X dari Y"). Empty when there is no next stop and not all
    // closed (e.g. empty list); the header then shows progressText alone.
    final String nextStopName = progress.nextStop != null
        ? (progress.nextStop![nameField] ?? '').toString()
        : '';
    final String subtitle = progress.allClosed
        ? allDoneLabel
        : nextStopName.isNotEmpty
        ? '$nextLabel $nextStopName'
        : '';
    // Header line: progress text plus the subtitle segment only when present.
    final String headerLine =
        progressText + (subtitle.isNotEmpty ? ' · $subtitle' : '');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: icon + title + subtitle + percentage
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 20,
                color: Color(0xFF4338CA),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      headerLine,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(pct * 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4338CA), // indigo
                ),
              ),
            ],
          ),
          // Thin progress bar
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4338CA),
              ),
            ),
          ),
          // Stop rows
          if (stops.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (int i = 0; i < stops.length; i++)
              _buildStopRow(
                stops[i],
                i,
                nameField,
                addressField,
                actionField,
                isActive: identical(stops[i], progress.nextStop),
              ),
          ],
          // Footer CTA
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _onCtaTap,
              child: Text(
                '$ctaLabel →', // →
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4338CA), // indigo
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopRow(
    Map<String, dynamic> stop,
    int index,
    String nameField,
    String addressField,
    String actionField, {
    bool isActive = false,
  }) {
    final String status = stopStatusOf(stop);
    final bool isClosed = isStopClosed(status);
    final String name = (stop[nameField] ?? '').toString();
    final String address = (stop[addressField] ?? '').toString();
    final String action = (stop[actionField] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    // Badge text + colors
    final _BadgeStyle badge = _badgeFor(status, action);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFEEF2FF)
            : Colors.transparent, // indigo-50
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Leading: number circle or check icon
          SizedBox(
            width: 28,
            child: isClosed
                ? Icon(
                    status == 'done'
                        ? Icons.check_circle
                        : Icons.cancel_outlined,
                    size: 20,
                    color: status == 'done'
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFD97706),
                  )
                : Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? const Color(0xFF4338CA)
                          : const Color(0xFFF3F4F6),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? Colors.white
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          // Name + address + action hint
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isClosed
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF1F2937),
                    decoration: isClosed
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Trailing badge pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badge.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              badge.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: badge.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _BadgeStyle _badgeFor(String status, String action) {
    switch (status) {
      case 'done':
        return const _BadgeStyle(
          'SELESAI',
          Color(0xFFDCFCE7), // green-100
          Color(0xFF16A34A), // green-600
        );
      case 'failed':
        return const _BadgeStyle(
          'GAGAL',
          Color(0xFFFEF3C7), // amber-100
          Color(0xFFD97706), // amber-600
        );
      case 'active':
        return const _BadgeStyle(
          'LANJUT',
          Color(0xFFEEF2FF), // indigo-50
          Color(0xFF4338CA), // indigo-700
        );
      default:
        // Pending: derive label from the `tty` action field (R2-2).
        // Real values (confirmed on-device): "delivery" -> KIRIM (_t8),
        // "pickup" -> AMBIL (_t9). Any other/absent value defaults to KIRIM.
        final String label = action == 'pickup'
            ? _t(9, 'AMBIL').toUpperCase()
            : action == 'delivery'
            ? _t(8, 'KIRIM').toUpperCase()
            : _t(8, 'KIRIM').toUpperCase(); // default to KIRIM
        return _BadgeStyle(
          label,
          const Color(0xFFF3F4F6), // gray-100
          const Color(0xFF6B7280), // gray-500
        );
    }
  }
}

class _BadgeStyle {
  final String label;
  final Color bg;
  final Color fg;
  const _BadgeStyle(this.label, this.bg, this.fg);
}
