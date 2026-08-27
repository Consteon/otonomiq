// lib/widget/ocr_capture_support.dart
//
// Pure decision + geometry + normalisation helpers for the OCR_CAPTURE widget,
// plus the two compute() entry points and the cross-position writer.
//
// Everything a unit test can drive lives HERE, on purpose: the ML Kit
// MethodChannel throws MissingPluginException under `flutter test`, and a guard
// that lives inside an untestable widget method is an unguarded guard.
//
// NOTHING here imports ML Kit. photo_camera.dart imports this file for
// ocrGuideRect, and photo_camera.dart is the capture path for EVERY page -- so
// an ML Kit resolution failure must break OCR only, never the camera app-wide.
// The one ML-Kit-typed function (ocrFlattenElements) lives in ocr_capture.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../global.dart';
import '../global2.dart';
import '../model/general_get_controller.dart';
import '../model/input_controller.dart';
import '../sdui_spec.dart';

// ---------------------------------------------------------------------------
// Plain data types. List<double> boxes [left, top, right, bottom] rather than
// dart:ui Rect: trivially sendable through compute(), and a unit test can build
// one without touching ML Kit.
// ---------------------------------------------------------------------------

/// One recognised text element reduced to what OCR_CAPTURE needs.
typedef OcrElement = ({String text, List<double> box});

/// compute() message for [ocrPrepareSync].
typedef OcrPrepRequest = ({String imagePath, String cropPath, double? guideRatio});

/// compute() reply from [ocrPrepareSync]. width/height are 0 on failure.
typedef OcrPrepResult = ({int width, int height, String cropPath});

/// compute() message for [ocrFinishSync]. thumbBox is [l,t,r,b] or empty.
typedef OcrFinishRequest = ({
  String imagePath,
  String outPath,
  int maxSize,
  int quality,
  List<double> thumbBox,
});

/// compute() reply from [ocrFinishSync]. uploadPath is '' on failure.
typedef OcrFinishResult = ({String uploadPath, Uint8List? thumb});

/// One resolved target fill.
typedef OcrFill = ({
  String display,
  String finalData,
  String raw,
  List<double> box,
});

// ---------------------------------------------------------------------------
// Tunable constants. Top level ON PURPOSE: these are physical-world knobs a
// field trip may need to move, and hunting for a magic number inside a State
// class is how that knob gets lost.
// ---------------------------------------------------------------------------

/// Shortest digit run accepted as an `ocrType:"number"` candidate.
///
/// A water meter is printed with its unit next to the register and ML Kit reads
/// "m3" as a latin 3 -- so WITHOUT this floor every single capture yields a junk
/// '3'. A 1-character register, plate or serial does not exist, so a floor of 2
/// can never destroy a real reading.
const int ocrMinCandidateDigits = 2;

/// JPEG quality used for the ORIGINAL capture handed to ML Kit (not the upload
/// copy -- that one uses imageParameter's quality).
const int ocrCaptureQuality = 90;

const int ocrMaxSideDefault = 1600;
const int ocrMaxSideFloor = 320;
const int ocrMaxSideCeiling = 4000;

/// Guide box width as a fraction of the frame width.
const double ocrGuideWidthFraction = 0.86;

/// Slack added to EACH side of the guide box before cropping for ML Kit. The
/// overlay painter draws the box with pad 0; the crop uses this. It absorbs the
/// small mismatch between the CameraPreview rect and the captured frame.
const double ocrGuidePadFraction = 0.08;

/// Cap on the `raw` meta column so a dense invoice cannot bloat a record.
const int ocrRawMetaMaxChars = 200;

/// JPEG quality for the form thumbnail crop.
const int ocrThumbQuality = 85;

final RegExp _ocrNonDigit = RegExp(r'[^0-9]');

final RegExp _ocrDatePattern =
    RegExp(r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})');

// ---------------------------------------------------------------------------
// Seed + config parsing
// ---------------------------------------------------------------------------

