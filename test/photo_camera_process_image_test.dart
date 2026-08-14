import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:otonomiq/widget/photo_camera.dart';

// processCapturedImage is the pure-Dart decode -> resize -> watermark -> encode
// step that runs between the shutter and the Accept button going live. Every
// pixel it touches is wait the user sees, so the one thing worth pinning is
// that it never manufactures pixels: ResolutionPreset.medium caps the capture
// at 720x480, and a component with a larger `imageParameter` used to UPSCALE
// to that size before encoding.

Uint8List _jpgOf({required int width, required int height}) {
  final img.Image src = img.Image(width: width, height: height);
  img.fill(src, color: img.ColorRgb8(120, 130, 140));
  return Uint8List.fromList(img.encodeJpg(src, quality: 90));
}

Future<img.Image> _run(
  Uint8List bytes,
  int maxSize,
) async {
  final Uint8List out = await processCapturedImage(
    ImageProcessArgs(
      bytes: bytes,
      maxSize: maxSize,
      quality: 80,
      dateTime: '2026-08-14 10:00:00',
    ),
  );
  final img.Image? decoded = img.decodeImage(out);
  expect(decoded, isNotNull, reason: 'must always return encodable bytes');
  return decoded!;
}

void main() {
  test('landscape capture larger than maxSize is scaled down by width',
      () async {
    final img.Image out = await _run(_jpgOf(width: 720, height: 480), 400);
    expect(out.width, 400);
    expect(out.height, 267); // aspect ratio preserved
  });

  test('portrait capture larger than maxSize is scaled down by height',
      () async {
    final img.Image out = await _run(_jpgOf(width: 480, height: 720), 400);
    expect(out.height, 400);
    expect(out.width, 267);
  });

  test('capture already within maxSize is NOT upscaled', () async {
    // 720x480 capture, component asks for 900 -> stays 720x480. Upscaling here
    // costs ~1.5x the pixels to watermark and JPG-encode for zero detail, all
    // of it inside the wait before Accept.
    final img.Image out = await _run(_jpgOf(width: 720, height: 480), 900);
    expect(out.width, 720);
    expect(out.height, 480);
  });

  test('maxSize equal to the capture size is a no-op resize', () async {
    final img.Image out = await _run(_jpgOf(width: 720, height: 480), 720);
    expect(out.width, 720);
    expect(out.height, 480);
  });

  test('undecodable bytes are returned untouched, never thrown', () async {
    final Uint8List junk = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    final Uint8List out = await processCapturedImage(
      ImageProcessArgs(
        bytes: junk,
        maxSize: 400,
        quality: 80,
        dateTime: '2026-08-14 10:00:00',
      ),
    );
    expect(out, junk);
  });
}
