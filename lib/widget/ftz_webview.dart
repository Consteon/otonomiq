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
            onPageFinished: (String url) {},
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
            onPageFinished: (String url) {},
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web View'),
      ),
      body: SizedBox(
        height: 400,
        child: WebViewWidget(
          controller: _controller, // Adjust as needed
        ),
      ),
      // WebViewWidget(
      //   onWebViewCreated: (controller) => _controller = controller,
      //   initialUrl: widget.url,
      //   javascriptMode: JavascriptMode.unrestricted, // Adjust as needed
      // ),
    );
  }
}
