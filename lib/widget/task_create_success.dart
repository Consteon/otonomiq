import 'package:flutter/material.dart';

import '../global.dart'; // diamondTextToList, routeStack, gotoRoute, routeExist
import 'admin_create_task_support.dart';
import 'admin_home_support.dart'; // AdminTierColors
import 'driver_home_support.dart'; // stripRouteWrapper

/// TASK_CREATE_SUCCESS -- P5 success confirmation screen for the Admin
/// create-task wizard.
///
/// Reads [AdminCreateTaskSupport.getLastCreated] via the shared [wizardKey]
/// and renders a static confirmation page (eyebrow + success banner +
/// summary card + info hint + two navigation buttons).
///
/// Pure display: no Firestore subscription, no saveSend, no write path.
/// No Obx -- data is read once from lastCreated (set by task_create_submit
/// before clearDraft, persists in-memory).
///
/// Text slot map (diamond-separated `component['text']`):
///   [0] "TASK CREATED"           -- eyebrow label
///   [1] "Task Berhasil Dibuat"   -- success banner title
///   [2] "Customer"               -- summary card customer label
///   [3] "Kendaraan"              -- summary card vehicle label
///   [4] "Drop"                   -- drop pill label
///   [5] "Pickup"                 -- pickup pill label
///   [6] "+ Buat Task Lagi"       -- primary button text
///   [7] "Kembali ke Admin Feed"  -- secondary button text
///   [8] (info hint text)         -- default below
///
/// Component config fields:
///   wizardKey       -- wizard key (default 'admin_create_task')
///   createAgainRoute -- route for primary button
///   backRoute        -- route for secondary button
class TaskCreateSuccess extends StatefulWidget {
  const TaskCreateSuccess({
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
  State<TaskCreateSuccess> createState() => _TaskCreateSuccessState();
}

class _TaskCreateSuccessState extends State<TaskCreateSuccess> {
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// Length-guarded text slot accessor.
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  String get _wizardKey =>
      (widget.component['wizardKey'] ?? 'admin_create_task').toString().trim();

  // ── Colors (from mockup) ─────────────────────────────────────────────

  static const Color _text = Color(0xFF0F172A);
  static const Color _textMid = Color(0xFF475569);
  static const Color _textDim = Color(0xFF94A3B8);
  static const Color _border = Color(0xFFE8EAED);

  static const Color _emerald50 = Color(0xFFECFDF5);
  static const Color _emerald100 = Color(0xFFD1FAE5);
  static const Color _emerald500 = Color(0xFF10B981);
  static const Color _emerald700 = Color(0xFF047857);

  static const Color _dropBg = Color(0xFFEEF2FF);
  static const Color _dropFg = Color(0xFF4F46E5);
  static const Color _violet50 = Color(0xFFF5F3FF);
  static const Color _violet700 = Color(0xFF6D28D9);

  static const Color _infoBlueBg = Color(0xFFEFF6FF);
  static const Color _infoBlue = Color(0xFF3B82F6);

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? data = AdminCreateTaskSupport.getLastCreated(
      _wizardKey,
    );

    // Empty-state: P5 is only reached via successful create (which sets
    // lastCreated). Direct nav / no prior create -> invisible (defensive).
    if (data == null) return const SizedBox.shrink();

    final String tnm = (data['tnm'] ?? '').toString();
    final String kn = (data['kn'] ?? '').toString();
    final String vn = (data['vn'] ?? '').toString();
    final int totalDrop = data['totalDrop'] is int
        ? data['totalDrop'] as int
        : 0;
    final int totalPickup = data['totalPickup'] is int
        ? data['totalPickup'] as int
        : 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEyebrow(tnm),
          const SizedBox(height: 20),
          _buildSuccessBanner(tnm, kn, vn),
          const SizedBox(height: 16),
          _buildSummaryCard(kn, vn, totalDrop, totalPickup),
          const SizedBox(height: 16),
          _buildInfoHint(),
          const SizedBox(height: 24),
          _buildPrimaryButton(),
          const SizedBox(height: 8),
          _buildSecondaryButton(),
        ],
      ),
    );
  }

  // ── Eyebrow header ───────────────────────────────────────────────────

  Widget _buildEyebrow(String tnm) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _t(0, 'TASK CREATED').toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: _textMid,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tnm,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ],
      ),
    );
  }

  // ── Success banner ───────────────────────────────────────────────────

  Widget _buildSuccessBanner(String tnm, String kn, String vn) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _emerald50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _emerald100),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Check circle (Icons.check, NOT emoji -- vector glyph)
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _emerald500,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check, size: 32, color: Colors.white),
          ),
          const SizedBox(height: 14),
          // Title
          Text(
            _t(1, 'Task Berhasil Dibuat'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _emerald700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Subtitle: "{tnm} untuk {kn} sudah ke-assign ke {vn}."
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: tnm,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _text,
                  ),
                ),
                TextSpan(text: ' untuk $kn sudah ke-assign ke '),
                TextSpan(
                  text: vn,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _text,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            style: const TextStyle(fontSize: 13, color: _textMid),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Summary card ─────────────────────────────────────────────────────

  Widget _buildSummaryCard(
    String kn,
    String vn,
    int totalDrop,
    int totalPickup,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Customer (left) + Vehicle (right)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(2, 'Customer').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: _textDim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kn,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _text,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(3, 'Kendaraan').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: _textDim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vn,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // Drop + Pickup pills
          Row(
            children: [
              _buildPill(
                label: _t(4, 'Drop'),
                value: totalDrop,
                arrow: '\u{2193}', // down arrow
                arrowColor: _dropFg,
                bgColor: _dropBg,
              ),
              const SizedBox(width: 10),
              _buildPill(
                label: _t(5, 'Pickup'),
                value: totalPickup,
                arrow: '\u{2191}', // up arrow
                arrowColor: _violet700,
                bgColor: _violet50,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A single Drop or Pickup pill in the summary card.
  Widget _buildPill({
    required String label,
    required int value,
    required String arrow,
    required Color arrowColor,
    required Color bgColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  arrow,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: arrowColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: _textMid,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Info hint ────────────────────────────────────────────────────────

  /// Blue accent-bar callout. Follows the notice_bar left-accent pattern
  /// (ClipRRect + Row + IntrinsicHeight).
  Widget _buildInfoHint() {
    return Container(
      decoration: BoxDecoration(
        color: _infoBlueBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 3, minWidth: 3),
                color: _infoBlue,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 12, 14, 12),
                  child: Text(
                    _t(
                      8,
                      'Task sudah ke-anchor ke kendaraan dan nunggu '
                      'loading di gudang. Siapa yang ngantar '
                      'ditentukan saat loading.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _text,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Buttons ──────────────────────────────────────────────────────────

  /// Primary action: "+ Buat Task Lagi" -- admin blue, 48h, uppercase.
  Widget _buildPrimaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 48, // >= 44pt touch target
      child: ElevatedButton(
        onPressed: () => _navigateToRoute('createAgainRoute'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminTierColors.okAction, // #2563EB
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          _t(6, '+ Buat Task Lagi').toUpperCase(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// Secondary action: "Kembali ke Admin Feed" -- white + border, 44h.
  Widget _buildSecondaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 44, // >= 44pt touch target
      child: OutlinedButton(
        onPressed: () => _navigateToRoute('backRoute'),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _text,
          elevation: 0,
          side: const BorderSide(color: _border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          _t(7, 'Kembali ke Admin Feed'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _text,
          ),
        ),
      ),
    );
  }

  // ── Navigation ───────────────────────────────────────────────────────

  /// Navigate to a route specified in a component config field.
  /// Mirrors task_create_submit.dart L222-226: routeExist guard +
  /// stripRouteWrapper + routeStack.push BEFORE gotoRoute.
  void _navigateToRoute(String fieldName) {
    final String rawRoute = (widget.component[fieldName] ?? '')
        .toString()
        .trim();
    final String route = stripRouteWrapper(rawRoute);
    if (route.isNotEmpty && routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
  }
}
