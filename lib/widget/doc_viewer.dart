import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

import '../global.dart';
import '../page/lib/page/otq_pdf_viewer.dart';
import '../sdui_spec.dart';
import '../token_resolver.dart';

// ---------------------------------------------------------------------------
// Decision-rule functions — top-level so tests can reach them.
// _DocViewerState calls these; it never duplicates the rule inline.
// Precedent: pdfFileNameFromUrl in otq_pdf_viewer.dart.
// ---------------------------------------------------------------------------

/// Returns false if [resolved] is empty or still contains an unresolved
/// `{token}` marker — the source URL is not usable for download.
bool docViewerSourceIsUsable(String resolved) {
  return resolved.isNotEmpty && !resolved.contains('{');
}

/// Returns true if the resolved source requires Firebase Storage resolution
/// (getDownloadURL) before download — i.e. it is a storage ref path, not a
/// direct HTTP URL.
bool docViewerNeedsStorageResolve(String sourceType, String resolved) {
  return sourceType == 'path' || !resolved.startsWith('http');
}

/// Returns true if the PDF viewer should scroll horizontally.
/// Mirrors [OtqPdfViewer]'s `swipeHorizontal` rule: anything other than
/// `'vertical'` is horizontal.
bool docViewerSwipeHorizontal(String swipe) {
  return swipe != 'vertical';
}

/// Message shown when Variant B config (`table`) is set but NOT implemented.
/// Exported as a named constant so tests can assert against it without
/// coupling to the wording.
const String docViewerVariantBMessage =
    'Konfigurasi table (Variant B) belum didukung. '
    'Gunakan source dengan link langsung.';

/// Returns the error message when the resolved source is unusable.
/// When [hasTable] is true (Variant B config present but not implemented),
/// returns [docViewerVariantBMessage] so a config author can distinguish
/// "Variant B unsupported" from "PDF failed to load" ([emptyText]).
String docViewerUnusableSourceMessage(bool hasTable, String emptyText) {
  if (hasTable) return docViewerVariantBMessage;
  return emptyText;
}

/// Inline PDF viewer — SDUI component type `DOC_VIEWER`.
///
/// Renders a PDF embedded on the page from a URL or Firebase Storage path.
/// Optional fullscreen icon opens [OtqPdfViewer] via Navigator.push (NOT
/// routeStack — this is a plain Flutter overlay, same as PDF_VIEW's onTap).
///
/// Only Variant A (direct `source` link) is implemented. Variant B
/// (`table`/`search`/`sourceField`/`vidtable` — Firestore fetch) is NOT
/// implemented; those keys are INERT and emit a devPrint warning.
class DocViewer extends StatefulWidget {
  const DocViewer({
    required Key key,
    required this.component,
    required this.scrName,
  }) : super(key: key);

  final dynamic component;
  final String scrName;

  @override
  State<DocViewer> createState() => _DocViewerState();
}

class _DocViewerState extends State<DocViewer> {
  String _pdfPath =
      '--'; // '--' = not yet loaded (same sentinel as OtqPdfViewer)
  String _errorMessage = '';
  bool _isReady = false;

  late final SduiSpec _spec;
  late final String _emptyText;
  late final double _height;
  late final bool _showFullscreen;
  late final String _swipe;
  late final String _title;

  @override
  void initState() {
    super.initState();
    _spec = SduiSpec(widget.component);

    // -- Dead-config guard (D3): Variant B keys are INERT --
    if (_spec.has('table')) {
      devPrint(
        'DOC_VIEWER: `table` (variant B) NOT implemented — using `source`.',
      );
    }

    _emptyText = _spec.str('emptyText', 'Dokumen tidak tersedia');
    _height = _spec.intOr('height', 480).toDouble();
    _showFullscreen = _spec.str('fullscreen', 'true').toLowerCase() == 'true';
    _swipe = _spec.str('swipe', 'vertical').toLowerCase();
    _title = _spec.text(0);

    _resolveAndLoad();
  }