/// Normalise a record-slot seed value.
///
/// getInitialValue (init_values.dart:11 and :24) returns the LITERAL STRING
/// 'null' when the sheet row has no `currentValue` column: `null.toString()` is
/// "null", which passes the `.trim().isNotEmpty` guard and falls through to the
/// generic branch.
///
/// The '--' sentinel is deliberately NOT normalised -- api.dart:4827 depends on
/// it to fall back to controller.text.
String ocrNormalizeSeed(String raw) => raw == 'null' ? '' : raw;

/// Positions from a `,`-separated config value. Unparseable entries are dropped
/// (never throw on a lean tenant sheet).
List<int> ocrParsePositions(String raw) {
  final List<int> out = <int>[];
  if (raw.trim().isEmpty) return out;
  for (final String part in raw.split(separator[4])) {
    final int? v = int.tryParse(part.trim());
    if (v != null) out.add(v);
  }
  return out;
}

/// Guide aspect ratio from `"4:1"` / `"1.6:1"` / `"4"`. Invalid or absent -> null
/// (= no guide box, full frame).
double? ocrParseRatio(String raw) {
  final String s = raw.trim();
  if (s.isEmpty) return null;
  try {
    final List<String> parts = s.split(':');
    final double a = double.parse(parts[0].trim());
    final double b = parts.length > 1 ? double.parse(parts[1].trim()) : 1.0;
    if (!a.isFinite || !b.isFinite || a <= 0 || b <= 0) return null;
    final double r = a / b;
    return r.isFinite && r > 0 ? r : null;
  } catch (_) {
    return null;
  }
}

/// `ocrMaxSide` clamped to a sane range.
int ocrMaxSideOf(SduiSpec spec) {
  final int v = spec.intOr('ocrMaxSide', ocrMaxSideDefault);
  if (v < ocrMaxSideFloor) return ocrMaxSideFloor;
  if (v > ocrMaxSideCeiling) return ocrMaxSideCeiling;
  return v;
}

/// Upload size/quality from `imageParameter` -- same parse as
/// otq_get_images_2.dart:46-64, including its default.
({int maxSize, int quality}) ocrImageParameter(SduiSpec spec) {
  List<int> p = <int>[400, 400, 80];
  try {
    final List<String> raw =
        spec.str('imageParameter', '400,400,80').split(separator[4]);
    p = <int>[
      int.parse(raw[0].trim()),
      int.parse(raw[1].trim()),
      int.parse(raw[2].trim()),
    ];
  } catch (_) {
    p = <int>[400, 400, 80];
  }
  // maxSize collapses width/height into one dimension (the larger) so the
  // resize preserves aspect ratio -- matches the GET_IMAGES camera path.
  return (maxSize: p[0] > p[1] ? p[0] : p[1], quality: p[2]);
}

/// `ocrType` at [i]: `text` | `number` | `date`. Short list, blank slot or an
/// unknown word all fall back to `text` (spec 3.2).
String ocrTypeAt(List<String> types, int i) {
  final String v =
      types.length > i ? types[i].trim().toLowerCase() : '';
  if (v == 'number' || v == 'date' || v == 'text') return v;
  return 'text';
}

/// Compile a sheet-supplied regex. A malformed pattern must NOT crash the
/// widget -- null means "accept anything".
RegExp? ocrCompile(String pattern) {
  if (pattern.trim().isEmpty) return null;
  try {
    return RegExp(pattern);
  } catch (_) {
    return null;
  }
}

/// `ocrPattern` at [i], length-guarded then compiled.
RegExp? ocrPatternAt(List<String> patterns, int i) =>
    ocrCompile(patterns.length > i ? patterns[i] : '');

/// True when [rx] accepts the value. Matches against BOTH the normalised value
/// and the raw text, because the spec's own examples target both sides
/// (`\d{4,6}` -> normalised meter reading; `\d{2}[/-]\d{2}[/-]\d{2,4}` and
/// `[\d.,]+` -> raw). Fail-open by construction: never strand the agent.
bool ocrAccepts(RegExp? rx, String raw, String normalized) {
  if (rx == null) return true;
  try {
    return rx.hasMatch(normalized) || rx.hasMatch(raw);
  } catch (_) {
    return true;
  }
}

