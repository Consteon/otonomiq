import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../model/otq_state.dart';
import '../redux/screen_transaction.dart';
import 'panel_card_support.dart';

/// Length-guarded slot access for NFC text slots. Mirrors `scannerSlot`
/// (scanner.dart): returns [fallback] when [index] is out of range OR empty.
/// Top-level so tests can exercise the real implementation.
String nfcSlot(List<String> arr, int index, String fallback) {
  return arr.length > index && arr[index].isNotEmpty ? arr[index] : fallback;
}

/// Pure value-selection for a scanned card: the first non-empty NDEF **text**
/// record wins ("the data written on the card"); otherwise fall back to the
/// tag [uid] (its fixed hardware serial, for blank/access cards).
///
/// Kept free of `ndef` types so tests can drive it without a live tag — the
/// widget extracts the candidate text strings, this picks among them.
String pickCardValue(List<String> ndefTexts, String uid) {
  for (final t in ndefTexts) {
    final s = t.trim();
    if (s.isNotEmpty) return s;
  }
  // ponytail: URI/other record types fall back to UID. Add a UriRecord branch
  // (return r.uriString) in the widget's extraction if cards start carrying URLs.
  return uid.trim();
}

/// Parsed config for one collector group from the `groups` component param.
class CollectorGroupConfig {
  final String key;
  final String title;
  final String labelScan;
  final String pillLabel;
  final String rawTarget;
  final int position;

  const CollectorGroupConfig({
    required this.key,
    required this.title,
    required this.labelScan,
    required this.pillLabel,
    required this.rawTarget,
    required this.position,
  });
}

/// Parse the `groups` config string.
///
/// Format: `key◼title◼labelScan◼pillLabel◼target◼position` per group,
/// groups joined by `★`. Groups with an unparseable position are skipped.
/// Length-guards every field index (Convention #3). `groups` is STRUCTURAL
/// config (literal `◼`, like `addToTable`) — NOT a search field, so no
/// autheniumDecode (Convention #2).
List<CollectorGroupConfig> parseGroups(String raw) {
  final List<CollectorGroupConfig> out = [];
  if (raw.trim().isEmpty) return out;
  for (final part in raw.split('★')) {
    final seg = part.split('◼');
    // position (index 5) is required; skip malformed entries
    final int? pos = seg.length > 5 ? int.tryParse(seg[5].trim()) : null;
    if (pos == null) continue;
    out.add(
      CollectorGroupConfig(
        key: seg[0].trim(),
        title: seg.length > 1 ? seg[1].trim() : '',
        labelScan: seg.length > 2 ? seg[2].trim() : 'Scan',
        pillLabel: seg.length > 3 ? seg[3].trim() : '',
        rawTarget: seg.length > 4 ? seg[4].trim() : '',
        position: pos,
      ),
    );
  }
  return out;
}

/// Resolve a target field: literal int, `{token}` from screenTx, or null.
///
/// Uses the same `{key}` regex as `resolveScreenTxTokens`
/// (statistic_card_support.dart:373). Non-numeric / empty after resolution
/// returns null (no target -- counter shows `n` only, no mismatch).
int? resolveTarget(String raw, Map<String, dynamic> screenTx) {
  if (raw.trim().isEmpty) return null;
  final resolved = raw.replaceAllMapped(
    RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'),
    (m) {
      final v = screenTx[m.group(1)];
      if (v == null) return m.group(0)!;
      final s = v.toString().trim();
      return s.isNotEmpty ? s : m.group(0)!;
    },
  );
  return int.tryParse(resolved.trim());
}

/// Check if [id] exists in ANY group's ID list (cross-group dedupe).
bool isDuplicate(String id, List<List<String>> allGroupIds) {
  for (final group in allGroupIds) {
    if (group.contains(id)) return true;
  }
  return false;
}

/// Join collected IDs with `★` for form capture (finalData).
String joinIds(List<String> ids) => ids.join('★');

