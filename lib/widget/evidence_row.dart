import 'package:flutter/material.dart';

import '../global.dart';

/// EVIDENCE_ROW -- two side-by-side toggle buttons for P11 DeliveryWorkspace.
///
/// Left button: note (📝 Tambah Catatan / Catatan ditambah).
/// Right button: photo (📷 Ambil Foto / Foto · 1).
///
/// LOCAL toggle state only. No persistence this round.
///
/// DEFERRED: when writes land, the note/photo will use:
///   - notePosition: 7 (from component['notePosition'])
///   - photoPosition: 8 (from component['photoPosition'])
///   to write into txfController[scrName][7] and [8].
///
/// Read-only for Firestore: no txfController, no saveSend, no history.
class EvidenceRow extends StatefulWidget {
  const EvidenceRow({
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
  State<EvidenceRow> createState() => _EvidenceRowState();
}

class _EvidenceRowState extends State<EvidenceRow> {
  // ── Driver palette tokens ───────────────────────────────────────────────
  static const Color _accent = Color(0xFF4338CA); // indigo-700 (active fg)
  static const Color _accentBg = Color(0xFFEEF2FF); // indigo-50 (active bg)
  static const Color _hair = Color(0xFFE5E7EB); // gray-200 (inactive border)
  static const Color _inactiveFg = Color(0xFF6B7280); // gray-500 (inactive fg)

  List<String> _textArray = [];
  bool _noteActive = false;
  bool _photoActive = false;

  @override
  void initState() {
    super.initState();
    _parseText();
  }

  void _parseText() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  /// text slot accessors (6 slots):
  ///  [0] noteIcon      "📝"
  ///  [1] noteInactive  "Tambah Catatan"
  ///  [2] noteActive    "Catatan ditambah"
  ///  [3] photoIcon     "📷"
  ///  [4] photoInactive "Ambil Foto"
  ///  [5] photoActive   "Foto · 1"
  String _t(int i, [String def = '']) =>
      _textArray.length > i ? _textArray[i] : def;

  // DEFERRED: positions for future write integration.
  // final int notePosition = int.tryParse(
  //     (widget.component['notePosition'] ?? '').toString()) ?? -1;
  // final int photoPosition = int.tryParse(
  //     (widget.component['photoPosition'] ?? '').toString()) ?? -1;

  @override
  Widget build(BuildContext context) {
    final String noteIcon = _t(0, '\u{1F4DD}');
    final String noteLabel = _noteActive
        ? _t(2, 'Catatan ditambah')
        : _t(1, 'Tambah Catatan');
    final String photoIcon = _t(3, '\u{1F4F7}');
    final String photoLabel = _photoActive
        ? _t(5, 'Foto \u{00B7} 1')
        : _t(4, 'Ambil Foto');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.lPad,
        widget.tPad,
        widget.rPad,
        widget.bPad,
      ),
      child: Row(
        children: [
          // Note button
          Expanded(
            child: _buildToggleButton(
              icon: noteIcon,
              label: noteLabel,
              active: _noteActive,
              onTap: () => setState(() => _noteActive = !_noteActive),
            ),
          ),
          const SizedBox(width: 10),
          // Photo button
          Expanded(
            child: _buildToggleButton(
              icon: photoIcon,
              label: photoLabel,
              active: _photoActive,
              onTap: () => setState(() => _photoActive = !_photoActive),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final Color bg = active ? _accentBg : Colors.white;
    final Color borderColor = active ? _accent : _hair;
    final Color textColor = active ? _accent : _inactiveFg;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: active ? 1.6 : 1.4),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // active state earns a leading check; inactive shows the emoji glyph
            if (active)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: _accent,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(icon, style: const TextStyle(fontSize: 14)),
              ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
