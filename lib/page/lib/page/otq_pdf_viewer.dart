import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import '../../../global.dart';

/// Local filename for the cached copy of [urlPath].
///
/// Uri.pathSegments decodes %2F, so a Firebase object path arrives as one
/// segment ('c/autsorz/Otonomiq.pdf') — take the tail. The old
/// lastIndexOf('.pdf') + substring() threw RangeError on any URL without a
/// literal '.pdf' (endPosition 3 < startPosition). Top-level so the guard is
/// reachable from a test instead of buried in State.
String pdfFileNameFromUrl(String urlPath) {
  final segments = Uri.tryParse(urlPath)?.pathSegments ?? const <String>[];
  final tail = segments.isEmpty ? '' : segments.last.split('/').last;
  return tail.isEmpty ? 'document.pdf' : tail;
}

/// Download a remote PDF to the platform cache directory and return the local
/// [File]. Top-level so both [OtqPdfViewer] (fullscreen page) and [DocViewer]
/// (inline SDUI widget) share one implementation.
///
/// Throws on network failure — callers MUST `.catchError` with a `mounted`
/// guard (an uncaught async error from this path was a prior Crashlytics fatal).
Future<File> createFileOfPdfUrl(String urlPath) async {
  final filename = pdfFileNameFromUrl(urlPath);
  var request = await HttpClient().getUrl(Uri.parse(urlPath));
  var response = await request.close();
  // A 403 (expired Firebase Storage token) or 404 (wrong path) returns a small
  // XML/HTML error body — writing it to disk and "sharing" it succeeds silently
  // otherwise. Throw so callers' .catchError surfaces it as a failure. Both
  // existing callers (OtqPdfViewer.initState, DocViewer._downloadPdf) and the
  // new DocDownload already handle a throw.
  if (response.statusCode != 200) {
    throw HttpException(
      'HTTP ${response.statusCode} for $urlPath',
      uri: Uri.tryParse(urlPath),
    );
  }
  var bytes = await consolidateHttpClientResponseBytes(response);
  Directory? dir;
  if (andrew) {
    dir = await getExternalStorageDirectory();
  } else {
    dir = await getApplicationDocumentsDirectory();
  }
  File file = File("${dir!.path}/$filename");
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

class OtqPdfViewer extends StatefulWidget {
  final String urlPath;
  final bool remote;
  final String swipe;
  final bool linkNavigation;
  final String? password;

  const OtqPdfViewer({
    super.key,
    required this.urlPath,
    this.remote = true,
    this.swipe = 'vertical',
    this.linkNavigation = false,
    this.password,
  });

  @override
  _OtqPdfViewerState createState() => _OtqPdfViewerState();
} // end of class PDFScreen

class _OtqPdfViewerState extends State<OtqPdfViewer>
    with WidgetsBindingObserver {
  final Completer<PDFViewController> _controller =
      Completer<PDFViewController>();
  int? pages = 0;
  int? currentPage = 0;
  bool isReady = false;
  String pdfPath = '--';
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.remote) {
      createFileOfPdfUrl(widget.urlPath)
          .then((f) {
            if (!mounted) return;
            setState(() {
              pdfPath = f.path;
            });
          })
          .catchError((e) {
            // download/write failure must surface in-page, not as an uncaught
            // async error (that path used to reach Crashlytics as a fatal)
            if (!mounted) return;
            setState(() {
              errorMessage = e.toString();
            });
          });
    } else {
      pdfPath = widget.urlPath;
    }
  } // end of initState()

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title: Text(pdfPath.split(Platform.pathSeparator).last),
        // actions: <Widget>[
        //   IconButton(
        //     icon: Icon(Icons.share),
        //     onPressed: () {},
        //   ),
        // ],
      ),
      body: Stack(
        children: <Widget>[
          pdfPath == '--'
              ? const Center(child: CircularProgressIndicator())
              : PDFView(
                  filePath: pdfPath,
                  enableSwipe: true,
                  swipeHorizontal:
                      widget.swipe.trim().toLowerCase() != 'vertical',
                  autoSpacing: false,
                  pageFling: true,
                  pageSnap: true,
                  // sheet template ships `"password":""` for every PDF_VIEW;
                  // send null for that so PDFKit/Pdfium treats the doc as
                  // unencrypted instead of failing an empty-password unlock
                  password: (widget.password ?? '').isEmpty
                      ? null
                      : widget.password,
                  defaultPage: currentPage!,
                  fitPolicy: FitPolicy.BOTH,
                  preventLinkNavigation: !widget.linkNavigation,
                  onRender: (pages) {
                    setState(() {
                      pages = pages;
                      isReady = true;
                    });
                  },
                  onError: (error) {
                    setState(() {
                      errorMessage = error.toString();
                    });
                    // devPrint(error.toString());
                  },
                  onPageError: (page, error) {
                    setState(() {
                      errorMessage = '$page: ${error.toString()}';
                    });
                    // devPrint('$page: ${error.toString()}');
                  },
                  onViewCreated: (PDFViewController pdfViewController) {
                    _controller.complete(pdfViewController);
                  },
                  onLinkHandler: (String? uri) {
                    // devPrint('goto uri: $uri');
                  },
                  onPageChanged: (int? page, int? total) {
                    // devPrint('page change: $page/$total');
                    setState(() {
                      currentPage = page;
                    });
                  },
                ),
          errorMessage.isEmpty
              ? !isReady
                    ? const Center(child: CircularProgressIndicator())
                    : Container()
              : Center(child: Text(errorMessage)),
        ],
      ),
      // floatingActionButton: FutureBuilder<PDFViewController>(
      //   future: _controller.future,
      //   builder: (context, AsyncSnapshot<PDFViewController> snapshot) {
      //     if (snapshot.hasData) {
      //       return FloatingActionButton.extended(
      //         label: Text("Go to ${pages! ~/ 2}"),
      //         onPressed: () async {
      //           await snapshot.data!.setPage(pages! ~/ 2);
      //         },
      //       );
      //     }
      //
      //     return Container();
      //   },
      // ),
    );
  }
} // end of class _PDFScreenState
