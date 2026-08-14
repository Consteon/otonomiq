import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../global.dart';

String inputPath = emptyString; // temporary path variable

class ImageProcessArgs {
  final Uint8List bytes;
  final int maxSize;
  final int quality;
  final String dateTime;
  const ImageProcessArgs({
    required this.bytes,
    required this.maxSize,
    required this.quality,
    required this.dateTime,
  });
}

/// Runs in a background isolate (via compute) so the shutter doesn't freeze the
/// UI (~1s) on every capture: decode -> bake orientation -> resize -> draw two
/// text watermarks straight onto the decoded image -> single jpg encode.
/// Pure-Dart (image pkg), so it is isolate-safe. Always returns bytes — falls
/// back to the input on any failure.
Future<Uint8List> processCapturedImage(ImageProcessArgs a) async {
  // decodeImage sniffs the format by trying each decoder, and some of them
  // (PSD) THROW a RangeError on a buffer too short to hold their header rather
  // than reporting "not mine" — so a truncated capture (killed mid-write, disk
  // full) escapes as an isolate rejection, not the documented null.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(a.bytes);
  } catch (_) {
    return a.bytes;
  }
  if (decoded == null) return a.bytes;
  img.Image image = decoded;
  try {
    image = img.bakeOrientation(image);
  } catch (_) {}
  img.Image resizedImage = image;
  try {
    // Only ever DOWN-scale. ResolutionPreset.medium caps the capture at 720x480
    // (camerax) / 480x360 (avfoundation), so a maxSize above that used to
    // UPSCALE the photo — more pixels to watermark and JPG-encode, for zero
    // detail, straight onto the wait before Accept.
    if (image.width > a.maxSize || image.height > a.maxSize) {
      if (image.height > image.width) {
        resizedImage = img.copyResize(image, height: a.maxSize);
      } else {
        resizedImage = img.copyResize(image, width: a.maxSize);
      }
    }
  } catch (_) {}
  // Bake both watermark texts (dark shadow + blue) directly onto the decoded
  // image, then JPG-encode ONCE. The old image_watermark path decoded and
  // re-encoded as PNG twice per shot — slow, and it silently returned an
  // oversized PNG stored under a .jpg name, throwing away the JPG quality.
  try {
    img.drawString(
      resizedImage,
      a.dateTime,
      font: img.arial14,
      x: 11,
      y: 9,
      color: img.ColorRgba8(10, 10, 10, 150),
    );
    img.drawString(
      resizedImage,
      a.dateTime,
      font: img.arial14,
      x: 10,
      y: 8,
      color: img.ColorRgba8(24, 129, 240, 255),
    );
  } catch (_) {}
  return Uint8List.fromList(img.encodeJpg(resizedImage, quality: a.quality));
}

class PhotoCamera extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String? label;
  final int? direction;
  final int? maxSize;
  //final BuildContext? context;
  final int? quality;
  final double? height;
  final double? width;
  final List<String> imageUrl;
  const PhotoCamera({
    super.key,
    //this.context,
    required this.cameras,
    this.label,
    this.direction,
    this.maxSize,
    this.quality,
    this.height,
    this.width,
    required this.imageUrl,
  });

  @override
  PhotoCameraState createState() => PhotoCameraState();
}

class PhotoCameraState extends State<PhotoCamera> with WidgetsBindingObserver {
  bool tapDetector = false;
  MediaQueryData? media;
  static double controlHeight = 400; // was 325

  @override
  void initState() {
    gotPicture = false;
    flashIndex = 0;
    selectedCamera = widget.direction ?? 0;
    // Register the lifecycle observer so didChangeAppLifecycleState actually
    // fires — without this the resumed-handler that rebuilds the controller
    // never runs, leaving a blank white preview after a permission dialog or
    // an app background/foreground.
    WidgetsBinding.instance.addObserver(this);
    initializeCamera(selectedCamera, flashIndex); //Initially selectedCamera = 0
    super.initState();
  }

