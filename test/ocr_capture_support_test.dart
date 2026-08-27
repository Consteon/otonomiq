// test/ocr_capture_support_test.dart
//
// Pure-logic tests for OCR_CAPTURE. Each test names the code change that turns
// it RED.
//
// What CANNOT be tested here (states the truth rather than certifying nothing):
//  * ocrFlattenElements -- needs ML Kit types; it is a dumb 3-loop mapper.
//  * TextRecognizer.processImage -- the MethodChannel raises
//    MissingPluginException under `flutter test`. NOTHING in this file proves
//    anything about the native ML Kit side; that is device QA (see the plan's
//    Open Risks).
//  * The camera preview, the guide overlay paint, and the real upload.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:otonomiq/global.dart';
import 'package:otonomiq/global2.dart';
import 'package:otonomiq/model/general_get_controller.dart';
import 'package:otonomiq/sdui_spec.dart';
import 'package:otonomiq/widget/ocr_capture_support.dart';

OcrElement el(String text,
        [double l = 0, double t = 0, double r = 10, double b = 10]) =>
    (text: text, box: <double>[l, t, r, b]);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // globalInit() (global.dart:882) does NOT run under flutter_test, so the
    // `dynamic screenUIComponent` (global.dart:491) is still null here. The
    // PRODUCTION lookup survives that (ocrSiblingComponent's try returns null),
    // but the ocrSiblingComponent group has to WRITE to the map to seed a
    // screen -- and `null['k'] = v` throws NoSuchMethodError. Seed it exactly
    // the way globalInit does.
    screenUIComponent ??= <String, dynamic>{};
  });

  group('ocrNormalizeSeed', () {
    // RED if: the 'null' literal check is removed -> an untouched field submits
    // the four-character string `null`.
    test("the literal string 'null' becomes empty", () {
      expect(ocrNormalizeSeed('null'), '');
    });

    // RED if: the function starts normalising '--' too (api.dart:4827 needs it).
    test("the '--' sentinel is NOT touched", () {
      expect(ocrNormalizeSeed('--'), '--');
      expect(ocrNormalizeSeed(emptyString), emptyString);
    });

    // RED if: the comparison becomes a `contains`.
    test('a real value passes through', () {
      expect(ocrNormalizeSeed('nullish'), 'nullish');
      expect(ocrNormalizeSeed('12345'), '12345');
    });
  });

  group('ocrParsePositions', () {
    // RED if: the split stops using separator[4].
    test('comma separated positions', () {
      expect(ocrParsePositions('11,12,13,14'), <int>[11, 12, 13, 14]);
      expect(ocrParsePositions(' 7 '), <int>[7]);
    });

    // RED if: unparseable entries throw instead of being dropped.
    test('junk entries are dropped, never thrown', () {
      expect(ocrParsePositions('7,,x,9'), <int>[7, 9]);
      expect(ocrParsePositions(''), <int>[]);
    });
  });

  group('ocrParseRatio', () {
    // RED if: the ':' split is dropped.
    test('a:b forms', () {
      expect(ocrParseRatio('4:1'), 4.0);
      expect(ocrParseRatio('1.6:1'), closeTo(1.6, 1e-9));
      expect(ocrParseRatio('4'), 4.0);
    });

    // RED if: an invalid ratio returns a number instead of null (= no guide).
    test('invalid or empty -> null (full frame)', () {
      expect(ocrParseRatio(''), isNull);
      expect(ocrParseRatio('abc'), isNull);
      expect(ocrParseRatio('0:1'), isNull);
      expect(ocrParseRatio('4:0'), isNull);
    });
  });

  group('ocrTypeAt / ocrPatternAt -- spec 3.2 alignment', () {
    // RED if: the length guard becomes `types[i] ?? 'text'` (RangeError).
    test('short list falls back to text', () {
      expect(ocrTypeAt(<String>['number'], 0), 'number');
      expect(ocrTypeAt(<String>['number'], 3), 'text');
      expect(ocrTypeAt(const <String>[], 0), 'text');
    });

    // RED if: a blank ◆ slot stops falling back.
    test('blank slot and unknown word fall back to text', () {
      expect(ocrTypeAt(<String>['', 'date'], 0), 'text');
      expect(ocrTypeAt(<String>['weird'], 0), 'text');
    });

    // RED if: an out-of-range pattern index throws instead of accepting all.
    test('short pattern list -> accept anything', () {
      expect(ocrPatternAt(<String>[r'\d{4}'], 5), isNull);
      expect(ocrPatternAt(const <String>[], 0), isNull);
    });

    // RED if: RegExp compilation stops being wrapped in a try.
    test('a malformed sheet regex does not throw', () {
      expect(ocrPatternAt(<String>['('], 0), isNull);
      expect(ocrPatternAt(<String>[r'[\d.,]+'], 0), isNotNull);
    });
  });

  group('ocrAccepts', () {
    // RED if: the null-regex leg stops meaning "accept anything".
    test('no pattern accepts everything', () {
      expect(ocrAccepts(null, 'anything', 'anything'), isTrue);
    });

    // RED if: the raw leg is removed -- a date pattern only ever matches raw.
    test('matches on the RAW when the normalised form cannot match', () {
      final RegExp rx = RegExp(r'\d{2}[/-]\d{2}[/-]\d{2,4}');
      // normalised date is epoch millis; only the raw can satisfy this pattern.
      expect(ocrAccepts(rx, '14/08/26', '1755129600000'), isTrue);
    });

    // RED if: the normalised leg is removed.
    test('matches on the NORMALISED value', () {
      expect(ocrAccepts(RegExp(r'^\d{4,6}$'), '0 1 2 3 4', '1234'), isTrue);
    });

    // RED if: the function starts accepting everything unconditionally.
    test('a genuine mismatch is rejected', () {
      expect(ocrAccepts(RegExp(r'^\d{4,6}$'), 'PDAM', 'PDAM'), isFalse);
    });
  });

  group('ocrNormalizeNumber -- spec 5 anti-locale', () {
    // RED if: a locale formatter is introduced, or the thousands rule is
    // dropped. This is an explicit acceptance criterion (spec 13).
    test('id_ID thousands separators are removed', () {
      expect(ocrNormalizeNumber('3.663.000'), '3663000');
      expect(ocrNormalizeNumber('3 663 000'), '3663000');
      expect(ocrNormalizeNumber('12,345'), '12345');
    });

    // RED if: the leading-zero strip is dropped (spec 5's own table).
    test('leading zeros are stripped', () {
      expect(ocrNormalizeNumber('01234'), '1234');
      expect(ocrNormalizeNumber('000'), '0');
    });

    // RED if: the 3-digit-tail rule is dropped -> a decimal becomes thousands.
    test('a non-3-digit tail is a DECIMAL separator, emitted as a dot', () {
      expect(ocrNormalizeNumber('1.234,56'), '1234.56');
      expect(ocrNormalizeNumber('0,5'), '0.5');
    });

    // RED if: non-digits stop being stripped.
    test('no digits -> empty', () {
      expect(ocrNormalizeNumber('PDAM'), '');
      expect(ocrNormalizeNumber(''), '');
    });
  });

  group('ocrDigits', () {
    // RED if: the digit-only filter changes. This documents the m3 trap that
    // ocrMinCandidateDigits exists for.
    test('the unit marker "m3" contributes its latin 3', () {
      expect(ocrDigits('m3'), '3');
      expect(ocrDigits('m3 12,345'), '312345');
      expect(ocrDigits('m³ 12345'), '12345'); // superscript is not a digit
    });
  });

  group('ocrParseDateParts', () {
    // RED if: the separator class or the 2-digit-year expansion changes.
    test('common field formats', () {
      expect(ocrParseDateParts('14/08/26'), (y: 2026, m: 8, d: 14));
      expect(ocrParseDateParts('14-08-2026'), (y: 2026, m: 8, d: 14));
      expect(ocrParseDateParts('Tgl 14.08.2026'), (y: 2026, m: 8, d: 14));
    });

    // RED if: the DateTime roll-over probe is removed.
    test('an impossible date is rejected, not rolled over', () {
      expect(ocrParseDateParts('31/02/2026'), isNull);
      expect(ocrParseDateParts('14/13/2026'), isNull);
    });

    // RED if: the function stops returning null for unparseable input.
    test('no date -> null', () {
      expect(ocrParseDateParts('TOTAL 3.663.000'), isNull);
      expect(ocrParseDateParts(''), isNull);
    });
  });

  group('ocrDateToEpochString', () {
    // RED if: the tz adjustment (.add(offset)) is dropped -- on any machine
    // whose local zone is NOT UTC. The dev machines are WIB (+7). On a
    // UTC-configured runner this assertion is vacuous; stated, not hidden.
    //
    // Asserted against DateTime.utc(...) rather than by re-running the
    // production expression, so it is a real check and not a mirror.
    test('equals UTC midnight of that calendar day', () {
      expect(
        int.parse(ocrDateToEpochString(2026, 8, 14)),
        DateTime.utc(2026, 8, 14).millisecondsSinceEpoch,
      );
    });

    // The same check made DETERMINISTIC: an explicit offset means this one is
    // real on a UTC-configured runner too, where the assertion above is
    // vacuous. Closes R14 instead of merely disclosing it.
    test('the tz adjustment is applied regardless of the machine zone', () {
      expect(
        int.parse(ocrDateToEpochString(2026, 8, 14,
            tzOverride: const Duration(hours: 7))),
        DateTime.utc(2026, 8, 14).millisecondsSinceEpoch,
      );
    });
  });

  group('ocrNormalizeValue / ocrDisplayAndFinal', () {
    // RED if: date targets stop writing epoch millis to finalData (they would
    // then submit a human-readable string a number search cannot match).
    test('date target: finalData is epoch millis, display is formatted', () {
      final ({String display, String finalData})? r =
          ocrDisplayAndFinal('14/08/26', 'date', <String, dynamic>{
        'type': 'txf',
        'variant': 'date',
        'format': 'dd/MM/yyyy',
      });
      expect(r, isNotNull);
      expect(int.parse(r!.finalData),
          DateTime.utc(2026, 8, 14).millisecondsSinceEpoch);
      expect(r.display, '14/08/2026');
    });

    // RED if: the target's own `format` stops being read (D4).
    test('a target with no format falls back to d-MMM-yyyy', () {
      final ({String display, String finalData})? r =
          ocrDisplayAndFinal('14/08/26', 'date', <String, dynamic>{'type': 'txf'});
      expect(r!.display, '14-Aug-2026');
    });

    // RED if: a null/short target component throws instead of defaulting.
    test('a missing target component does not throw', () {
      expect(ocrDisplayAndFinal('14/08/26', 'date', null), isNotNull);
    });

    // RED if: number/text stop sharing display == finalData.
    test('number and text write the same string to both', () {
      expect(ocrDisplayAndFinal('3.663.000', 'number', null),
          (display: '3663000', finalData: '3663000'));
      expect(ocrDisplayAndFinal('  PT Sumber  ', 'text', null),
          (display: 'PT Sumber', finalData: 'PT Sumber'));
    });

    // RED if: an unusable raw starts returning a fill instead of null.
    test('unusable raw -> null', () {
      expect(ocrDisplayAndFinal('PDAM', 'number', null), isNull);
      expect(ocrDisplayAndFinal('no date here', 'date', null), isNull);
      expect(ocrDisplayAndFinal('   ', 'text', null), isNull);
    });
  });

  group('ocrPickAuto', () {
    // RED if: ocrMinCandidateDigits is removed -> every water-meter capture
    // yields a junk '3' from the "m3" unit marker.
    test('the m3 unit marker never wins', () {
      final OcrFill? f = ocrPickAuto(
        <OcrElement>[el('m3'), el('012345'), el('PDAM')],
        null,
        'number',
      );
      expect(f!.finalData, '12345');
      // The case above passes at ANY floor -- longest-wins already beats a
      // 1-digit 'm3' when a 6-digit reading is in frame. The floor only bites
      // when the junk is the ONLY candidate, which is the real water-meter
      // failure: a blurred register leaves 'm3' alone in the frame. THIS is the
      // assertion that goes red at ocrMinCandidateDigits = 1.
      expect(
        ocrPickAuto(<OcrElement>[el('m3'), el('PDAM')], null, 'number'),
        isNull,
      );
    });

    // RED if: longest-wins is replaced by first-wins for numbers.
    test('longest digit run wins; ties keep reading order', () {
      final OcrFill? f = ocrPickAuto(
        <OcrElement>[el('4471'), el('012345'), el('998877')],
        null,
        'number',
      );
      expect(f!.finalData, '12345'); // 6 digits raw, leading zero stripped
    });

    // RED if: the pattern stops filtering candidates in auto mode.
    test('ocrPattern filters the candidate set', () {
      final OcrFill? f = ocrPickAuto(
        <OcrElement>[el('18 Aug 2026 09:41'), el('012345')],
        RegExp(r'^\d{4,6}$'),
        'number',
      );
      expect(f!.finalData, '12345');
    });

    // RED if: text mode starts using longest-wins instead of reading order.
    test('text mode takes the FIRST accepted element', () {
      final OcrFill? f = ocrPickAuto(
        <OcrElement>[el('PT'), el('SUMBER JAYA')],
        null,
        'text',
      );
      expect(f!.finalData, 'PT');
    });

    // RED if: an empty / all-rejected set stops returning null (failure must be
    // a null, never an exception -- spec 4d).
    test('nothing usable -> null, never a throw', () {
      expect(ocrPickAuto(const <OcrElement>[], null, 'number'), isNull);
      expect(ocrPickAuto(<OcrElement>[el('PDAM')], null, 'number'), isNull);
    });

    // RED if: the box stops being carried through (D7 thumbnail crop).
    test('the winning element carries its box', () {
      final OcrFill? f =
          ocrPickAuto(<OcrElement>[el('012345', 10, 20, 110, 60)], null, 'number');
      expect(f!.box, <double>[10, 20, 110, 60]);
    });
  });

  group('ocrRawSummary', () {
    // RED if: the truncation cap is removed -> a dense invoice bloats a record.
    test('joined and capped at ocrRawMetaMaxChars', () {
      final List<OcrElement> els =
          List<OcrElement>.generate(100, (int i) => el('abcdefgh'));
      expect(ocrRawSummary(els).length, ocrRawMetaMaxChars);
    });

    // RED if: blank elements stop being filtered.
    test('blank elements are skipped', () {
      expect(ocrRawSummary(<OcrElement>[el('A'), el('  '), el('B')]), 'A B');
    });
  });

  group('ocrGuideRect', () {
    // RED if: the box stops being centred or stops honouring the ratio.
    test('centred box with the requested aspect ratio (pad 0)', () {
      final List<int> r = ocrGuideRect(1000, 1000, 4.0, pad: 0);
      expect(r.length, 4);
      expect(r[2], 860); // 1000 * 0.86
      expect(r[3], 215); // 860 / 4
      expect(r[0], 70); // (1000 - 860) / 2
      expect(r[1], ((1000 - 215) / 2).round()); // the impl rounds, not truncates
    });

    // RED if: the pad is dropped -- the ML Kit crop would clip the register
    // whenever the preview and the capture disagree slightly.
    test('the default pad widens the crop beyond the drawn box', () {
      final List<int> tight = ocrGuideRect(1000, 1000, 4.0, pad: 0);
      final List<int> padded = ocrGuideRect(1000, 1000, 4.0);
      expect(padded[2], greaterThan(tight[2]));
      expect(padded[3], greaterThan(tight[3]));
    });

    // RED if: the clamp to the image bounds is removed.
    test('never escapes the image', () {
      final List<int> r = ocrGuideRect(200, 100, 8.0);
      expect(r[0] + r[2], lessThanOrEqualTo(200));
      expect(r[1] + r[3], lessThanOrEqualTo(100));
    });

    // RED if: degenerate inputs stop returning [] (a crop of 0 px would throw).
    test('degenerate input -> empty', () {
      expect(ocrGuideRect(0, 0, 4.0), isEmpty);
      expect(ocrGuideRect(1000, 1000, 0), isEmpty);
      expect(ocrGuideRect(1000, 1000, double.nan), isEmpty);
      expect(ocrGuideRect(10, 10, 4.0), isEmpty); // < 8 px tall
    });
  });

  group('ocrPrepareSync / ocrFinishSync -- fail open', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ocr_capture_test');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    // RED if: the decodeImage call leaves its try -- img.decodeImage THROWS a
    // RangeError out of PsdDecoder.isValidFile on a short buffer instead of
    // returning null.
    test('a truncated file does not throw', () {
      final File f = File('${tmp.path}/junk.jpg')
        ..writeAsBytesSync(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      final OcrPrepResult r =
          ocrPrepareSync((imagePath: f.path, cropPath: '', guideRatio: 4.0));
      expect(r.width, 0);
      expect(r.cropPath, '');

      final OcrFinishResult fr = ocrFinishSync((
        imagePath: f.path,
        outPath: '${tmp.path}/out.jpg',
        maxSize: 400,
        quality: 80,
        thumbBox: <double>[0, 0, 10, 10],
      ));
      expect(fr.uploadPath, '');
      expect(fr.thumb, isNull);
    });

    // RED if: a missing file stops being caught.
    test('a missing file does not throw', () {
      final OcrPrepResult r = ocrPrepareSync(
          (imagePath: '${tmp.path}/nope.jpg', cropPath: '', guideRatio: null));
      expect(r.width, 0);
    });

    // RED if: the guide crop stops being written, or stops honouring the ratio.
    test('a real image yields dimensions and a crop file', () {
      final img.Image src = img.Image(width: 800, height: 600);
      final File f = File('${tmp.path}/real.jpg')
        ..writeAsBytesSync(img.encodeJpg(src, quality: 90));
      final String cropPath = '${tmp.path}/crop.jpg';
      final OcrPrepResult r = ocrPrepareSync(
          (imagePath: f.path, cropPath: cropPath, guideRatio: 4.0));
      expect(r.width, 800);
      expect(r.height, 600);
      expect(r.cropPath, cropPath);
      expect(File(cropPath).existsSync(), isTrue);
      final img.Image? crop = img.decodeImage(File(cropPath).readAsBytesSync());
      expect(crop!.width, greaterThan(crop.height));
    });

    // RED if: guideRatio null stops meaning "no crop" (tap mode must read the
    // FULL frame -- the agent has to see the whole document).
    test('no guide ratio -> no crop file', () {
      final img.Image src = img.Image(width: 400, height: 300);
      final File f = File('${tmp.path}/real2.jpg')
        ..writeAsBytesSync(img.encodeJpg(src, quality: 90));
      final OcrPrepResult r = ocrPrepareSync((
        imagePath: f.path,
        cropPath: '${tmp.path}/never.jpg',
        guideRatio: null,
      ));
      expect(r.cropPath, '');
      expect(File('${tmp.path}/never.jpg').existsSync(), isFalse);
    });

    // RED if: the shrink stops being down-scale-only, or stops writing.
    test('the upload copy is down-scaled to maxSize', () {
      final img.Image src = img.Image(width: 1280, height: 720);
      final File f = File('${tmp.path}/big.jpg')
        ..writeAsBytesSync(img.encodeJpg(src, quality: 90));
      final OcrFinishResult r = ocrFinishSync((
        imagePath: f.path,
        outPath: '${tmp.path}/small.jpg',
        maxSize: 400,
        quality: 80,
        thumbBox: <double>[100, 100, 300, 200],
      ));
      expect(r.uploadPath, '${tmp.path}/small.jpg');
      final img.Image? out = img.decodeImage(File(r.uploadPath).readAsBytesSync());
      expect(out!.width, 400);
      expect(r.thumb, isNotNull);
      final img.Image? thumb = img.decodeImage(r.thumb!);
      expect(thumb!.width, 200);
      expect(thumb.height, 100);
    });

    // RED if: an out-of-bounds thumb box stops being clamped (copyCrop would
    // still clamp, but a negative width would throw first).
    test('an out-of-bounds thumb box does not throw', () {
      final img.Image src = img.Image(width: 100, height: 100);
      final File f = File('${tmp.path}/tiny.jpg')
        ..writeAsBytesSync(img.encodeJpg(src, quality: 90));
      final OcrFinishResult r = ocrFinishSync((
        imagePath: f.path,
        outPath: '${tmp.path}/tinyout.jpg',
        maxSize: 400,
        quality: 80,
        thumbBox: <double>[-50, -50, 5000, 5000],
      ));
      expect(r.uploadPath, isNotEmpty);
    });
  });

  group('ocrSiblingComponent', () {
    // RED if: the children lookup stops handling a String position (sheet data
    // flips between 7 and "7").
    test('finds a target by int or String position', () {
      screenUIComponent['ocr_sib'] = <String, dynamic>{
        'children': <dynamic>[
          <String, dynamic>{'type': 'ocr_capture', 'position': 4},
          <String, dynamic>{'type': 'txf', 'position': '7', 'format': 'dd/MM/yyyy'},
        ],
      };
      addTearDown(() => screenUIComponent.remove('ocr_sib'));
      expect(ocrSiblingComponent('ocr_sib', 7)['format'], 'dd/MM/yyyy');
      expect(ocrSiblingComponent('ocr_sib', 4)['type'], 'ocr_capture');
    });

    // RED if: an absent screen / absent position starts throwing.
    test('absent screen or position -> null', () {
      expect(ocrSiblingComponent('no_such_screen', 7), isNull);
      screenUIComponent['ocr_sib2'] = <String, dynamic>{'children': 'not a list'};
      addTearDown(() => screenUIComponent.remove('ocr_sib2'));
      expect(ocrSiblingComponent('ocr_sib2', 7), isNull);
    });
  });

  group('ocrWriteToPosition -- the cross-position write (spec 14.4)', () {
    setUp(() {
      txfController.clear();
      if (!Get.isRegistered<WidgetUpdateController>()) {
        Get.put(WidgetUpdateController());
      }
      if (!Get.isRegistered<GeneralGetXController>()) {
        Get.put(GeneralGetXController());
      }
    });

    // RED if: finalData stops being written -> the field LOOKS filled and
    // submits empty. This is the failure this widget exists to avoid.
    test('writes BOTH controller.text and finalData', () {
      ocrWriteToPosition('scr_w', 7, display: '12345', finalData: '12345');
      expect(txfController['scr_w']![7]!.controller.text, '12345');
      expect(txfController['scr_w']![7]!.finalData, '12345');
    });

    // RED if: display and finalData are collapsed into one value -- a date
    // target must SHOW 14-Aug-2026 and SUBMIT epoch millis.
    test('display and finalData can differ (date targets)', () {
      ocrWriteToPosition('scr_w', 8,
          display: '14-Aug-2026', finalData: '1755129600000');
      expect(txfController['scr_w']![8]!.controller.text, '14-Aug-2026');
      expect(txfController['scr_w']![8]!.finalData, '1755129600000');
    });

    // RED if: the separate-controller leg is removed -- a widget that renders
    // its OWN controller would look empty while the slot is filled.
    test('a separate widget controller is written too', () {
      txfControllerCheck('scr_w', 9);
      final TextEditingController own = TextEditingController();
      addTearDown(own.dispose);
      GeneralGetXController.to.putController('scr_w', 9, own);
      ocrWriteToPosition('scr_w', 9, display: 'X', finalData: 'X');
      expect(own.text, 'X');
    });

    // RED if: txfControllerCheck stops being called first -> a null-check crash
    // on a position no widget has created yet.
    test('creates the InputController when absent', () {
      expect(txfController['scr_w2'], isNull);
      ocrWriteToPosition('scr_w2', 3, display: 'A', finalData: 'A');
      expect(txfController['scr_w2']![3]!.finalData, 'A');
    });
  });

  group('ocrImageParameter / ocrMaxSideOf / ocrTargetLabels', () {
    // RED if: the imageParameter default or the maxSize collapse changes ->
    // uploads would grow and blow the agent's quota (spec 6).
    test('imageParameter default and collapse', () {
      expect(ocrImageParameter(SduiSpec(<String, dynamic>{})),
          (maxSize: 400, quality: 80));
      expect(
        ocrImageParameter(
            SduiSpec(<String, dynamic>{'imageParameter': '800,600,70'})),
        (maxSize: 800, quality: 70),
      );
      expect(
        ocrImageParameter(SduiSpec(<String, dynamic>{'imageParameter': 'junk'})),
        (maxSize: 400, quality: 80),
      );
    });

    // RED if: the clamp is removed -> a sheet typo could ask for a 40000 px
    // decode on a low-RAM handset.
    test('ocrMaxSide is clamped', () {
      expect(ocrMaxSideOf(SduiSpec(<String, dynamic>{})), 1600);
      expect(ocrMaxSideOf(SduiSpec(<String, dynamic>{'ocrMaxSide': 40})), 320);
      expect(ocrMaxSideOf(SduiSpec(<String, dynamic>{'ocrMaxSide': 99999})), 4000);
      expect(ocrMaxSideOf(SduiSpec(<String, dynamic>{'ocrMaxSide': '900'})), 900);
    });

    // RED if: the chip label falls back to a hardcoded Indonesian string, or
    // the 5-slot offset changes (spec 3.1).
    test('chip labels come from text[5..] with a position-marker fallback', () {
      final SduiSpec spec = SduiSpec(<String, dynamic>{
        'text': 'L◆cam◆tap◆fail◆badge◆No. Invoice',
      });
      expect(ocrTargetLabels(spec, <int>[11, 12]),
          <String>['No. Invoice', '◁12▷']);
    });
  });
}