/// Chip labels: `text[5 + i]`, falling back to the position marker `◁pos▷`.
/// Never an Indonesian hardcode.
List<String> ocrTargetLabels(SduiSpec spec, List<int> targets) {
  return <String>[
    for (int i = 0; i < targets.length; i++)
      spec.text(5 + i).trim().isNotEmpty
          ? spec.text(5 + i)
          : '◁${targets[i]}▷',
  ];
}

// ---------------------------------------------------------------------------
// Normalisation (spec 5 -- anti-locale, anti String-vs-Number)
// ---------------------------------------------------------------------------

/// Every 0-9 character of [s], in order.
///
/// Executed, not guessed:
///   "12,345"    -> "12345"
///   "m3"        -> "3"      <- the reason ocrMinCandidateDigits exists
///   "m³ 12345"  -> "12345"  <- a real superscript is not a digit
///   "SN-A0042/B"-> "0042"
String ocrDigits(String s) => s.replaceAll(_ocrNonDigit, '');

/// Plain-number normalisation. NEVER uses a locale formatter.
///
/// The last '.' or ',' decides: a 3-digit tail means it was a THOUSANDS
/// separator, anything else means it was the DECIMAL separator. Leading zeros
/// are stripped per the spec's own table ("01234" -> 1234).
String ocrNormalizeNumber(String raw) {
  final StringBuffer buf = StringBuffer();
  for (final int c in raw.codeUnits) {
    if (c >= 0x30 && c <= 0x39) {
      buf.writeCharCode(c);
    } else if (c == 0x2E || c == 0x2C) {
      buf.writeCharCode(c);
    }
  }
  String s = buf.toString();
  while (s.isNotEmpty && (s.startsWith('.') || s.startsWith(','))) {
    s = s.substring(1);
  }
  while (s.isNotEmpty && (s.endsWith('.') || s.endsWith(','))) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return '';

  final int lastDot = s.lastIndexOf('.');
  final int lastComma = s.lastIndexOf(',');
  final int cut = lastDot > lastComma ? lastDot : lastComma;

  String intPart = s;
  String fracPart = '';
  if (cut >= 0 && (s.length - cut - 1) != 3) {
    intPart = s.substring(0, cut);
    fracPart = s.substring(cut + 1);
  }
  intPart = intPart.replaceAll('.', '').replaceAll(',', '');
  fracPart = fracPart.replaceAll('.', '').replaceAll(',', '');

  int i = 0;
  while (i < intPart.length - 1 && intPart[i] == '0') {
    i++;
  }
  intPart = intPart.substring(i);
  if (intPart.isEmpty) intPart = '0';
  return fracPart.isEmpty ? intPart : '$intPart.$fracPart';
}

/// Day/month/year from `14/08/26`, `14-08-2026`, `14.08.2026`. Rejects an
/// impossible date (31/02 rolls over in DateTime, so probe it).
({int y, int m, int d})? ocrParseDateParts(String raw) {
  final RegExpMatch? m = _ocrDatePattern.firstMatch(raw);
  if (m == null) return null;
  final int d = int.tryParse(m.group(1) ?? '') ?? 0;
  final int mo = int.tryParse(m.group(2) ?? '') ?? 0;
  int y = int.tryParse(m.group(3) ?? '') ?? 0;
  if (d < 1 || d > 31 || mo < 1 || mo > 12) return null;
  if (y < 100) y += 2000;
  if (y < 1900 || y > 2999) return null;
  final DateTime probe = DateTime(y, mo, d);
  if (probe.year != y || probe.month != mo || probe.day != d) return null;
  return (y: y, m: mo, d: d);
}

/// The epoch-millis String a `txf` with `variant:"date"` stores in finalData.
///
/// Mirrors otq_txf_2.dart:732-739 exactly. The tz adjustment makes the result
/// equal to DateTime.utc(y,m,d).millisecondsSinceEpoch -- that identity is what
/// the test asserts, rather than re-computing this expression.
String ocrDateToEpochString(int y, int m, int d, {Duration? tzOverride}) {
  final DateTime local = DateTime(y, m, d);
  final Duration off = tzOverride ?? local.timeZoneOffset;
  return local
      .add(Duration(minutes: off.inMinutes))
      .millisecondsSinceEpoch
      .toString();
}

