// test/display_image_fallback_test.dart
//
// displayImage's LOCAL branch: what happens when the local file is gone.
//
// The local copy can genuinely vanish: _capture's `finally` deletes shrunkPath,
// and renamePath's double-failure fallback can hand back that very path as the
// url -- plus app storage being cleared. Before this round that branch gave up
// and painted `defaultImage`, which is how a meter photo that had ALREADY
// uploaded rendered as a broken placeholder. imageMap is the
// local-path -> Storage-url ledger and is a synchronous Map lookup, so the
// second attempt is safe from build().
//
// Every test here inspects the RETURNED widget; nothing is pumped, so no test
// in this file touches the network or the cache manager.
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otonomiq/api.dart' show displayImage;
import 'package:otonomiq/global.dart'
    show
        defaultImage,
        emptyString,
        imageMap,
        invalidPathPostfix,
        invalidPathPrefix,
        localImagePostfix,
        localImagePrefix;

void main() {
  // The shape isValidImageUrl accepts (firestore_generic_repository.dart).
  const String cloudUrl =
      'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/meter%2Fabc.jpg'
      '?alt=media&token=30e55f7e-7a5e-44ab-a77b-eced57355cd3';
  const String missingPath = '/does/not/exist/ocrup123.jpg';
  const String missingUrl = '$localImagePrefix$missingPath$localImagePostfix';

  // imageMap is a plain global Map: a leaked row would answer a later test.
  setUp(imageMap.clear);
  tearDown(imageMap.clear);

  test('an uploaded photo falls back to its Storage url', () {
    imageMap[missingPath] = <dynamic>[1740500867945, cloudUrl, true, 1, 0];
    final Widget w = displayImage(imageUrl: missingUrl, cached: true);
    expect(w, isA<CachedNetworkImage>());
    expect((w as CachedNetworkImage).imageUrl, cloudUrl);
  });

  test('an upload still queued shows the pending icon, not the give-up image',
      () {
    imageMap[missingPath] = <dynamic>[1740500867945, emptyString, false, 0, 0];
    final Widget w = displayImage(imageUrl: missingUrl, cached: true);
    expect(w, isA<Icon>());
    expect((w as Icon).icon, Icons.cloud_upload_outlined);
  });

  test('a poisoned entry (InvalidImagePath) shows pending, never that string',
      () {
    imageMap[missingPath] = <dynamic>[
      1740500867945,
      '${invalidPathPrefix}01$invalidPathPostfix',
      false,
      5,
      0,
    ];
    expect(displayImage(imageUrl: missingUrl, cached: true), isA<Icon>());
  });

  test('a short entry never throws (conventions rule 3)', () {
    imageMap[missingPath] = <dynamic>[1740500867945];
    expect(displayImage(imageUrl: missingUrl, cached: true), isA<Icon>());
    imageMap[missingPath] = <dynamic>[];
    expect(displayImage(imageUrl: missingUrl, cached: true), isA<Icon>());
    imageMap[missingPath] = <dynamic>[1, null, false, 0, 0];
    expect(displayImage(imageUrl: missingUrl, cached: true), isA<Icon>());
  });

  test('an entry of the wrong TYPE is swallowed, not thrown', () {
    // imageMap is Map<String, dynamic>; imageMapGet's implicit cast to
    // List<dynamic> throws here and lands in displayImage's own catch.
    imageMap[missingPath] = 'garbage';
    expect(displayImage(imageUrl: missingUrl, cached: true),
        isA<CachedNetworkImage>());
  });

  test('no imageMap entry keeps exactly the old give-up behaviour', () {
    final Widget w = displayImage(imageUrl: missingUrl, cached: true);
    expect(w, isA<CachedNetworkImage>());
    expect((w as CachedNetworkImage).imageUrl, defaultImage);
  });

  test('a local file that EXISTS still wins over the imageMap url', () {
    final Directory d = Directory.systemTemp.createTempSync('otq_disp');
    final File f = File('${d.path}/real.jpg')..writeAsBytesSync(<int>[1, 2, 3]);
    imageMap[f.path] = <dynamic>[1, cloudUrl, true, 0, 0];
    final Widget w =
        displayImage(imageUrl: '$localImagePrefix${f.path}$localImagePostfix');
    expect(w, isA<Image>());
    d.deleteSync(recursive: true);
  });

  test('the network branch is untouched (cached true)', () {
    imageMap[missingPath] = <dynamic>[1, emptyString, false, 0, 0];
    final Widget w = displayImage(imageUrl: cloudUrl, cached: true);
    expect(w, isA<CachedNetworkImage>());
    expect((w as CachedNetworkImage).imageUrl, cloudUrl);
  });

  test('the network branch is untouched (cached false)', () {
    expect(displayImage(imageUrl: cloudUrl, cached: false), isA<FadeInImage>());
  });
}
