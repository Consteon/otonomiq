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

// Returns a usable http(s) image URL, or null to fall back to a coloured
// initial avatar. Rejects null/blank, the legacy grey "defaultpp", and
// malformed values — e.g. a stray leading space (" https://…") that makes
// NetworkImage's Uri.parse throw "Scheme not starting with alphabetic
// character". Trims first so an otherwise-valid but padded URL still renders.
String? _cleanPicUrl(String? pp) {
  if (pp == null) return null;
  final s = pp.trim();
  if (s.isEmpty || s.contains('defaultpp')) return null;
  final uri = Uri.tryParse(s);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  return s;
}

Widget notifAvatar(String name, String? pp, double radius) {
  final fallback = CircleAvatar(
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
  final url = _cleanPicUrl(pp);
  if (url == null) return fallback;
  // Image.network (not CircleAvatar.backgroundImage) so a failed fetch — dead
  // host, dropped handshake, 404 — routes to errorBuilder instead of dumping
  // to the console; falls back to the same coloured initial avatar.
  final d = radius * 2;
  return ClipOval(
    child: Image.network(
      url,
      width: d,
      height: d,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
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

// `tr` (receivedTime) is documented as unix SECONDS, but the broadcast bridge
// actually writes millis — so the old `tr * 1000` overshot into the future and
// every bubble read "baru". Normalize by magnitude so time is right whichever
// unit the writer used. Returns null when unset.
int? notifNormalizeMs(int? t) {
  if (t == null || t <= 0) return null;
  return t < 100000000000 ? t * 1000 : t; // < 1e11 ⇒ seconds, else already ms
}

// Absolute clock "HH:mm" for a message bubble. `ms` = unix millis.
String notifClockTime(int? ms) {
  if (ms == null || ms <= 0) return '';
  return DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
}

// Absolute "9 Jul 2026 • 23:51" for a flat notification-feed row.
String notifDateTime(int? ms) {
  if (ms == null || ms <= 0) return '';
  return DateFormat(
    "d MMM yyyy '•' HH:mm",
  ).format(DateTime.fromMillisecondsSinceEpoch(ms));
}

// Channel avatar with a small unread dot in the top-right corner.
Widget notifAvatarDot(String name, String? pp, double radius, bool unread) {
  final av = notifAvatar(name, pp, radius);
  if (!unread) return av;
  return Stack(
    clipBehavior: Clip.none,
    children: <Widget>[
      av,
      Positioned(
        right: -1,
        top: -1,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
            border: Border.all(color: notifBg, width: 2),
          ),
        ),
      ),
    ],
  );
}

// Date-separator label grouping a thread by calendar day.
String notifDayLabel(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final diff = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  return DateFormat('d MMM yyyy').format(d);
}

// Centered date-separator chip for the message thread.
Widget notifDaySeparator(String label) {
  return Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: notifBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: notifTextMuted,
        ),
      ),
    ),
  );
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
