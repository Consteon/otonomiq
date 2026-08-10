import 'package:flutter/material.dart';

import 'admin_home_support.dart'; // AdminTierColors

// ─── SIGNAL_LIST support — pure parsers ─────────────────────────────────────
//
// Every function in this file is a pure transform: no Firebase, no
// BuildContext, no GetX, no Redux. That is what makes
// test/signal_list_support_test.dart able to exercise all of it without a
// Flutter binding or a Firebase app.
//
// ★ Deliberately NOT exported from lib/widget/all_widget.dart. The barrel
// exports signal_list.dart only. all_widget.dart already re-exports
// admin_home_support.dart, which declares a public `class Signal`; keeping
// this file out of the barrel removes any chance of an `ambiguous_export`
// (the trap list_card_support.dart hit with its public `BadgeEntry`, which
// collides with timeline_ledger_support.dart's `BadgeEntry`).

// ─── `text` ◆-segment accessor ──────────────────────────────────────────────

/// Read one segment of the `text` config field **by its DEV-SPEC number**.
///
/// The dev spec numbers segments 1..8 for humans:
///   1 title · 2 subtitle · 3 metric · 4 meta · 5 actionLabel
///   6 emptyText · 7 searchHint · 8 listTitle
///
/// `diamondTextToList` is 0-based, so spec segment N lives at
/// `segments[N - 1]`. This function does the −1 so that NO caller ever has to,
/// which is the entire reason it exists: an off-by-one here silently shifts
/// every label on the card by one slot and looks like a config bug.
///
/// Length-guarded (`segments.length > i`). NEVER `segments[i] ?? def` — an
/// out-of-range index on a Dart List THROWS RangeError, it does not return
/// null, and `text` segment counts are tenant-authored, so an under-configured
/// tenant would crash while every other tenant works fine.
///
/// Returns `''` for any out-of-range or non-positive segment number. `''` is
/// the correct "feature off" value everywhere in this widget (dev spec §3.1:
/// "Segmen kosong = fitur off"), which is also why there is deliberately no
/// `default` parameter — a non-empty fallback would be a hardcoded label, and
/// this widget has none.
///
/// NOTE `diamondTextToList('')` returns `['']` (length 1), NOT `[]` —
/// global.dart:1793 short-circuits only on the `'--'` sentinel. So an EMPTY
/// `text` config yields `''` from segment 1 by direct hit and `''` from
/// segments 2..8 by fallback. Both are `''`; nothing downstream can or needs
/// to tell them apart.
String signalTextSegment(List<String> segments, int specSegment) {
  final int i = specSegment - 1;
  if (i < 0) return '';
  return segments.length > i ? segments[i] : '';
}

// ─── `statusMap` ────────────────────────────────────────────────────────────

/// One parsed `statusMap` entry: `value◼label◼tone`.
class SignalStatusEntry {
  /// Raw value as it appears in the row's `statusField`.
  final String value;

  /// Human label rendered in the pill and in the group section header.
  final String label;

  /// RAW tone exactly as authored. Intentionally NOT normalised here — run it
  /// through [resolveSignalTone] before use, so the amber-never-red doctrine
  /// guard lives in exactly ONE place.
  final String tone;

  const SignalStatusEntry(this.value, this.label, this.tone);
}

/// Parse `statusMap`: `value◼Label◼tone★value2◼Label2◼tone2`.
///
/// `★` (U+2605) separates entries; `◼` (U+25FC) separates the three fields.
/// **Order is preserved** — the widget renders group sections in this order
/// and appends unlisted data values after them.
///
/// * missing / empty label → label = value (a raw code beats a blank pill)
/// * missing / empty tone  → `'neutral'`
/// * empty value           → entry skipped (a pill with no key never matches)
/// * a 4th field           → ignored, not fatal
///
/// Caller MUST `autheniumDecode` the raw config string BEFORE calling: the
/// server encodes `◼` as `_25FC_` and `⭘` as `_2B58_`.
List<SignalStatusEntry> parseSignalStatusMap(String decoded) {
  if (decoded.trim().isEmpty) return const <SignalStatusEntry>[];
  final List<SignalStatusEntry> out = <SignalStatusEntry>[];
  for (final String part in decoded.split('\u{2605}')) {
    final String trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final List<String> segs = trimmed.split('\u{25FC}');
    final String value = segs.isNotEmpty ? segs[0].trim() : '';
    if (value.isEmpty) continue;
    final String rawLabel = segs.length > 1 ? segs[1].trim() : '';
    final String rawTone = segs.length > 2 ? segs[2].trim() : '';
    out.add(
      SignalStatusEntry(
        value,
        rawLabel.isEmpty ? value : rawLabel,
        rawTone.isEmpty ? 'neutral' : rawTone,
      ),
    );
  }
  return out;
}