/// Returns [mismatchText] when target is set and count does not match;
/// null otherwise (no target, or count matches, or empty mismatchText).
String? mismatchNote(int count, int? target, String mismatchText) {
  if (target == null) return null;
  if (count == target) return null;
  if (mismatchText.trim().isEmpty) return null;
  return mismatchText;
}

/// SDUI component `type: 'nfc_reader'` — a card with a **Tap card** action that
/// reads an NFC tag (Android reader-mode / iOS system sheet), resolves a value
/// (NDEF text, else UID), and:
///
/// - Stores it in the bare screen-tx marker `NFC_RESULT` so DSL `<NFC_RESULT>`
///   resolves it (api.dart `_resolveScreenTxMarkers`). Left set when the
///   component has no write target, so a sibling submit on the same screen can
///   consume it.
/// - If `addToTable`/`updateTableRow` is configured, runs the offline-first
///   [saveSend] pipeline (mirrors `Scanner._doSuccess`) then clears the marker.
/// - Navigates to `route` when present (routeStack push-before-goto).
///
/// ## Text slot map — diamond-delimited `component['text']`
///
/// | Index | Meaning                 | Default                        |
/// |-------|-------------------------|--------------------------------|
/// | 0     | Card title              | `'Baca Kartu NFC'`             |
/// | 1     | Card subtitle / iOS msg | `'Dekatkan kartu ke perangkat'`|
/// | 2     | Button label            | `'Tap Kartu'`                  |
/// | 3     | Reading label           | `'Membaca kartu...'`           |
/// | 4     | Success message         | `'Berhasil'`                   |
/// | 5     | Failure message         | `'Gagal membaca kartu'`        |
/// | 6     | NFC-unavailable message | `'NFC tidak tersedia'`         |
class NfcReader extends StatefulWidget {
  const NfcReader({
    super.key,
    required this.component,
    required this.scrName,
    this.lPad = 0,
    this.tPad = 0,
    this.rPad = 0,
    this.bPad = 0,
  });

  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  // ---- Collector variant state ----

  /// Per-widget-instance collector accumulator: composed key
  /// `'$scrName#$firstPosition'` -> list of ID lists (one per group).
  /// Newest IDs are prepended (index 0 = most recent scan). Keyed by
  /// scrName + first-group position so two collector widgets on one screen
  /// don't clobber each other (W1). Cleared on route change via
  /// [clearCollectorState] from clearData.
  static final Map<String, List<List<String>>> collectorState = {};

  /// Compose the per-instance state key from [scrName] and the first group's
  /// form [firstPosition]. Single source of the `#` key format.
  static String collectorKey(String scrName, int firstPosition) =>
      '$scrName#$firstPosition';

  /// Get or lazily initialize the collector state for [key] with [groupCount]
  /// groups. Returns the existing state if it matches the expected group count;
  /// otherwise creates a fresh state.
  static List<List<String>> getOrInitState(String key, int groupCount) {
    final existing = collectorState[key];
    if (existing != null && existing.length == groupCount) return existing;
    final fresh = List.generate(groupCount, (_) => <String>[]);
    collectorState[key] = fresh;
    return fresh;
  }

  /// Clear ALL collector state for a screen (every group-position instance).
  /// Called from clearData (api.dart) on route change.
  static void clearCollectorState(String scrName) {
    collectorState.removeWhere(
      (k, _) => k == scrName || k.startsWith('$scrName#'),
    );
  }

  @override
  State<NfcReader> createState() => _NfcReaderState();
}

class _NfcReaderState extends State<NfcReader> {
  bool _isReading = false;
  int? _activeGroupIndex; // which group's strip is scanning (strip mode)
  String? _freshId; // ID to highlight (newly added or duplicate flash)
  Timer? _freshTimer;

  static const Color _accent = Color(
    0xFF5B6CFF,
  ); // neonIndigo (matches Scanner)

  @override
  void dispose() {
    _freshTimer?.cancel();
    // Best-effort: close a dangling session if torn down mid-read.
    if (_isReading) {
      unawaited(FlutterNfcKit.finish().catchError((_) {}));
    }
    super.dispose();
  }

