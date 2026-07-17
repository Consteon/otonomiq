import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Shared presentational helpers for the in-app inbox screens
// (notification_list.dart + message_list.dart). Presentation only — no data
// or bloc logic lives here.

const notifBg = Color(0xFFF4F6FB); // page background
const notifBorder = Color(0xFFE6EAF2); // hairline dividers / bubble borders
const notifTextMuted = Color(0xFF64748B); // secondary text
const notifTextStrong = Color(0xFF0F172A); // primary text
const notifUnreadTint = Color(0xFFEFF4FF); // unread row highlight

const _avatarPalette = <Color>[
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFF059669),
  Color(0xFFDB2777),
  Color(0xFFEA580C),
  Color(0xFF4F46E5),
  Color(0xFFCA8A04),
];

// Deterministic avatar colour so the same name always gets the same tint.
Color notifAvatarColor(String s) {
  if (s.isEmpty) return _avatarPalette.first;
  int h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _avatarPalette[h % _avatarPalette.length];
}

String notifInitials(String s) {
  final parts = s
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

// The legacy default picture renders as a blank grey circle — treat it (and
// empty/null) as "no picture" and fall back to a coloured initial avatar.
bool _hasRealPic(String? pp) =>
    pp != null && pp.isNotEmpty && !pp.contains('defaultpp');

Widget notifAvatar(String name, String? pp, double radius) {
  if (_hasRealPic(pp)) {
    return CircleAvatar(radius: radius, backgroundImage: NetworkImage(pp!));
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: notifAvatarColor(name),
    child: Text(
      notifInitials(name),
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: radius * 0.8,
      ),
    ),
  );
}

// Relative "chat" time. `ms` = unix milliseconds (caller normalizes units).
String notifRelTime(int? ms) {
  if (ms == null || ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'baru';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}j';
  if (diff.inDays == 1) return 'Kemarin';
  if (diff.inDays < 7) return '${diff.inDays}h';
  return DateFormat('d MMM').format(d);
}

// Small red unread-count pill (replaces the old detached TxtDot).
Widget notifCountPill(String txt) {
  return Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: Colors.redAccent,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(
      child: Text(
        txt,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

// Centered empty state for both inbox screens.
Widget notifEmptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: notifUnreadTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: notifTextMuted),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: notifTextStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: notifTextMuted),
          ),
        ],
      ),
    ),
  );
}
