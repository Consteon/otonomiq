import 'global.dart';

/// Read-side accessor for a server-driven component map.
///
/// Decode (autheniumDecode), split (◆ via diamondTextToList), index-guard and
/// default — in ONE place. New widgets MUST read their config through this
/// class instead of hand-rolling `_t()` guards or raw `component[...]` parsing
/// (that idiom has 47 copies and shipped repeated RangeError / missed-decode
/// crashes). Existing widgets migrate ON-TOUCH only — never in bulk.
///
/// Decode-before-split follows the repo convention (CLAUDE.md): sheet data
/// escapes special glyphs as `_uXXXX_`; a literal `_u25C6_` in a value
/// therefore becomes `◆` and splits. That is the documented ordering contract,
/// not a bug.
class SduiSpec {
  SduiSpec(dynamic component)
    : _component = component is Map ? component : const {} {
    final String rawText = _rawString('text');
    // Short-circuit empty BEFORE diamondTextToList: its guard compares against
    // `empty == "--"` (global.dart:364), so diamondTextToList('') returns ['']
    // (length 1), not []. Guarding here keeps text()/textLength consistent with
    // list() and shields new widgets from that trap.
    _text = rawText.isEmpty
        ? const []
        : diamondTextToList(autheniumDecode(rawText) ?? rawText);
  }

  /// The raw server map. Kept loosely typed — server JSON is dynamic.
  final Map _component;

  late final List<String> _text;

  String _rawString(String key) {
    final dynamic v = _component[key];
    return v == null ? '' : v.toString();
  }

  /// Element [i] of the decoded, ◆-split `component['text']`; [def] when out
  /// of range. Replaces the per-widget `_t()` idiom.
  String text(int i, [String def = '']) => _text.length > i ? _text[i] : def;

  /// Number of ◆-segments in `component['text']` (0 when absent/empty).
  int get textLength => _text.length;

  /// Decoded, trimmed string at [key]; [def] when the key is missing, null,
  /// or blank. Non-string values (numbers from the sheet) are stringified.
  String str(String key, [String def = '']) {
    final String raw = _rawString(key);
    if (raw.trim().isEmpty) return def;
    return (autheniumDecode(raw) ?? raw).trim();
  }

  /// Type-tolerant int at [key]: int stays, num truncates, numeric string
  /// parses; anything else → [def]. Sheet data flips between `5` and `"5"`.
  int intOr(String key, int def) {
    final dynamic v = _component[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(str(key)) ?? def;
  }

  /// Decoded, ◆-split list at [key]. Missing/empty → `const []` — callers can
  /// iterate or index-guard without the raw-`split` `['']` trap.
  List<String> list(String key) {
    final String raw = _rawString(key);
    if (raw.isEmpty) return const [];
    final String decoded = autheniumDecode(raw) ?? raw;
    return diamondTextToList(decoded);
  }

  /// True when [key] holds a non-empty (post-trim) value.
  bool has(String key) => str(key).isNotEmpty;
}