/// The value that goes into finalData, or null when [raw] yields nothing usable.
String? ocrNormalizeValue(String raw, String type) {
  switch (type) {
    case 'number':
      final String n = ocrNormalizeNumber(raw);
      return n.isEmpty ? null : n;
    case 'date':
      final ({int y, int m, int d})? p = ocrParseDateParts(raw);
      return p == null ? null : ocrDateToEpochString(p.y, p.m, p.d);
    default:
      final String t = raw.trim();
      return t.isEmpty ? null : t;
  }
}

/// The (display, finalData) pair for a target, honouring a `date` target's own
/// `format` (D4). Returns null when [raw] yields nothing usable.
({String display, String finalData})? ocrDisplayAndFinal(
  String raw,
  String type,
  dynamic targetComponent,
) {
  final String? v = ocrNormalizeValue(raw, type);
  if (v == null || v.isEmpty) return null;
  if (type != 'date') return (display: v, finalData: v);

  final ({int y, int m, int d})? p = ocrParseDateParts(raw);
  if (p == null) return null;
  String fm = 'd-MMM-yyyy';
  try {
    final dynamic f = targetComponent is Map ? targetComponent['format'] : null;
    if (f != null && f.toString().trim().isNotEmpty) fm = f.toString();
  } catch (_) {
    fm = 'd-MMM-yyyy';
  }
  String display;
  try {
    display = DateFormat(fm).format(DateTime(p.y, p.m, p.d));
  } catch (_) {
    display = DateFormat('d-MMM-yyyy').format(DateTime(p.y, p.m, p.d));
  }
  return (display: display, finalData: v);
}

// ---------------------------------------------------------------------------
// Candidate selection
//
// ocrFlattenElements (the ML Kit RecognizedText -> OcrElement mapper) lives in
// ocr_capture.dart, NOT here, on purpose: photo_camera.dart imports this file
// for ocrGuideRect, and photo_camera.dart is the capture path for EVERY page in
// the app. Keeping the ML Kit import out of this file means an ML Kit
// resolution failure breaks OCR only, instead of breaking the camera app-wide.
// ---------------------------------------------------------------------------

/// True when [box] is a usable [l,t,r,b].
bool ocrBoxOk(List<double> box) =>
    box.length >= 4 && box[2] > box[0] && box[3] > box[1];

/// The `auto` pick: the accepted candidate with the LONGEST digit run for
/// `number`, ties resolving to the first in reading order; the FIRST accepted
/// element for `text`/`date` (longest-wins is meaningless for those).
OcrFill? ocrPickAuto(List<OcrElement> els, RegExp? rx, String type) {
  OcrFill? best;
  int bestLen = -1;
  for (final OcrElement e in els) {
    final String? v = ocrNormalizeValue(e.text, type);
    if (v == null || v.isEmpty) continue;
    if (type == 'number' && ocrDigits(v).length < ocrMinCandidateDigits) {
      continue;
    }
    if (!ocrAccepts(rx, e.text, v)) continue;
    if (type != 'number') {
      return (display: v, finalData: v, raw: e.text, box: e.box);
    }
    // RAW digit count, NOT the normalised one. ocrNormalizeNumber strips
    // leading zeros, and a water meter prints them as standard -- ranking on
    // the normalised value makes a `012345` register measure 5 and lose to any
    // 6-digit junk in the frame. Ranking raw keeps it a 6, and the tie then
    // resolves by reading order because the compare below is strict.
    final int len = ocrDigits(e.text).length;
    if (len > bestLen) {
      bestLen = len;
      best = (display: v, finalData: v, raw: e.text, box: e.box);
    }
  }
  return best;
}

