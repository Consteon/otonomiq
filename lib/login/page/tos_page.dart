import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
// import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';
import '../../redux/screen_transaction.dart';

import '../../widget/ftz_webview.dart';

class TosPage extends StatefulWidget {
  const TosPage({super.key});
  //  AnyPage({Key key, this.store, this.pageName}) : super(key: key);
  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".
  // final String pageName;
  // final List<Widget> component;
  //  final DevToolsStore store;

  @override
  TosPageState createState() => TosPageState();
}

class TosPageState extends State<TosPage> {
  Key key = UniqueKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<ScreenTransaction, ScreenTransaction>(
      converter: (transactionStore) => transactionStore.state,
      builder: (context, list) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Legals'),
          ),
          body: ListView(
            children: <Widget>[
              Card(
                child: ListTile(
                  title: const Text('Peraturan Layanan (ID)'),
                  onTap: () {
                    _openInWebView(
                        'https://vertika.id/vertika_tos_id001.html',
                        'Peraturan Pelayanan');
                  },
                ),
              ),
              const Divider(),
              Card(
                child: ListTile(
                  title: const Text('Peraturan Privasi (ID)'),
                  onTap: () {
                    _openInWebView(
                        'https://vertika.id/vertika_privacy_id001.html',
                        'Peraturan Privasi');
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

//    return new WebviewScaffold(
//      url: "https://vertika.id/vertika_tos_id001.html",
////      url: "https://vertika.id/vertika_privacy_id001.html",
////      url: "https://google.com",
//      appBar: AppBar(
//        title: Text('Legals'),
//        actions: <Widget>[
//          IconButton(
//            icon: Icon(Icons.exit_to_app),
//            onPressed: () {
//              Navigator.popUntil(
//                  context, ModalRoute.withName(Navigator.defaultRouteName));
//            },
//          ),
//        ],
//      ),
//      withZoom: true,
//      withLocalStorage: true,
//      hidden: true,
//      initialChild: Container(
//        child: const Center(
//          child: Text('Loading.....'),
//        ),
//      ),
//
//    );
  }

  Future<void> _openInWebView(String url, String title) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        // builder: (ctx) => WebviewScaffold(
        //   initialChild: Center(
        //     child: CircularProgressIndicator(),
        //   ),
        //   url: _url,
        //   appBar: AppBar(title: Text(_title)),
        // ),
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Builder(
            builder: (BuildContext context) {
              return WebView(
                url: url,
              );
            },
          ),
        ),
      ),
    );
  }
}
