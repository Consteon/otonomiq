import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

import '../api.dart';
import '../global.dart';
import '../model/otq_state.dart';
import '../redux/screen_transaction.dart';

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

  @override
  State<NfcReader> createState() => _NfcReaderState();
}

class _NfcReaderState extends State<NfcReader> {
  bool _isReading = false;

  static const Color _accent = Color(0xFF5B6CFF); // neonIndigo (matches Scanner)

  @override
  void dispose() {
    // Best-effort: close a dangling session if torn down mid-read.
    if (_isReading) {
      unawaited(FlutterNfcKit.finish().catchError((_) {}));
    }
    super.dispose();
  }

  Future<void> _readCard() async {
    if (_isReading) return;
    setState(() => _isReading = true);

    final slots =
        diamondTextToList((widget.component['text'] ?? '').toString());

    try {
      final NFCAvailability availability = await FlutterNfcKit.nfcAvailability;
      if (!mounted) return;
      if (availability != NFCAvailability.available) {
        _fail(nfcSlot(slots, 6, 'NFC tidak tersedia'));
        return;
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
      await FlutterNfcKit.finish(iosAlertMessage: nfcSlot(slots, 4, 'Berhasil'));
      if (!mounted) return;

      if (value.isEmpty) {
        _fail(nfcSlot(slots, 5, 'Gagal membaca kartu'));
        return;
      }
      await _doSuccess(value, slots);
    } catch (e) {
      // Timeout / user cancel / read error.
      try {
        await FlutterNfcKit.finish(
            iosErrorMessage: nfcSlot(slots, 5, 'Gagal membaca kartu'));
      } catch (_) {}
      if (!mounted) return;
      _fail(nfcSlot(slots, 5, 'Gagal membaca kartu'));
    }
  }

  Future<void> _doSuccess(String value, List<String> slots) async {
    // Store bare screen-tx marker for <NFC_RESULT> DSL resolution.
    transactionStore.dispatch(
        UpdateScreenTxAction(ScreenTransaction({'NFC_RESULT': value})));

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
      saveSend(timeStamp, widget.scrName, widget.component, locString,
          defaultVid());
      transactionStore.dispatch(
          UpdateScreenTxAction(ScreenTransaction({'NFC_RESULT': ''})));
    }
    // No write target: leave NFC_RESULT set so a sibling submit on this screen
    // can consume <NFC_RESULT>.

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nfcSlot(slots, 4, 'Berhasil')),
        duration: const Duration(seconds: 2),
      ));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 3),
    ));
    setState(() => _isReading = false);
  }

  @override
  Widget build(BuildContext context) {
    final slots =
        diamondTextToList((widget.component['text'] ?? '').toString());
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
                  : const Icon(Icons.contactless_outlined,
                      size: 44, color: _accent),
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
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