  void _resolveAndLoad() {
    // 1. Resolve {token} markers in source
    final rawSource = _spec.str('source');
    final resolved = TokenResolver.curly(rawSource, widget.scrName);

    // 2. Empty or unresolved → show emptyText
    if (!docViewerSourceIsUsable(resolved)) {
      _errorMessage = docViewerUnusableSourceMessage(
        _spec.has('table'),
        _emptyText,
      );
      return;
    }

    final sourceType = _spec.str('sourceType', 'url').toLowerCase();

    // 3. Storage path vs direct URL
    if (docViewerNeedsStorageResolve(sourceType, resolved)) {
      _resolveStoragePath(resolved);
    } else {
      // 4. Already a full URL
      _downloadPdf(resolved);
    }
  }

  void _resolveStoragePath(String storagePath) {
    // Read #STORAGE_BUCKET — it is a FirebaseStorage instance, not a string.
    // It may be absent (settings not run yet) or the wrong type.
    final dynamic bucket = transactionStore.state.screenTx['#STORAGE_BUCKET'];
    if (bucket == null || bucket is! FirebaseStorage) {
      devPrint(
        'DOC_VIEWER: #STORAGE_BUCKET is null or not FirebaseStorage '
        '(type: ${bucket.runtimeType}). Cannot resolve path: $storagePath',
      );
      // Direct assignment — this branch runs synchronously from initState,
      // so setState is redundant (no build has run yet). Consistent with
      // the empty-source branch in _resolveAndLoad.
      _errorMessage = _emptyText;
      return;
    }

    final FirebaseStorage storage = bucket;
    storage
        .ref(storagePath)
        .getDownloadURL()
        .then((url) {
          if (!mounted) return;
          _downloadPdf(url);
        })
        .catchError((e) {
          if (!mounted) return;
          devPrint('DOC_VIEWER: getDownloadURL failed for "$storagePath": $e');
          setState(() {
            _errorMessage = _emptyText;
          });
        });
  }

  void _downloadPdf(String url) {
    createFileOfPdfUrl(url)
        .then((file) {
          if (!mounted) return;
          setState(() {
            _pdfPath = file.path;
          });
        })
        .catchError((e) {
          if (!mounted) return;
          devPrint('DOC_VIEWER: PDF download failed for "$url": $e');
          setState(() {
            _errorMessage = _emptyText;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final Widget viewer;

    if (_errorMessage.isNotEmpty) {
      // Error / empty state
      viewer = Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
      );
    } else if (_pdfPath == '--') {
      // Loading state
      viewer = const Center(child: CircularProgressIndicator());
    } else {
      // PDF loaded — render inline
      viewer = Stack(
        fit: StackFit.expand,
        children: [
          PDFView(
            filePath: _pdfPath,
            enableSwipe: true,
            swipeHorizontal: docViewerSwipeHorizontal(_swipe),
            autoSpacing: false,
            pageFling: true,
            pageSnap: true,
            fitPolicy: FitPolicy.BOTH,
            onError: (error) {
              if (!mounted) return;
              devPrint('DOC_VIEWER: PDFView onError: $error');
              setState(() {
                _errorMessage = _emptyText;
              });
            },
            onPageError: (page, error) {
              if (!mounted) return;
              devPrint('DOC_VIEWER: PDFView onPageError page $page: $error');
              setState(() {
                _errorMessage = _emptyText;
              });
            },
            onRender: (pages) {
              if (!mounted) return;
              setState(() {
                _isReady = true;
              });
            },
          ),
          // Loading overlay until first render
          if (!_isReady) const Center(child: CircularProgressIndicator()),
          // Fullscreen icon — gated on _pdfPath != '--' so it cannot be
          // tapped mid-download. Uses the already-downloaded local file
          // (remote: false) to avoid a redundant re-download and to dodge
          // expired Firebase Storage signed-URL tokens.
          if (_showFullscreen && _pdfPath != '--')
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OtqPdfViewer(
                          urlPath: _pdfPath,
                          remote: false,
                          swipe: _swipe,
                        ),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6.0),
                    child: Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 4,
            ),
            child: Text(
              _title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        SizedBox(height: _height, child: viewer),
      ],
    );
  }
}