/// The `raw` meta column when nothing matched: everything ML Kit saw, space
/// joined and truncated. This is the production accuracy instrument (spec 13).
String ocrRawSummary(List<OcrElement> els) {
  final String joined =
      els.map((OcrElement e) => e.text.trim()).where((String s) => s.isNotEmpty).join(' ');
  return joined.length <= ocrRawMetaMaxChars
      ? joined
      : joined.substring(0, ocrRawMetaMaxChars);
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// The guide box in image pixels: `[x, y, width, height]`, or `[]` when it is
/// degenerate. Called TWICE with different [pad]: the camera overlay draws the
/// tight box (pad 0), the ML Kit crop takes the padded one.
List<int> ocrGuideRect(
  int w,
  int h,
  double ratio, {
  double widthFraction = ocrGuideWidthFraction,
  double pad = ocrGuidePadFraction,
}) {
  if (w <= 0 || h <= 0 || !ratio.isFinite || ratio <= 0) return const <int>[];
  double bw = w * widthFraction;
  double bh = bw / ratio;
  if (bh > h * 0.9) {
    bh = h * 0.9;
    bw = bh * ratio;
  }
  bw = bw * (1 + pad * 2);
  bh = bh * (1 + pad * 2);
  if (bw > w) bw = w.toDouble();
  if (bh > h) bh = h.toDouble();
  final int x = ((w - bw) / 2).round().clamp(0, w - 1);
  final int y = ((h - bh) / 2).round().clamp(0, h - 1);
  int cw = bw.round();
  int ch = bh.round();
  if (x + cw > w) cw = w - x;
  if (y + ch > h) ch = h - y;
  if (cw < 8 || ch < 8) return const <int>[];
  return <int>[x, y, cw, ch];
}

// ---------------------------------------------------------------------------
// compute() entry points -- pure Dart, isolate safe.
//
// Flutter 3.44 merged the UI thread into main, so a heavy pure-Dart decode on
// the main isolate is an ANR, not jank. And DEBUG runs the `image` pipeline
// 10-30x slower than AOT -- never judge decode speed from `flutter run`.
//
// img.decodeImage THROWS (RangeError out of PsdDecoder.isValidFile) on a short
// or corrupt buffer instead of returning null as documented. Every call is
// inside a try. FAIL OPEN at every rung.
// ---------------------------------------------------------------------------

/// Decode once: report the upright pixel dimensions and, when a guide ratio was
/// requested, write the cropped region to [OcrPrepRequest.cropPath].
///
/// width/height 0 means the decode failed -> the caller reads the FULL frame and
/// skips the tap overlay geometry.
OcrPrepResult ocrPrepareSync(OcrPrepRequest req) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(File(req.imagePath).readAsBytesSync());
  } catch (_) {
    return (width: 0, height: 0, cropPath: '');
  }
  if (decoded == null) return (width: 0, height: 0, cropPath: '');

  img.Image src = decoded;
  try {
    // bakeOrientation does a full copy even when orientation is already 1, so
    // only pay for it when EXIF actually asks. (acquireCamera already returns a
    // baked file -- this is the defensive leg for the gallery path.)
    final int orientation = src.exif.imageIfd.hasOrientation
        ? (src.exif.imageIfd.orientation ?? 1)
        : 1;
    if (orientation != 1) src = img.bakeOrientation(src);
  } catch (_) {
    src = decoded;
  }

  String cropPath = '';
  final double? ratio = req.guideRatio;
  if (ratio != null && req.cropPath.isNotEmpty) {
    try {
      final List<int> r = ocrGuideRect(src.width, src.height, ratio);
      if (r.length == 4) {
        final img.Image cropped =
            img.copyCrop(src, x: r[0], y: r[1], width: r[2], height: r[3]);
        File(req.cropPath)
            .writeAsBytesSync(img.encodeJpg(cropped, quality: ocrCaptureQuality));
        cropPath = req.cropPath;
      }
    } catch (_) {
      cropPath = '';
    }
  }
  return (width: src.width, height: src.height, cropPath: cropPath);
}