  /// `CameraController.dispose()` NEVER rejects through this.
  ///
  /// camera_android_camerax throws `IllegalStateException:
  /// releaseFlutterSurfaceTexture() cannot be called if the
  /// flutterSurfaceProducer for the camera preview has not yet been
  /// initialized` whenever the controller is torn down before the preview's
  /// surface producer exists — `initialize()` still in flight, OR
  /// `CameraPreview` never rendered a frame (app backgrounded right after the
  /// camera opened). `value.isInitialized` does NOT cover the second case: it
  /// flips on `initialize()`, while the surface producer is created later by
  /// the preview widget.
  ///
  /// Every dispose site here is either fire-and-forget or reached from an
  /// un-awaited caller, so a rejection escapes to platformDispatcher.onError
  /// as a FATAL with no app frames. Guarded once, here, rather than per call
  /// site. There is nothing to recover — the controller is being thrown away.
  ///
  /// It also records [c] in [_disposedController] so `build()` can refuse to
  /// render a preview on it — see that field.
  Future<void> _safeDisposeCamera(CameraController? c) async {
    if (c == null) return;
    _disposedController = c;
    try {
      await c.dispose();
    } catch (e) {
      devPrint('camera dispose (uninitialized?): $e');
    }
  }

  /// The most recent controller handed to [_safeDisposeCamera].
  ///
  /// ★ `CameraController.dispose()` does NOT reset `value.isInitialized` — it
  /// only flips a private `_isDisposed`. So the build guard's
  /// `controller!.value.isInitialized` cannot tell a live controller from a
  /// dead one, and any frame drawn after the lifecycle observer disposed on
  /// `inactive` (which leaves the `controller` field pointing at the corpse)
  /// mounted `CameraPreview` → `buildPreview()` →
  /// `CameraException(Disposed CameraController)` during drawFrame = fatal.
  ///
  /// Identity comparison rather than a bool so the three controller-creation
  /// sites need no bookkeeping: a fresh controller is never identical to this.
  CameraController? _disposedController;