  /// Shared NFC poll: check availability -> poll tag -> read NDEF -> pick value.
  /// Returns the scanned value on success. Returns null on failure (snackbar
  /// shown, `_isReading` reset via `_fail`). Caller must reset `_isReading` on
  /// success. Extracted from the original `_readCard` so both single-shot and
  /// collector share identical hardware interaction (finish() already called
  /// before returning a value, exactly as before).
  Future<String?> _pollNfc() async {
    if (_isReading) return null;
    setState(() => _isReading = true);

    final slots = diamondTextToList(
      (widget.component['text'] ?? '').toString(),
    );

    try {
      final NFCAvailability availability = await FlutterNfcKit.nfcAvailability;
      if (!mounted) return null;
      if (availability != NFCAvailability.available) {
        _fail(nfcSlot(slots, 6, 'NFC tidak tersedia'));
        return null;
      }

      final int timeoutSec = widget.component['timeoutSeconds'] is num
          ? (widget.component['timeoutSeconds'] as num).toInt()
          : 20;

      // Android: reader-mode poll (waits for a tap, honours timeout).
      // iOS: shows the system NFC sheet with [iosAlertMessage].
      final NFCTag tag = await FlutterNfcKit.poll(
        timeout: Duration(seconds: timeoutSec),
        iosAlertMessage: nfcSlot(slots, 1, 'Dekatkan kartu ke perangkat'),
      );

      // Read NDEF text records when the tag advertises NDEF; a read failure
      // (locked / non-NDEF) degrades cleanly to the UID.
      List<String> texts = const [];
      if (tag.ndefAvailable == true) {
        try {
          final records = await FlutterNfcKit.readNDEFRecords(cached: false);
          texts = records
              .whereType<ndef.TextRecord>()
              .map((r) => r.text ?? '')
              .toList();
        } catch (_) {
          texts = const [];
        }
      }

      final String value = pickCardValue(texts, tag.id);
      await FlutterNfcKit.finish(
        iosAlertMessage: nfcSlot(slots, 4, 'Berhasil'),
      );
      if (!mounted) return null;

      if (value.isEmpty) {
        _fail(nfcSlot(slots, 5, 'Gagal membaca kartu'));
        return null;
      }
      return value;
    } catch (e) {
      // Timeout / user cancel / read error.
      try {
        await FlutterNfcKit.finish(
          iosErrorMessage: nfcSlot(slots, 5, 'Gagal membaca kartu'),
        );
      } catch (_) {}
      if (!mounted) return null;
      _fail(nfcSlot(slots, 5, 'Gagal membaca kartu'));
      return null;
    }
  }

  /// Single-shot NFC read (existing behavior, unchanged semantics).
  Future<void> _readCard() async {
    final value = await _pollNfc();
    if (value == null) return;
    final slots = diamondTextToList(
      (widget.component['text'] ?? '').toString(),
    );
    try {
      await _doSuccess(value, slots);
    } catch (_) {
      _fail(nfcSlot(slots, 5, 'Gagal membaca kartu'));
    }
  }

