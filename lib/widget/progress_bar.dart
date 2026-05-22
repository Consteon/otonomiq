import 'package:flutter/material.dart';

import '../global.dart';
import 'task_progress_store.dart';

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    required Key key,
    required this.component,
    required this.scrName,
    required this.single,
    required this.lPad,
    required this.rPad,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final bool single;
  final double lPad;
  final double rPad;

  static bool _parseBool(dynamic v, {bool fallback = true}) {
    if (v is bool) return v;
    if (v is String) return v.toUpperCase() == 'TRUE';
    return fallback;
  }

  Color _parseColor(String? hex, Color fallback) {
    if (hex == null) return fallback;
    try {
      var c = hex.replaceAll('#', '').trim();
      if (c.length == 3) {
        c = '${c[0]}${c[0]}${c[1]}${c[1]}${c[2]}${c[2]}';
      }
      if (c.length == 6) return Color(int.parse('FF$c', radix: 16));
    } catch (_) {}
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final texts = diamondTextToList(component['text'] as String? ?? '');
    final margin = marginArray(component['margin'] as String?);
    final positionRaw = component['positionId'];
    final positions = positionRaw is List
        ? positionRaw.map((e) => (e as num).toInt()).toList()
        : <int>[];
    final showPercent = _parseBool(component['showPercent']);
    final showCount = _parseBool(component['showCount']);
    final barHeight = (component['height'] as num?)?.toDouble() ?? 8;
    final borderRadius = (component['borderRadius'] as num?)?.toDouble() ?? 10;
    final bgColor = _parseColor(component['bgColor'] as String?, Colors.white);
    final lineColor =
    _parseColor(component['lineColor'] as String?, const Color(0xFF22C55E));

    final title = texts.isNotEmpty ? texts[0] : '';
    final subtitle = [
      if (texts.length > 1) texts[1],
      if (texts.length > 2) texts[2],
      if (texts.length > 3) texts[3],
    ].join(' ');
    final countSep = texts.length > 4 ? texts[4] : '/';
    final verifiedIcon = texts.length > 5 ? texts[5] : '✓';
    final verifiedLabel = texts.length > 6 ? texts[6] : 'Verified';
    final tasksLabel = texts.length > 7 ? texts[7] : 'tasks';
    final percentSuffix = texts.length > 8 ? texts[8].trim() : '%';

    return ListenableBuilder(
      listenable: TaskProgressStore.instance,
      builder: (context, _) {
        final total = TaskProgressStore.instance.totalFor(scrName, positions);
        final done = TaskProgressStore.instance.doneFor(scrName, positions);
        final progress =
        TaskProgressStore.instance.progressFor(scrName, positions);
        final percent = (progress * 100).round();
        final isVerified = total > 0 && done == total;

        return Container(
          margin: EdgeInsets.only(
            top: margin[0],
            bottom: margin[1],
            left: lPad + margin[2],
            right: rPad + margin[3],
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: const Color(0xffE2E8F0)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  if (isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color:
                            const Color(0xFF22C55E).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '$verifiedIcon $verifiedLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                    ),
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (showCount || showPercent)
                Row(
                  children: [
                    if (showCount)
                      Text(
                        '$done $countSep $total $tasksLabel',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    const Spacer(),
                    if (showPercent)
                      Text(
                        '$percent$percentSuffix',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                        height: barHeight,
                        width: constraints.maxWidth * progress,
                        decoration: BoxDecoration(
                          color: lineColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