/// Look up a status entry by a row's raw `statusField` value.
///
/// Returns null when the value is empty or absent from the map. The widget
/// then HIDES the pill entirely and falls back to the neutral tone — design
/// spec §3.3: a raw unmapped code (`overdue_x`) shown to an operator is worse
/// than no pill at all.
SignalStatusEntry? lookupSignalStatus(
  List<SignalStatusEntry> entries,
  String value,
) {
  final String v = value.trim();
  if (v.isEmpty || entries.isEmpty) return null;
  for (final SignalStatusEntry e in entries) {
    if (e.value == v) return e;
  }
  return null;
}

// ─── tone ───────────────────────────────────────────────────────────────────

/// Normalise an authored `tone` to one of `warn` | `ok` | `accent` | `neutral`.
///
/// ★★ DOCTRINE GUARD ★★ `danger` is FORCED to `warn`.
///
/// Reorder_Signal_Doctrine §5 and dev spec §10: an operational signal is
/// AMBER; red is reserved for engineering failure. Red must be unreachable
/// BY CONSTRUCTION, not merely unauthored — hence an explicit branch here
/// rather than "we just never write danger in a sheet". Unit-tested in
/// test/signal_list_support_test.dart. Do not remove this line.
///
/// Anything unrecognised (including `''`) falls back to `neutral`.
String resolveSignalTone(String rawTone) {
  String tone = rawTone.trim().toLowerCase();
  // DOCTRINE: operational urgency is amber, never red. Never remove.
  if (tone == 'danger') tone = 'warn';
  switch (tone) {
    case 'warn':
    case 'ok':
    case 'accent':
      return tone;
    default:
      return 'neutral';
  }
}

/// The four colours a tone resolves to.
class SignalToneColors {
  /// NON-TEXT marks ONLY: the 4px left accent bar, the dashed timeline
  /// segment, the hollow marker ring. Never used for text — see [pillText].
  final Color accent;

  /// Status pill background.
  final Color pillBg;

  /// Status pill text, the metric line, AND the group section header.
  ///
  /// Design spec §3.4: the JSX mockup renders the metric in the accent amber
  /// (#F59E0B) which is 2.1:1 on white and FAILS WCAG AA. The pill text
  /// (#B45309 for warn) is 5.9:1. The metric is the card's primary read at
  /// 16/w800 — it must pass.
  final Color pillText;

  /// Card background tint.
  final Color cardTint;

  const SignalToneColors({
    required this.accent,
    required this.pillBg,
    required this.pillText,
    required this.cardTint,
  });
}

/// Tone → colour table. **This is the binding mapping** (design spec §1), and
/// it deliberately does NOT follow the token names.
///
/// ★★ THE PALETTE TRAP ★★ `AdminTierColors` token names do not mean what the
/// spec's `tone` names mean. The Admin runtime already enforces
/// amber-for-urgency, so its `danger*` family IS AMBER and its `warn*` family
/// is VIOLET:
///
///     AdminTierColors.dangerBorder  = #F59E0B  AMBER   ← tone `warn` uses THIS
///     AdminTierColors.warnBadgeText = #7C3AED  VIOLET  ← tone `warn` must NOT
///
/// Mapping tone `warn` onto `AdminTierColors.warn*` ships a VIOLET badge.
///
/// `ok` pill TEXT uses [AdminTierColors.okActionGreen] (#15803D, ≈5.0:1), not
/// `okBadgeText` (#16A34A, ≈3.2:1 on #DCFCE7 — below AA for 11px bold). The
/// same reasoning is already documented at admin_home_support.dart:1040.
///
/// Do NOT use `statusColor`/`statusBgColor` from panel_card_support.dart here:
/// those map `danger` to RED (#DC2626 / #FEE2E2), which this widget's doctrine
/// forbids.
SignalToneColors signalToneColors(String rawTone) {
  switch (resolveSignalTone(rawTone)) {
    case 'warn':
      return const SignalToneColors(
        accent: AdminTierColors.dangerBorder, // #F59E0B amber
        pillBg: AdminTierColors.dangerBadgeBg, // #FEF3C7
        pillText: AdminTierColors.dangerBadgeText, // #B45309
        cardTint: AdminTierColors.dangerBg, // #FFF7E6
      );
    case 'ok':
      return const SignalToneColors(
        accent: AdminTierColors.okActionGreen, // #15803D
        pillBg: AdminTierColors.okBadgeBg, // #DCFCE7
        pillText: AdminTierColors.okActionGreen, // #15803D (AA, not #16A34A)
        cardTint: Colors.white,
      );
    case 'accent':
      return const SignalToneColors(
        accent: AdminTierColors.okAction, // #2563EB
        pillBg: AdminTierColors.iconTileBg, // #EAF1FF
        pillText: AdminTierColors.okAction, // #2563EB
        cardTint: Colors.white,
      );
    default:
      return const SignalToneColors(
        accent: AdminTierColors.mutedText, // #9CA3AF
        pillBg: AdminTierColors.normalBadgeBg, // #F1F5F9
        pillText: AdminTierColors.normalBadgeText, // #475569
        cardTint: Colors.white,
      );
  }
}