  Future<void> _doSuccess(String value, List<String> slots) async {
    // Store bare screen-tx marker for <NFC_RESULT> DSL resolution.
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'NFC_RESULT': value})),
    );

    final bool hasWrite =
        (widget.component['addToTable'] ?? '').toString().isNotEmpty ||
        (widget.component['updateTableRow'] ?? '').toString().isNotEmpty;

    if (hasWrite) {
      final int timeStamp = await getRealTime();
      if (!mounted) return;
      final OtqState locSensor = await OtqState().setAllDataAsync();
      if (!mounted) return;
      final String locString = getLocationString('', '', '', locSensor);

      // Offline-first: enqueues, never awaits network. Resolves <NFC_RESULT>
      // synchronously inside saveSend, so clearing right after is safe.
      saveSend(
        timeStamp,
        widget.scrName,
        widget.component,
        locString,
        defaultVid(),
      );
      transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'NFC_RESULT': ''})),
      );
    }
    // No write target: leave NFC_RESULT set so a sibling submit on this screen
    // can consume <NFC_RESULT>.

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nfcSlot(slots, 4, 'Berhasil')),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (!mounted) return;
    final String route = (widget.component['route'] ?? '').toString();
    if (route.isNotEmpty && routeExist(route)) {
      routeStack.push(route); // push BEFORE goto (Convention #1)
      gotoRoute(route);
    } else {
      setState(() => _isReading = false);
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
    setState(() => _isReading = false);
  }

  /// Collector NFC read for a specific group.
  Future<void> _readCardCollector(int groupIndex) async {
    setState(() => _activeGroupIndex = groupIndex);
    final value = await _pollNfc();
    if (value == null) {
      if (mounted) setState(() => _activeGroupIndex = null);
      return;
    }
    _doCollectorSuccess(value, groupIndex);
    if (mounted) setState(() => _activeGroupIndex = null);
  }

  /// Handle a successful collector scan: dedupe, append, write, highlight.
  void _doCollectorSuccess(String value, int groupIndex) {
    final groups = parseGroups((widget.component['groups'] ?? '').toString());
    if (groups.isEmpty) {
      setState(() => _isReading = false);
      return;
    }
    final String key = NfcReader.collectorKey(
      widget.scrName,
      groups[0].position,
    );
    final state = NfcReader.collectorState[key];
    if (state == null || groupIndex >= state.length) {
      setState(() => _isReading = false);
      return;
    }

    // Dedupe check (across ALL groups in this widget)
    final String dedupe = (widget.component['dedupe'] ?? '')
        .toString()
        .toUpperCase();
    if (dedupe == 'TRUE' && isDuplicate(value, state)) {
      // Flash the existing row; do not append
      _showFresh(value);
      setState(() => _isReading = false);
      return;
    }

    // Append (newest first)
    state[groupIndex].insert(0, value);

    // Write finalData to the group's form position (slot-write pattern,
    // selectable_btn.dart:158-159). RBT savesend reads it via ◁position▷.
    if (groupIndex < groups.length) {
      final int pos = groups[groupIndex].position;
      txfControllerCheck(widget.scrName, pos);
      txfController[widget.scrName]![pos]!.finalData = joinIds(
        state[groupIndex],
      );
    }

    // Fresh highlight + reset _isReading
    _showFresh(value);
    setState(() => _isReading = false);

    // Fire-and-forget per-scan write (if addToTable configured)
    final bool hasWrite =
        (widget.component['addToTable'] ?? '').toString().isNotEmpty ||
        (widget.component['updateTableRow'] ?? '').toString().isNotEmpty;
    if (hasWrite) {
      unawaited(_saveSendForCollector(value));
    }
  }

  /// Brief highlight (1 second) for a freshly scanned or duplicate ID.
  void _showFresh(String id) {
    _freshTimer?.cancel();
    setState(() => _freshId = id);
    _freshTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _freshId = null);
    });
  }

  /// Per-scan addToTable write (fire-and-forget). Mirrors `_doSuccess`'s write
  /// path but does NOT navigate and does NOT block scanning.
  Future<void> _saveSendForCollector(String value) async {
    final int timeStamp = await getRealTime();
    if (!mounted) return;
    final OtqState locSensor = await OtqState().setAllDataAsync();
    if (!mounted) return;
    final String locString = getLocationString('', '', '', locSensor);
    // Sync block: set marker, saveSend (resolves <NFC_RESULT> synchronously),
    // clear marker. No await between these three prevents interleaving when
    // two scans overlap in the async preamble above.
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'NFC_RESULT': value})),
    );
    saveSend(
      timeStamp,
      widget.scrName,
      widget.component,
      locString,
      defaultVid(),
    );
    transactionStore.dispatch(
      UpdateScreenTxAction(ScreenTransaction({'NFC_RESULT': ''})),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Variant gate: collector forks here; everything below is single-shot.
    final String variant = (widget.component['variant'] ?? '')
        .toString()
        .toLowerCase();
    if (variant == 'collector') {
      return _buildCollector(context);
    }

    // ---- SINGLE-SHOT (existing code, unchanged) ----
    final slots = diamondTextToList(
      (widget.component['text'] ?? '').toString(),
    );
    final title = nfcSlot(slots, 0, 'Baca Kartu NFC');
    final subtitle = nfcSlot(slots, 1, 'Dekatkan kartu ke perangkat');
    final buttonLabel = nfcSlot(slots, 2, 'Tap Kartu');
    final readingLabel = nfcSlot(slots, 3, 'Membaca kartu...');

    return Container(
      margin: EdgeInsets.only(
        top: (widget.component['beforeSpacing'] ?? 0.0).toDouble(),
        bottom: (widget.component['afterSpacing'] ?? 0.0).toDouble(),
      ),
      padding: EdgeInsets.fromLTRB(
        widget.lPad + (widget.component['leftPadding'] ?? 0.0).toDouble(),
        widget.tPad,
        widget.rPad + (widget.component['rightPadding'] ?? 0.0).toDouble(),
        widget.bPad,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _accent.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withValues(alpha: _isReading ? 0.18 : 0.10),
              ),
              child: _isReading
                  ? const Center(
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: _accent,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.contactless_outlined,
                      size: 44,
                      color: _accent,
                    ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isReading ? readingLabel : subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isReading ? null : _readCard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _accent.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Collector variant UI ----

  static const Color _freshBg = Color(0xFFDCFCE7); // == statusBgColor('ok')

  Widget _buildCollector(BuildContext context) {
    final groups = parseGroups((widget.component['groups'] ?? '').toString());
    if (groups.isEmpty) return const SizedBox.shrink();

    final String key = NfcReader.collectorKey(
      widget.scrName,
      groups[0].position,
    );
    final state = NfcReader.getOrInitState(key, groups.length);
    final String scanMode = (widget.component['scanMode'] ?? 'pad')
        .toString()
        .toLowerCase();
    final String emptyText = (widget.component['emptyText'] ?? '').toString();
    final String mismatchText = (widget.component['mismatchText'] ?? '')
        .toString();
    final Map<String, dynamic> screenTx = transactionStore.state.screenTx;

    return Container(
      margin: EdgeInsets.only(
        top: (widget.component['beforeSpacing'] ?? 0.0).toDouble(),
        bottom: (widget.component['afterSpacing'] ?? 0.0).toDouble(),
      ),
      padding: EdgeInsets.fromLTRB(
        widget.lPad + (widget.component['leftPadding'] ?? 0.0).toDouble(),
        widget.tPad,
        widget.rPad + (widget.component['rightPadding'] ?? 0.0).toDouble(),
        widget.bPad,
      ),
      child: scanMode == 'strip'
          ? _buildStrip(groups, state, screenTx, emptyText, mismatchText)
          : _buildPad(groups, state, screenTx, emptyText, mismatchText),
    );
  }

  Widget _buildPad(
    List<CollectorGroupConfig> groups,
    List<List<String>> state,
    Map<String, dynamic> screenTx,
    String emptyText,
    String mismatchText,
  ) {
    final group = groups[0];
    final ids = state[0];
    final int? target = resolveTarget(group.rawTarget, screenTx);
    final String? mismatch = mismatchNote(ids.length, target, mismatchText);
    final slots = diamondTextToList(
      (widget.component['text'] ?? '').toString(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dashed ScanTarget
        _buildScanTarget(
          label: nfcSlot(slots, 2, 'Scan Tabung'),
          hint: _isReading
              ? nfcSlot(slots, 3, 'Membaca kartu...')
              : nfcSlot(slots, 1, ''),
          onTap: _isReading ? null : () => _readCardCollector(0),
          isReading: _isReading,
        ),
        const SizedBox(height: 14),
        // Results section
        _buildGroupCard(group, ids, target, emptyText),
        // Mismatch note
        if (mismatch != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              mismatch,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF59E0B), // amber-500
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStrip(
    List<CollectorGroupConfig> groups,
    List<List<String>> state,
    Map<String, dynamic> screenTx,
    String emptyText,
    String mismatchText,
  ) {
    final String titleText = (widget.component['title'] ?? '').toString();
    final String badgeText = (widget.component['badge'] ?? '').toString();

    // Check if ANY group has a mismatch
    String? anyMismatch;
    for (int i = 0; i < groups.length; i++) {
      final int? t = resolveTarget(groups[i].rawTarget, screenTx);
      final String? m = mismatchNote(state[i].length, t, mismatchText);
      if (m != null) {
        anyMismatch = m;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Optional title + badge header
        if (titleText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      titleText,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                if (badgeText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // Per-group sections
        for (int i = 0; i < groups.length; i++) ...[
          _buildGroupCard(
            groups[i],
            state[i],
            resolveTarget(groups[i].rawTarget, screenTx),
            emptyText,
          ),
          const SizedBox(height: 8),
          _buildScanStripButton(groups[i], i),
          if (i < groups.length - 1) const SizedBox(height: 14),
        ],
        // Mismatch note
        if (anyMismatch != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              anyMismatch,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF59E0B),
              ),
            ),
          ),
      ],
    );
  }

  /// Dashed ScanTarget card (pad mode).
  Widget _buildScanTarget({
    required String label,
    required String hint,
    required VoidCallback? onTap,
    required bool isReading,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: _accent.withValues(alpha: 0.4),
          radius: 20,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent,
                ),
                child: isReading
                    ? const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.contactless_outlined,
                        size: 26,
                        color: Colors.white,
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              if (hint.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Dashed ScanStrip button (strip mode, per group).
  Widget _buildScanStripButton(CollectorGroupConfig group, int groupIndex) {
    final bool isKosong = group.pillLabel.trim().toLowerCase() == 'kosong';
    final Color tierColor = statusColor(isKosong ? 'warn' : 'ok');
    final bool isActive = _isReading && _activeGroupIndex == groupIndex;

    return GestureDetector(
      onTap: _isReading ? null : () => _readCardCollector(groupIndex),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: tierColor.withValues(alpha: 0.4),
          radius: 12,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: tierColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isActive)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tierColor,
                  ),
                )
              else
                Icon(Icons.contactless_outlined, size: 16, color: tierColor),
              const SizedBox(width: 8),
              Text(
                group.labelScan,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: isKosong ? const Color(0xFF6B7280) : statusColor('ok'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Group results card (shared by pad and strip): header + ID list or empty.
  Widget _buildGroupCard(
    CollectorGroupConfig group,
    List<String> ids,
    int? target,
    String emptyText,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4EAE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: title + counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  group.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              _buildCounter(ids.length, target, group.pillLabel),
            ],
          ),
          const SizedBox(height: 12),
          // ID list or empty placeholder
          if (ids.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  emptyText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            )
          else
            for (final id in ids) _buildIdRow(id, group.pillLabel),
        ],
      ),
    );
  }

  /// Single result row: dot + ID + pill label.
  Widget _buildIdRow(String id, String pillLabel) {
    final bool isFresh = id == _freshId;
    final Color tierColor = statusColor(
      pillLabel.trim().toLowerCase() == 'kosong' ? 'warn' : 'ok',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: isFresh ? _freshBg : Colors.transparent,
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tierColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              id,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          Text(
            pillLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tierColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Counter widget: `n` or `n / target`.
  Widget _buildCounter(int count, int? target, String pillLabel) {
    final Color tierColor = statusColor(
      pillLabel.trim().toLowerCase() == 'kosong' ? 'warn' : 'ok',
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: tierColor,
          ),
        ),
        if (target != null)
          Text(
            ' / $target',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
      ],
    );
  }
}

/// Dashed rounded-rect border for scan target/strip cards.
/// Follows the pattern in otq_get_images_2.dart:491.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  static const double _stroke = 1.5;
  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            _stroke / 2,
            _stroke / 2,
            size.width - _stroke,
            size.height - _stroke,
          ),
          Radius.circular(radius),
        ),
      );

    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + _dash),
          Offset.zero,
        );
        distance += _dash + _gap;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