  @override
  void dispose() {
    _safeDisposeCamera(controller); // never rejects — see helper
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // #docregion AppLifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _safeDisposeCamera(cameraController);
    } else if (state == AppLifecycleState.resumed) {
      // Un-awaited from a void callback: onNewCameraSelected still awaits
      // initialize(), whose PlatformException is NOT caught by its
      // `on CameraException` clause. Route the rejection to a non-fatal.
      safeUnawaited(
        onNewCameraSelected(cameraController.description),
        'photoCamera resumed',
      );
    }
  } // end of didChangeAppLifecycleState
  // #enddocregion AppLifecycle

  CameraController? controller; //To control the camera
  late Future<void>
  _initializeControllerFuture; //Future to wait until camera initializes
  int selectedCamera = 0;
  int flashIndex = 0;
  late bool gotPicture;
  bool _processing = false; // shutter busy: blocks re-entry, shows spinner

  /// The watermark bake+write running behind the already-visible preview.
  ///
  /// Accept AWAITS this instead of staying disabled until it completes. Same
  /// invariant (the file handed to the form is always the watermarked one),
  /// but the wait now overlaps the user's own look-at-the-photo-and-reach-for-
  /// the-button time instead of being serialized after it. Never rejects —
  /// [_finalizeCapture] swallows everything.
  Future<void>? _finalizeFuture;
  bool _accepting = false; // Accept tapped before the bake finished
  List<IconData> flashIcons = [
    Icons.flash_auto_rounded,
    Icons.flash_on_rounded,
    Icons.lightbulb,
    Icons.flash_off_rounded,
  ];
  List<File> capturedImages = [];
  File? currentImage;

  Future<void> _doInitializeCamera(int cameraIndex, int flashIndex) async {
    await _safeDisposeCamera(controller);
    controller = CameraController(
      widget.cameras[cameraIndex],
      ResolutionPreset.medium,
    );

    // The previous camera owner (QR scanner via mobile_scanner) may still be
    // releasing the hardware, so initialize() fails and the preview shows blank
    // white. Retry a few times on a fresh controller with a short backoff
    // before giving up.
    for (int attempt = 0; ; attempt++) {
      try {
        await controller!.initialize();
        break;
      } catch (e) {
        if (attempt >= 3) rethrow;
        await Future.delayed(const Duration(milliseconds: 300));
        // A controller whose initialize() just failed has no surface producer,
        // so a raw dispose() here would throw OUT of this catch block.
        await _safeDisposeCamera(controller);
        controller = CameraController(
          widget.cameras[cameraIndex],
          ResolutionPreset.medium,
        );
      }
    }
    // The 500ms settle used to sit INSIDE _initializeControllerFuture, so the
    // FutureBuilder kept the spinner up for half a second AFTER the camera was
    // already live. Keep the settle (setFlashMode right after initialize() is
    // flaky on some devices) but run it behind the preview.
    final CameraController c = controller!;
    safeUnawaited(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted || identical(c, _disposedController)) return;
      await c.setFlashMode(_flashModeFor(flashIndex));
    }(), 'photoCamera setFlashMode');
  }

  FlashMode _flashModeFor(int index) {
    switch (index) {
      case 1:
        return FlashMode.always;
      case 2:
        return FlashMode.torch;
      case 3:
        return FlashMode.off;
      default:
        return FlashMode.auto;
    }
  }

  void initializeCamera(int cameraIndex, int flashIndex) {
    _initializeControllerFuture = _doInitializeCamera(cameraIndex, flashIndex);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    final CameraController? oldController = controller;
    if (oldController != null) {
      // `controller` needs to be set to null before getting disposed,
      // to avoid a race condition when we use the controller that is being
      // disposed. This happens when camera permission dialog shows up,
      // which triggers `didChangeAppLifecycleState`, which disposes and
      // re-creates the controller.
      controller = null;
      // Reached from the resumed branch above with an ALREADY-disposed
      // controller (the inactive branch disposed it and left the field set),
      // so this dispose is exactly the throwing case.
      await _safeDisposeCamera(oldController);
    }
    bool kIsWeb = false;
    final CameraController cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.medium,
      // enableAudio: enableAudio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    try {
      await cameraController.initialize();
      // await Future.wait(<Future<Object?>>[
      //   // The exposure mode is currently not supported on the web.
      //   ...!kIsWeb
      //       ? <Future<Object?>>[
      //           cameraController.getMinExposureOffset().then(
      //               (double value) => _minAvailableExposureOffset = value),
      //           cameraController
      //               .getMaxExposureOffset()
      //               .then((double value) => _maxAvailableExposureOffset = value)
      //         ]
      //       : <Future<Object?>>[],
      //   cameraController
      //       .getMaxZoomLevel()
      //       .then((double value) => _maxAvailableZoom = value),
      //   cameraController
      //       .getMinZoomLevel()
      //       .then((double value) => _minAvailableZoom = value),
      // ]);
    } on CameraException {
      // switch (e.code) {
      //   case 'CameraAccessDenied':
      //     showInSnackBar('You have denied camera access.');
      //     break;
      //   case 'CameraAccessDeniedWithoutPrompt':
      //     // iOS only
      //     showInSnackBar('Please go to Settings app to enable camera access.');
      //     break;
      //   case 'CameraAccessRestricted':
      //     // iOS only
      //     showInSnackBar('Camera access is restricted.');
      //     break;
      //   case 'AudioAccessDenied':
      //     showInSnackBar('You have denied audio access.');
      //     break;
      //   case 'AudioAccessDeniedWithoutPrompt':
      //     // iOS only
      //     showInSnackBar('Please go to Settings app to enable audio access.');
      //     break;
      //   case 'AudioAccessRestricted':
      //     // iOS only
      //     showInSnackBar('Audio access is restricted.');
      //     break;
      //   default:
      //     _showCameraException(e);
      //     break;
      // }
    }

    if (mounted) {
      setState(() {});
    }
  } //onNewCameraSelected

  /// Bakes the watermark onto [rawFile] and points [currentImage] at the
  /// resulting `.jpg`. Runs behind the already-visible preview.
  ///
  /// NEVER rejects — Accept awaits it bare, and a rejection there would escape
  /// an async button callback straight to platformDispatcher.onError.
  Future<void> _finalizeCapture(File rawFile, String rawPath) async {
    try {
      final String imagePath =
          "${rawPath.split("/CAP")[0]}/$localImageArtifact${globalRandom.nextInt(999999999)}.jpg";
      final String formattedDateTime = DateFormat(
        dateTimeFormat,
      ).format(DateTime.now());
      final Uint8List rawBytes = await rawFile.readAsBytes();
      Uint8List watermarkedImage;
      try {
        // A stalled / OOM-killed isolate on low-RAM devices decoding the
        // capture never settles — the await would hang and Accept would block
        // on it forever ("foto tidak berhasil, tanpa hasil"). Cap it and fall
        // back to the raw (un-watermarked) bytes so the capture always
        // completes.
        watermarkedImage = await compute(
          processCapturedImage,
          ImageProcessArgs(
            bytes: rawBytes,
            maxSize: widget.maxSize ?? 500,
            quality: widget.quality ?? 80,
            dateTime: formattedDateTime,
          ),
        ).timeout(const Duration(seconds: 12));
      } catch (e) {
        errorReport('image processing error/timeout: $e');
        watermarkedImage = rawBytes;
      }
      bool wrote = false;
      try {
        await File(imagePath).writeAsBytes(watermarkedImage);
        wrote = true;
      } catch (e) {
        errorReport('write captured image error: $e');
      }
      // write failed -> keep the valid raw file rather than pointing at a
      // missing watermarked path. Assigned OUTSIDE setState because Accept
      // reads currentImage after awaiting this, mounted or not.
      if (wrote) {
        currentImage = File(imagePath);
        // drop the raw temp only once the watermarked file is safely written.
        try {
          await rawFile.delete();
        } catch (e) {
          devPrint('delete temp capture error: $e');
        }
      }
    } catch (e) {
      errorReport('finalize capture error: $e');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    media = MediaQuery.maybeOf(context);
    double currentWidth = (media?.size.width ?? widget.width) ?? controlHeight;
    double currentHeight =
        (media?.size.height ?? widget.height) ?? controlHeight;
    double pictureHeight = currentHeight - controlHeight;
    int d = 1;

    return Stack(
      children: [
        gotPicture
            ? Container(
                height: pictureHeight,
                alignment: Alignment.center,
                // width: MediaQuery.of(context).size.width * picFactor,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(4),
                  image: DecorationImage(
                    // image: FileImage(capturedImages.last),
                    image: FileImage(currentImage!),
                    // Accept hands this /cache/OTQC*.jpg path to the form and
                    // pops; saveImageToCloud → renamePath then MOVES the file
                    // out of /cache while this page can still repaint (and
                    // Android may evict /cache anyway) → FileImage.length()
                    // PathNotFoundException. DecorationImage has no
                    // errorBuilder, so without onError it escapes to
                    // FlutterError.onError = fatal.
                    onError: (e, s) => devPrint('preview image gone: $e'),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            : FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      !snapshot.hasError &&
                      controller != null &&
                      !identical(controller, _disposedController) &&
                      controller!.value.isInitialized) {
                    // Only show the preview when the camera is really live —
                    // rendering CameraPreview on a failed/half-initialized
                    // controller is exactly what produced the blank white frame,
                    // and on a DISPOSED one it throws inside drawFrame (see
                    // _disposedController — isInitialized stays true there).
                    return Container(
                      //width: pictureWidth,
                      height: pictureHeight,
                      //width: MediaQuery.of(context).size.width * picFactor,
                      alignment: Alignment.center,
                      child: CameraPreview(controller!),
                    );
                  } else {
                    // Otherwise, display a loading indicator.
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              ),
        SizedBox(
          height: currentHeight,
          width: currentWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height: pictureHeight,
                // width: MediaQuery.of(context).size.width * picFactor,
                color: Colors.transparent, //Color.fromRgba(0,0,0,0),
              ),
              // Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: SizedBox(
                  width: currentWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    // crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IconButton(
                        onPressed: () {
                          if (selectedCamera == 0 && !gotPicture) {
                            setState(() {
                              flashIndex = (flashIndex + 1) % flashIcons.length;
                            });
                            switch (flashIndex) {
                              case 0:
                                {
                                  // _controller.setFlashMode(FlashMode.off);
                                  controller!.setFlashMode(FlashMode.auto);
                                }
                                break;

                              case 1:
                                {
                                  controller!.setFlashMode(FlashMode.always);
                                }
                                break;

                              case 2:
                                {
                                  controller!.setFlashMode(FlashMode.torch);
                                }
                                break;

                              case 3:
                                {
                                  controller!.setFlashMode(FlashMode.off);
                                }
                                break;
                            } // end switch
                          }
                        },
                        icon: Icon(
                          flashIcons[flashIndex],
                          color: selectedCamera == 1 || gotPicture
                              ? colorMap['disabled']
                              : colorMap['enabled'],
                          size: 40,
                        ),
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      ),
                      IconButton(
                        onPressed: () async {
                          if (gotPicture || _processing) return;
                          setState(() => _processing = true);
                          try {
                            await _initializeControllerFuture;
                            final xFile = await controller!.takePicture();
                            // restore flash for the next shot
                            controller!.setFlashMode(_flashModeFor(flashIndex));

                            // Show the just-captured frame IMMEDIATELY from the
                            // raw file (native codec = instant). The pure-Dart
                            // decode/resize/watermark pipeline runs AFTER, in
                            // the background, then swaps in the watermarked
                            // file. Accept is live right away and awaits that
                            // swap on tap (see _finalizeFuture), so the saved
                            // file is still always the watermarked one.
                            final File rawFile = File(xFile.path);
                            setState(() {
                              currentImage = rawFile;
                              gotPicture = true;
                              _processing = false;
                            });
                            _finalizeFuture = _finalizeCapture(
                              rawFile,
                              xFile.path,
                            );
                          } catch (e) {
                            errorReport('capture error: $e');
                            if (mounted) {
                              setState(() => _processing = false);
                            }
                          }
                        },
                        icon: Icon(
                          Icons.camera, // camera
                          color: gotPicture || _processing
                              ? colorMap['disabled']
                              : colorMap['enabled'],
                          size: 70,
                        ),
                        // padding: const EdgeInsets.fromLTRB(0, 0, 35, 35),
                      ),
                      IconButton(
                        onPressed: () {
                          if (!tapDetector) {
                            // ignore double tap
                            tapDetector = true;
                            if (widget.cameras.length > 1 && !gotPicture) {
                              setState(() {
                                selectedCamera = selectedCamera == 0 ? 1 : 0;
                                initializeCamera(selectedCamera, flashIndex);
                              });
                              if (flashIndex == 2) {
                                controller!.setFlashMode(FlashMode.torch);
                              }
                            }
                            Future.delayed(
                              const Duration(milliseconds: 1200),
                              () {
                                // wait until the camera is stable
                                tapDetector = false;
                              },
                            );
                          }
                        },
                        icon: Icon(
                          Icons.switch_camera_rounded,
                          color: gotPicture
                              ? colorMap['disabled']
                              : colorMap['enabled'],
                          size: 40,
                        ),
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      ),
                    ],
                  ),
                ),
              ),
              // Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(50, 0, 50, 0),
                child: SizedBox(
                  // width: MediaQuery.of(context).size.width,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          // Accept already awaiting the bake -> its Get.back()
                          // is coming; a second pop here would close the caller
                          // page too.
                          if (_accepting) return;
                          if (gotPicture) {
                            setState(() {
                              gotPicture = false;
                            });
                          }
                          Get.back();
                        },
                        icon: Icon(
                          // Icons.cancel_outlined,
                          Icons.cancel_outlined,
                          color: colorMap['cancel'],
                          size: 40,
                        ),
                        // padding: const EdgeInsets.fromLTRB(0, 0, 24, 0),
                      ),
                      IconButton(
                        onPressed: () async {
                          if (!gotPicture || _accepting) return;
                          final Future<void>? pending = _finalizeFuture;
                          if (pending != null) {
                            // Normally already complete (the bake ran while the
                            // user was looking at the shot) -> returns on the
                            // next microtask. Only a genuinely slow device is
                            // still working here, and then the spinner says so.
                            setState(() => _accepting = true);
                            await pending; // never rejects — see _finalizeCapture
                            if (!mounted) return;
                            setState(() => _accepting = false);
                          }
                          inputPath = currentImage!.path;
                          widget.imageUrl[0] = currentImage!.path;
                          Get.back();
                          //Navigator.of(context).pop();
                        },
                        icon: Icon(
                          Icons.check_circle,
                          color: !gotPicture || _accepting
                              ? colorMap['disabled']
                              : colorMap['enabled'],
                          size: 40,
                        ),
                        // padding: const EdgeInsets.fromLTRB(0, 0, 24, 0),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_processing || _accepting)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

Future<String> acquireCamera(
  List<CameraDescription> cameras,
  String label,
  String direction,
  int maxSize,
  int quality,
  double? height,
  double? width,
) async {
  // inputPath = emptyString;
  FocusManager.instance.primaryFocus?.unfocus();
  await Future.delayed(const Duration(milliseconds: 300));
  List<String> result = [emptyString];
  await Get.dialog(
    AlertDialog(
      insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 20),
      title: Text(label, textAlign: TextAlign.center),
      content: PhotoCamera(
        cameras: cameras,
        label: label,
        direction: getCameraIndex(cameras, direction),
        maxSize: maxSize,
        quality: quality,
        height: height,
        width: width,
        imageUrl: result,
      ),
    ),
  );
  return result[0];
} // end of acquireCamera

int getCameraIndex(List<CameraDescription> cameras, String lensFacing) {
  int result = 0;
  bool found = false;
  CameraLensDirection direction =
      lensFacing.toString().trim().toLowerCase() == 'front'
      ? CameraLensDirection.front
      : CameraLensDirection.back;
  for (int i = 0; i < cameras.length && !found; i++) {
    if (cameras[i].lensDirection == direction) {
      result = i;
      found = true;
    } // end if cameras[i]
  } // end for i
  return result;
} //getCameraIndex