// ─── `gaps` (mini-timeline) ─────────────────────────────────────────────────

/// Tolerant parse of a row's `gapsField` value into a list of day-gaps.
///
/// ★ The `reorder_cache` collection DOES NOT EXIST YET — verified
/// 2026-08-06 against live Firestore (project otq-01): the tenant has 21
/// subcollections and none is named `reorder_cache`, so the Go Cloud
/// Function has not shipped and its `gaps` shape cannot be read directly.
/// Every plausible output is therefore accepted:
///
/// | input                            | result      |
/// |----------------------------------|-------------|
/// | `[7, 6, 8]` (List of num)        | `[7, 6, 8]` |
/// | `['7', '6', '8']` (List of String) | `[7, 6, 8]` |
/// | `[{d:7},{d:6}]` (List of Map)    | `[7, 6]`    |
/// | `'7◆6◆8'` (◆-joined String)      | `[7, 6, 8]` |
/// | `'7,6,8'` (comma String)         | `[7, 6, 8]` |
/// | `'[7,6,8]'` (JSON-ish String)    | `[7, 6, 8]` |
/// | `'7'` / `7`                      | `[7]`       |
/// | `null` / `''` / `'--'` / garbage | `[]`        |
///
/// Non-numeric elements are DROPPED, never coerced to 0 — a bogus gap dot
/// lies about the customer's rhythm; a missing one is merely less detail.
///
/// Never throws: a malformed cache field must not take the card down.
List<num> parseSignalGaps(dynamic raw) {
  if (raw == null) return const <num>[];
  if (raw is List) {
    final List<num> out = <num>[];
    for (final dynamic e in raw) {
      if (e == null) continue;
      // ★ VERIFIED 2026-08-06 against live Firestore (project otq-01): this
      // backend's ONLY array field, task.it, is an array of MAPS
      // ({ad, ap, pd, …}). Both CF-derived caches (reward_cache,
      // asset_cache) are flat scalars with no arrays at all. So if the
      // reorder_cache Cloud Function follows house style, `gaps` arrives as
      // [{d: 7}, {d: 6}] rather than [7, 6] — and a scalar-only parser would
      // return [] and silently kill the mini-timeline with no error and no
      // log. A map element therefore contributes its FIRST numeric value,
      // whatever the key is named.
      //
      // First-numeric-value, not a configured key name: the real field name
      // is unknowable until the CF ships, and adding a `gapsValueField`
      // config key for an unverified shape would be new config surface
      // guessing at the same unknown. A gap entry has exactly one number
      // worth reading; if a future CF emits maps with several numbers, THAT
      // is the moment to add the key.
      if (e is Map) {
        for (final dynamic v in e.values) {
          final num? mn = num.tryParse(v.toString().trim());
          if (mn != null) {
            out.add(mn);
            break;
          }
        }
        continue;
      }
      final num? n = num.tryParse(e.toString().trim());
      if (n != null) out.add(n);
    }
    return out;
  }
  if (raw is num) return <num>[raw];
  // A top-level Map (as opposed to a Map ELEMENT inside a List) is not a gap
  // series in any shape we can read.
  if (raw is Map) return const <num>[];
  String s = raw.toString().trim();
  // '--' is the global `empty` sentinel (global.dart:364). Matched as a
  // literal so this file stays free of global.dart and remains pure.
  if (s.isEmpty || s == '--') return const <num>[];
  if (s.startsWith('[')) s = s.substring(1);
  if (s.endsWith(']')) s = s.substring(0, s.length - 1);
  final String sep = s.contains('\u{25C6}') ? '\u{25C6}' : ',';
  final List<num> out = <num>[];
  for (final String part in s.split(sep)) {
    final num? n = num.tryParse(
      part.trim().replaceAll('"', '').replaceAll("'", ''),
    );
    if (n != null) out.add(n);
  }
  return out;
}