/// Decode once more: crop the form thumbnail AND write the imageParameter-sized
/// upload copy.
///
/// uploadPath '' means the shrink failed -> the caller uploads the ORIGINAL
/// rather than losing the photo. thumb null -> the caller falls back to the
/// plain photo preview (D7).
OcrFinishResult ocrFinishSync(OcrFinishRequest req) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(File(req.imagePath).readAsBytesSync());
  } catch (_) {
    return (uploadPath: '', thumb: null);
  }
  if (decoded == null) return (uploadPath: '', thumb: null);

  img.Image src = decoded;
  try {
    final int orientation = src.exif.imageIfd.hasOrientation
        ? (src.exif.imageIfd.orientation ?? 1)
        : 1;
    if (orientation != 1) src = img.bakeOrientation(src);
  } catch (_) {
    src = decoded;
  }

  Uint8List? thumb;
  try {
    final List<double> b = req.thumbBox;
    if (ocrBoxOk(b)) {
      final int x = b[0].round().clamp(0, src.width - 1);
      final int y = b[1].round().clamp(0, src.height - 1);
      int cw = (b[2] - b[0]).round();
      int ch = (b[3] - b[1]).round();
      if (x + cw > src.width) cw = src.width - x;
      if (y + ch > src.height) ch = src.height - y;
      if (cw >= 8 && ch >= 8) {
        thumb = Uint8List.fromList(
          img.encodeJpg(
            img.copyCrop(src, x: x, y: y, width: cw, height: ch),
            quality: ocrThumbQuality,
          ),
        );
      }
    }
  } catch (_) {
    thumb = null;
  }

  String out = '';
  try {
    img.Image resized = src;
    // Only ever DOWN-scale.
    if (src.width > req.maxSize || src.height > req.maxSize) {
      resized = src.height > src.width
          ? img.copyResize(src, height: req.maxSize)
          : img.copyResize(src, width: req.maxSize);
    }
    File(req.outPath)
        .writeAsBytesSync(img.encodeJpg(resized, quality: req.quality));
    out = req.outPath;
  } catch (_) {
    out = '';
  }
  return (uploadPath: out, thumb: thumb);
}

// ---------------------------------------------------------------------------
// Cross-position write (spec 14.4 -- CLOSED, see clearData api.dart:4630-4683)
// ---------------------------------------------------------------------------

/// The sibling component that owns [position] on [scrName], or null.
///
/// screenUIComponent[scrName]['children'] is a flat List of component maps
/// (ui_component.dart:20-23), so a widget CAN look a sibling up by position.
/// This is how a `date` target's `format` is found (D4).
dynamic ocrSiblingComponent(String scrName, int position) {
  try {
    final dynamic children = screenUIComponent[scrName]?['children'];
    if (children is! List) return null;
    for (final dynamic c in children) {
      if (c is! Map) continue;
      final dynamic p = c['position'];
      if (p == null) continue;
      final int? pi = p is int ? p : int.tryParse(p.toString());
      if (pi == position) return c;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Write a value into ANOTHER widget's record slot AND make it visible.
///
/// THREE writes plus a repaint -- one of them is not optional:
///  1. controller.text  -- what a txf renders (its myController IS this object
///     in the SDUI path, otq_txf_2.dart:317-328)
///  2. finalData        -- what submit reads
///  3. the widget's OWN controller, when it keeps a separate one
///     (GeneralGetXController.getController). The `identical` guard makes this a
///     no-op for txf and a real write for anything that does own one.
///  4. WidgetUpdateController.update(['scrName-pos']) -- the id otq_txf_2
///     registers (otq_txf_2.dart:646-647) and the id clearData uses
///     (api.dart:4647).
void ocrWriteToPosition(
  String scrName,
  int position, {
  required String display,
  required String finalData,
}) {
  try {
    txfControllerCheck(scrName, position);
    final InputController ic = txfController[scrName]![position]!;
    ic.controller.text = display;
    ic.controller.selection = TextSelection.collapsed(offset: display.length);
    ic.finalData = finalData;
    final dynamic other =
        GeneralGetXController.to.getController(scrName, position);
    if (other is TextEditingController && !identical(other, ic.controller)) {
      other.text = display;
    }
  } catch (e) {
    errorReport(e);
  }
  try {
    Get.find<WidgetUpdateController>().update(<String>['$scrName-$position']);
  } catch (_) {
    // No GetX registered (unit test / very early boot). The slot is written;
    // the repaint is cosmetic.
  }
}
