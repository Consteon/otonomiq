import 'package:flutter/material.dart';
import '../global.dart' as prefix0;

class TestApp extends StatelessWidget {
  const TestApp({super.key, required this.flag});

  final String flag;
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERROR 801',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(key: UniqueKey(), title: 'ERROR 801', flag: flag),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({required Key key, required this.title, required this.flag})
      : super(key: key);
  final String title;
  final String flag;

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  final int _counter = prefix0.debugCount;

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Column(
        // Column is also layout widget. It takes a list of children and
        // arranges them vertically. By default, it sizes itself to fit its
        // children horizontally, and tries to be as tall as its parent.
        //
        // Invoke "debug painting" (press "p" in the console, choose the
        // "Toggle Debug Paint" action from the Flutter Inspector in Android
        // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
        // to see the wireframe for each widget.
        //
        // Column has various properties to control how it sizes itself and
        // how it positions its children. Here we use mainAxisAlignment to
        // center the children vertically; the main axis here is the vertical
        // axis because Columns are vertical (the cross axis would be
        // horizontal).
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 30,
          ),
          Text(
            'ERROR 801 Gagal start aplikasi. Error detail # 801-$_counter ',
            style: const TextStyle(fontSize: 28),
          ),
          Container(
            height: 30,
          ),
          const Text(
            'Harap tutup aplikasi, hapus data aplikasi di mobile (Clear data), ulangi dari awal.',
            style: TextStyle(fontSize: 18),
          ),
          Container(
            height: 30,
          ),
          Text(
            'Terjadi kesalahan pada saat membaca data. ${widget.flag}',
            style: const TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }
}
