// lib/dev/ocr_spike_main.dart
//
// DEV-ONLY accuracy harness for the OCR_CAPTURE spike (dev spec 12 step 0).
//
// NOT part of the app. Nothing imports this file, so `flutter build` (which
// targets lib/main.dart) tree-shakes it out of every release artifact. Run with:
//
//     flutter run -t lib/dev/ocr_spike_main.dart
//
// It exists because ML Kit CANNOT run under `flutter test` (MethodChannel ->
// MissingPluginException), so the only honest place to measure 7-segment
// accuracy is on a real device.
//
// Procedure: pick ~30 real meter photos (include glare, dirty glass, dark),
// confirm the expected reading per photo, run, and report the percentage.
// >= 80% -> ship `auto` as designed. ~30% -> stop; either tighten the guide box
// or drop `auto` and ship `tap` only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../widget/ocr_capture.dart'; // ocrFlattenElements
import '../widget/ocr_capture_support.dart';

void main() => runApp(const OcrSpikeApp());

class OcrSpikeApp extends StatelessWidget {
  const OcrSpikeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        title: 'OCR spike',
        home: OcrSpikePage(),
      );
}

class _Row {
  _Row(this.path, String expected)
      : controller = TextEditingController(text: expected);
  final String path;
  final TextEditingController controller;
  String recognized = '';
  String pick = '';
  bool done = false;

  bool get labelled => controller.text.trim().isNotEmpty;
  /// NORMALISED on both sides. `pick` is ocrPickAuto's finalData, which has
  /// already been through ocrNormalizeNumber, so a raw comparison scored every
  /// leading-zero register ('012345' vs '12345') as a MISS on a CORRECT read --
  /// exactly the case ocrPickAuto's RAW-digit ranking was built for, and the
  /// percentage dev spec 12 uses as the go/no-go gate (code-review-r1 W-5).
  /// The pre-fill stays RAW so the operator still sees the printed register.
  bool get hit =>
      labelled && pick == ocrNormalizeNumber(controller.text.trim());
}

class OcrSpikePage extends StatefulWidget {
  const OcrSpikePage({super.key});

  @override
  State<OcrSpikePage> createState() => _OcrSpikePageState();
}

class _OcrSpikePageState extends State<OcrSpikePage> {
  final List<_Row> _rows = <_Row>[];
  bool _running = false;
  String _summary = '';

  /// Digits in the file name, used as the pre-filled expected value.
  static String _expectedFromName(String path) {
    final String base = path.split(Platform.pathSeparator).last.split('/').last;
    final int dot = base.lastIndexOf('.');
    return ocrDigits(dot > 0 ? base.substring(0, dot) : base);
  }

  Future<void> _pick() async {
    // No maxWidth/maxHeight/imageQuality: the spike must measure the ORIGINAL
    // photo, not a resized one.
    final List<XFile> picked = await ImagePicker().pickMultiImage();
    setState(() {
      _rows
        ..clear()
        ..addAll(picked
            .map((XFile f) => _Row(f.path, _expectedFromName(f.path))));
      _summary = '';
    });
  }

  Future<void> _run() async {
    if (_rows.isEmpty || _running) return;
    setState(() => _running = true);
    final TextRecognizer rec =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      for (final _Row r in _rows) {
        try {
          final RecognizedText out =
              await rec.processImage(InputImage.fromFilePath(r.path));
          final List<OcrElement> els = ocrFlattenElements(out);
          r.recognized = els.map((OcrElement e) => e.text).join(' | ');
          final OcrFill? f = ocrPickAuto(els, null, 'number');
          r.pick = f?.finalData ?? '';
        } catch (e) {
          r.recognized = 'ERROR: $e';
          r.pick = '';
        }
        r.done = true;
        if (mounted) setState(() {});
      }
    } finally {
      await rec.close();
    }
    final int labelled = _rows.where((_Row r) => r.labelled).length;
    final int hits = _rows.where((_Row r) => r.hit).length;
    final String pct = labelled == 0
        ? 'n/a'
        : (hits * 100 / labelled).toStringAsFixed(1);
    final StringBuffer b = StringBuffer()
      ..writeln('files: ${_rows.length}  labelled: $labelled  exact: $hits')
      ..writeln('EXACT MATCH: $pct%')
      ..writeln('---');
    for (final _Row r in _rows) {
      b.writeln('${r.hit ? "OK " : "MISS"} exp=${r.controller.text.trim()} '
          'got=${r.pick}  <<${r.recognized}>>');
    }
    // debugPrint, not print: flutter_lints has avoid_print.
    debugPrint(b.toString());
    if (mounted) {
      setState(() {
        _summary = b.toString();
        _running = false;
      });
    }
  }

  @override
  void dispose() {
    for (final _Row r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR spike')),
      body: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              TextButton(onPressed: _pick, child: const Text('Pick photos')),
              TextButton(
                onPressed: _running ? null : _run,
                child: Text(_running ? 'Running...' : 'Run OCR'),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('${_rows.length}'),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (BuildContext c, int i) {
                final _Row r = _rows[i];
                return ListTile(
                  dense: true,
                  title: TextField(
                    controller: r.controller,
                    decoration: const InputDecoration(labelText: 'expected'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  subtitle: Text(
                    r.done ? 'got: ${r.pick}\n${r.recognized}' : r.path,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: r.done
                      ? Icon(r.hit ? Icons.check : Icons.close,
                          color: r.hit ? Colors.green : Colors.red)
                      : null,
                );
              },
            ),
          ),
          if (_summary.isNotEmpty)
            SizedBox(
              height: 140,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(_summary,
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
