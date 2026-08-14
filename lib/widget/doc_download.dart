import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../global.dart';
import '../global2.dart';
import '../page/lib/page/otq_pdf_viewer.dart';
import '../sdui_spec.dart';
import '../token_resolver.dart';
import 'biometric_gate.dart';
import 'doc_viewer.dart';

// ---------------------------------------------------------------------------
// Decision-rule functions — top-level so tests can reach them without
// instantiating the widget. The widget CALLS these; it never duplicates
// the rule inline.
// ---------------------------------------------------------------------------

/// The 4 text slots with Indonesian defaults.
/// [0] button label, [1] progress, [2] success toast, [3] failure toast.
///
/// A BLANK-but-present ◆ slot falls back to its default (locked decision D4):
/// `SduiSpec.text` is a LENGTH guard only, so `"Unduh PDF◆◆Tersimpan◆Gagal"`
/// returns `''` for slot 1. Same `trim().isEmpty → default` idiom as
/// `bioGateTexts` (biometric_gate.dart).
({String label, String progress, String success, String failure})
docDownloadTexts(SduiSpec spec) {
  String at(int i, String def) {
    final String v = spec.text(i);
    return v.trim().isEmpty ? def : v;
  }

  return (
    label: at(0, 'Unduh'),
    progress: at(1, 'Mengunduh…'),
    success: at(2, 'Tersimpan'),
    failure: at(3, 'Gagal mengunduh'),
  );
}

/// Choose the effective file name for the shared/saved file.
///
/// [configResolved] is the token-resolved `fileName` config value (may be
/// empty or still contain unresolved `{token}` markers).
/// [urlFallback] is the basename extracted from the download URL via
/// [pdfFileNameFromUrl].
String docDownloadEffectiveName(String configResolved, String urlFallback) {
  if (configResolved.isNotEmpty && !configResolved.contains('{')) {
    return configResolved;
  }
  return urlFallback.isNotEmpty ? urlFallback : 'document.pdf';
}

/// Download button — SDUI component type `DOC_DOWNLOAD`.
///
/// Downloads a file from a URL (or Firebase Storage path) and presents the
/// OS share sheet via [SharePlus]. Both `mode:"save"` and `mode:"share"` route
/// to the same share-sheet path in v1 — see plan doc for rationale (Android
/// scoped-storage constraint, `WRITE_EXTERNAL_STORAGE` capped at SDK 28).
///
/// Parsed-but-inert fields in v1: **`mode`**. Both values produce identical
/// behavior (share sheet). Upgrade path: MediaStore MethodChannel for
/// direct-to-Downloads on Android.
class DocDownload extends StatefulWidget {
  const DocDownload({
    required Key key,
    required this.component,
    required this.scrName,
  }) : super(key: key);

  final dynamic component;
  final String scrName;

  @override
  State<DocDownload> createState() => _DocDownloadState();
}

class _DocDownloadState extends State<DocDownload> {
  late final SduiSpec _spec;
  late final ({String label, String progress, String success, String failure})
  _texts;
  late final String _rawUrl;
  late final String _rawFileName;
  late final String _iconName;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _spec = SduiSpec(widget.component);
    _texts = docDownloadTexts(_spec);
    _rawUrl = _spec.str('url');
    _rawFileName = _spec.str('fileName');
    _iconName = _spec.str('icon');

    // Dead-config guard: mode is parsed but both values use share-sheet in v1.
    final mode = _spec.str('mode', 'save').toLowerCase();
    if (mode != 'save' && mode != 'share') {
      devPrint(
        'DOC_DOWNLOAD: unknown mode "$mode", defaulting to save (share-sheet).',
      );
    }
  }

  // Repo snackbar idiom (matches ftz_bluetooth_printer._showSnackBar).
  // Not GetX — this widget has no other GetX dependency; bioGate owns its own
  // Get.dialog internally.
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _onTap() async {
    if (_loading) return;

    // Biometric gate — reuses the same bioGate as LIST_CARD. Returns true
    // (no prompt) when `biometrik` is absent/not "true".
    if (!await bioGate(widget.component, context)) return;
    if (!mounted) return;

    setState(() {
      _loading = true;
    });

    try {
      // 1. Resolve URL via {token} markers
      final resolved = TokenResolver.curly(_rawUrl, widget.scrName);
      if (!docViewerSourceIsUsable(resolved)) {
        devPrint(
          'DOC_DOWNLOAD: URL not usable after token resolve: "$resolved"',
        );
        if (!mounted) return;
        setState(() {
          _loading = false;
        });
        _showSnackBar(_texts.failure);
        return;
      }

      // 2. Storage path or direct URL (mirrors DOC_VIEWER exactly)
      String downloadUrl = resolved;
      if (docViewerNeedsStorageResolve('url', resolved)) {
        final dynamic bucket =
            transactionStore.state.screenTx['#STORAGE_BUCKET'];
        if (bucket == null || bucket is! FirebaseStorage) {
          devPrint(
            'DOC_DOWNLOAD: #STORAGE_BUCKET is null or not FirebaseStorage '
            '(type: ${bucket.runtimeType}). Cannot resolve path: $resolved',
          );
          if (!mounted) return;
          setState(() {
            _loading = false;
          });
          _showSnackBar(_texts.failure);
          return;
        }
        downloadUrl = await bucket.ref(resolved).getDownloadURL();
      }
      if (!mounted) return;

      // 3. Download to temp file (reuses otq_pdf_viewer helper; it now throws
      // on a non-200 status, caught below).
      final file = await createFileOfPdfUrl(downloadUrl);
      if (!mounted) return;

      // 4. Resolve fileName (config with tokens, fallback to URL basename)
      final resolvedName = docDownloadEffectiveName(
        _rawFileName.isNotEmpty
            ? TokenResolver.curly(_rawFileName, widget.scrName)
            : '',
        pdfFileNameFromUrl(downloadUrl),
      );

      // 5. Share via OS sheet (both platforms, both mode values in v1).
      // sharePositionOrigin is REQUIRED on iPad: the native plugin otherwise
      // falls back to CGRectZero and anchors the popover at the screen's
      // top-left corner. Harmless/ignored on phones and Android.
      final RenderObject? box = context.findRenderObject();
      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          fileNameOverrides: [resolvedName],
          sharePositionOrigin: box is RenderBox
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        ),
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      // W2: do NOT claim success when the user dismissed the sheet. Keep the
      // toast on `unavailable` (the normal Android outcome).
      if (result.status != ShareResultStatus.dismissed) {
        _showSnackBar(_texts.success);
      }
    } catch (e) {
      devPrint('DOC_DOWNLOAD: download/share failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _showSnackBar(_texts.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _loading ? null : _onTap,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  stringToIconData(
                    _iconName.isNotEmpty ? _iconName : 'download',
                  ),
                ),
          label: Text(_loading ? _texts.progress : _texts.label),
        ),
      ),
    );
  }
}
