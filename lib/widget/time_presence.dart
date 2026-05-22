import 'dart:async';

import 'package:flutter/material.dart';

import '../global.dart';

// text index mapping (◆-separated from server):
// [0] header label
// [1] check-in column label
// [2] live column label
// [3] last action column label
// [4] no-data fallback display (e.g. "-" or "-:-")
// [5] check-in time: "HH:mm" or "[CHECKIN]" placeholder
// [6] last action time: "HH:mm" or "[LASTACTION]" placeholder
// [7] checkout time: "HH:mm" or "[CHECKOUT]" placeholder / empty = no checkout

class TimePresence extends StatefulWidget {
  const TimePresence({
    required Key key,
    required this.component,
    required this.scrName,
    required this.single,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final bool single;

  @override
  State<TimePresence> createState() => _TimePresenceState();
}

class _TimePresenceState extends State<TimePresence> {
  late List<String> _texts;
  late double _borderRadius;

  @override
  void initState() {
    super.initState();
    _texts = diamondTextToList(widget.component['text'] as String? ?? '');
    _borderRadius =
        (widget.component['borderRadius'] as num?)?.toDouble() ?? 12;
  }

  bool _isPlaceholder(String s) => s.isEmpty || s.startsWith('[');

  DateTime? _parseTime(String raw) {
    if (_isPlaceholder(raw)) return null;
    try {
      final parts = raw.split(':');
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final header = _texts.isNotEmpty ? _texts[0] : 'TIME PRESENCE';
    final checkInLabel = _texts.length > 1 ? _texts[1] : 'CHECK-IN';
    final liveLabel = _texts.length > 2 ? _texts[2] : 'LIVE';
    final lastActionLabel = _texts.length > 3 ? _texts[3] : 'LAST ACTION';
    final noDataLabel = _texts.length > 4 ? _texts[4] : '--:--';

    final rawCheckIn = _texts.length > 5 ? _texts[5] : '';
    final rawLastAction = _texts.length > 6 ? _texts[6] : '';
    final rawCheckOut = _texts.length > 7 ? _texts[7] : '';

    final hasCheckIn = !_isPlaceholder(rawCheckIn);
    final hasCheckOut = !_isPlaceholder(rawCheckOut);

    final checkInDt = hasCheckIn ? _parseTime(rawCheckIn) : null;

    String checkInDisplay;
    String lastActionDisplay;

    if (hasCheckOut) {
      checkInDisplay = noDataLabel;
      lastActionDisplay = noDataLabel;
    } else {
      checkInDisplay = checkInDt != null ? _fmt(checkInDt) : noDataLabel;

      final lastActionDt =
          _isPlaceholder(rawLastAction) ? null : _parseTime(rawLastAction);
      lastActionDisplay =
          lastActionDt != null ? _fmt(lastActionDt) : noDataLabel;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Color(0xffE2E8F0)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_outlined,
                  size: 15, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Text(
                header,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _TimeColumn(
                    label: checkInLabel,
                    value: checkInDisplay,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _LiveCounter(
                    label: liveLabel,
                    checkInDt: (hasCheckIn && !hasCheckOut) ? checkInDt : null,
                    noDataLabel: noDataLabel,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _TimeColumn(
                    label: lastActionLabel,
                    value: lastActionDisplay,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  final String label;
  final String value;

  const _TimeColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveCounter extends StatefulWidget {
  final String label;
  final DateTime? checkInDt;
  final String noDataLabel;

  const _LiveCounter({
    required this.label,
    required this.checkInDt,
    required this.noDataLabel,
  });

  @override
  State<_LiveCounter> createState() => _LiveCounterState();
}

class _LiveCounterState extends State<_LiveCounter> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    if (widget.checkInDt != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _display {
    final dt = widget.checkInDt;
    if (dt == null) return widget.noDataLabel;
    final d = _now.difference(dt);
    final clamped = d.isNegative ? Duration.zero : d;
    final h = clamped.inHours.toString().padLeft(2, '0');
    final m = (clamped.inMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            _display,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnDivider extends StatelessWidget {
  const _ColumnDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 8);
  }
}