/// Render a gap / marker number for the mini-timeline: `7`, not `7.0`.
///
/// Whole doubles print as integers; genuine fractions keep one decimal.
String formatSignalGapValue(num g) {
  if (g is int) return g.toString();
  if (g == g.roundToDouble()) return g.toInt().toString();
  return g.toStringAsFixed(1);
}

// ─── `sort` ─────────────────────────────────────────────────────────────────

/// Parsed `sort` config: field name + direction.
class SignalSortSpec {
  final String field;
  final bool desc;
  const SignalSortSpec(this.field, this.desc);

  /// True when there is nothing to sort by (arrival order).
  bool get isEmpty => field.isEmpty;
}

/// Parse `sort`: `field◼asc|desc`.
///
/// Length-guarded split. No `◼` at all → the whole string is the field and
/// direction defaults to ascending. Any direction other than `desc`
/// (case-insensitive) is ascending. Empty input → [SignalSortSpec.isEmpty].
///
/// Caller MUST `autheniumDecode` the raw config string BEFORE calling.
SignalSortSpec parseSignalSort(String decoded) {
  final String s = decoded.trim();
  if (s.isEmpty) return const SignalSortSpec('', false);
  final List<String> segs = s.split('\u{25FC}');
  final String field = segs.isNotEmpty ? segs[0].trim() : '';
  final String dir = segs.length > 1 ? segs[1].trim().toLowerCase() : '';
  return SignalSortSpec(field, dir == 'desc');
}

// ─── aging compute (REV2) ──────────────────────────────────────────────────

/// Compute days since last activity from an epoch-ms value.
///
/// Returns -1 when the value is null, empty, non-numeric, or <= 0, OR when
/// the epoch is in the future (clock skew, ms-vs-seconds confusion). In all
/// these cases the caller skips the card.
///
/// `lo` may arrive as String, int, or double -- CF numeric typing is
/// inconsistent (verified: `reward_cache.qt` is int, `rd` is String `"0"` in
/// the same doc class). Routed through `num.tryParse(v.toString().trim())`;
/// never a raw cast.
///
/// [nowMs] is injectable so tiering is unit-testable without mocking clocks.
int computeSignalDaysSince(dynamic loValue, int nowMs) {
  if (loValue == null) return -1;
  final String s = loValue.toString().trim();
  if (s.isEmpty) return -1;
  final num? lo = num.tryParse(s);
  if (lo == null || lo <= 0) return -1;
  return ((nowMs - lo) / 86400000).floor();
}

/// Convert a raw cadence value + unit to cadence-in-days.
///
/// Returns -1 when the value is null, empty, non-numeric, or <= 0. The caller
/// skips the card (broken cadence = aging cannot be computed).
///
/// [cadenceUnit] `'bulan'` multiplies by 30; anything else (including the
/// default `'hari'`) treats the raw value as already in days.
///
/// Same `num.tryParse(v.toString().trim())` tolerance as
/// [computeSignalDaysSince] for the same CF-typing reason.
num computeSignalCadenceDays(dynamic cadValue, String cadenceUnit) {
  if (cadValue == null) return -1;
  final String s = cadValue.toString().trim();
  if (s.isEmpty) return -1;
  final num? cad = num.tryParse(s);
  if (cad == null || cad <= 0) return -1;
  return cad * (cadenceUnit == 'bulan' ? 30 : 1);
}

/// Compute the aging tier from days-since and cadence-in-days.
///
/// **Caller contract:** [ds] must be >= 0 (pre-filtered by
/// [computeSignalDaysSince] returning -1 for invalid/future epochs).
/// A negative [ds] passed here would produce `'fresh'`, which is technically
/// correct (just ordered) but masks a data bug the caller should have caught.
///
/// ```text
/// ds <= cadDays * attFraction   -> "fresh"
/// ds <= cadDays                 -> "approaching"
/// ds <= cadDays * dormantMult   -> "overdue"
/// ds >  cadDays * dormantMult   -> "dormant"
/// ```
///
/// Spec section 3.3 defaults: [attFraction] = 0.8, [dormantMult] = 3.0.
String computeSignalTier(
  int ds,
  num cadDays,
  double attFraction,
  double dormantMult,
) {
  if (ds <= cadDays * attFraction) return 'fresh';
  if (ds <= cadDays) return 'approaching';
  if (ds <= cadDays * dormantMult) return 'overdue';
  return 'dormant';
}
