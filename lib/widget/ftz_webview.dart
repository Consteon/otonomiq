import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebView extends StatefulWidget {
  final String url; // Replace with the URL you want to display
  final String? htmlString;

  const WebView({super.key, required this.url, this.htmlString});

  @override
  WebViewState createState() => WebViewState();
}

class WebViewState extends State<WebView> {
  late WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    if (widget.htmlString == null || widget.htmlString!.isEmpty) {
      _controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              // Update loading bar.
            },
            onPageStarted: (String url) {},
            onPageFinished: (String url) => _fitWidth(),
            onWebResourceError: (WebResourceError error) {},
            onNavigationRequest: (NavigationRequest request) {
              if (request.url.startsWith('https://www.youtube.com/')) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    } else {
      final String contentBase64 = base64Encode(
        const Utf8Encoder().convert(widget.htmlString!),
      );
      _controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              // Update loading bar.
            },
            onPageStarted: (String url) {},
            onPageFinished: (String url) => _fitWidth(),
            onWebResourceError: (WebResourceError error) {},
            onNavigationRequest: (NavigationRequest request) {
              if (request.url.startsWith('https://www.youtube.com/')) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse('data:text/html;base64,$contentBase64'));
    }
  }

  // Make arbitrary/exported HTML fit the phone width: force a device-width
  // viewport (these Google-Docs exports declare none) and neutralise their huge
  // body padding/max-width (e.g. `body{max-width:468pt;padding:72pt}`) that
  // otherwise squeezes text into a narrow column with big side gaps.
  void _fitWidth() {
    _controller.runJavaScript(
      "var h=document.head||document.documentElement;"
      "var m=document.querySelector('meta[name=viewport]');"
      "if(!m){m=document.createElement('meta');m.name='viewport';h.appendChild(m);}"
      "m.setAttribute('content','width=device-width, initial-scale=1');"
      "var s=document.createElement('style');"
      "s.innerHTML='html,body{max-width:100%!important;margin:0!important;"
      "padding:16px!important;box-sizing:border-box!important;"
      "overflow-x:hidden!important;}';"
      "h.appendChild(s);",
    );
  }

  @override
  Widget build(BuildContext context) {
    // Callers (openInWebView / tos_page) already provide the Scaffold + AppBar,
    // so this just fills the body — no inner AppBar, no fixed height (was 400,
    // which cut the page off).
    return WebViewWidget(controller: _controller);
  }
}
