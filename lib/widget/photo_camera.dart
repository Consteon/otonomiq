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
  final img.Image? decoded = img.decodeImage(a.bytes);
  if (decoded == null) return a.bytes;
  img.Image image = decoded;
  try {
    image = img.bakeOrientation(image);
  } catch (_) {}
  img.Image resizedImage = image;
  try {
    if (image.height > image.width) {
      resizedImage = img.copyResize(image, height: a.maxSize);
    } else {
      resizedImage = img.copyResize(image, width: a.maxSize);
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

  @override
  void dispose() {
    // camera plugin's dispose() rejects with IllegalStateException
    // (releaseFlutterSurfaceTexture ... not yet initialized) when the screen is
    // closed while initialize() is still in flight — the preview surface
    // producer was never built. Unawaited in a sync dispose(), the rejected
    // Future is otherwise unhandled → platformDispatcher → fatal. Swallow it;
    // there is nothing to recover here.
    controller?.dispose().catchError((e) {
      devPrint('camera dispose (uninitialized?): $e');
    });
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
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      onNewCameraSelected(cameraController.description);
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
  bool _finalizing = false; // preview shown; watermark still writing in bg
  List<IconData> flashIcons = [
    Icons.flash_auto_rounded,
    Icons.flash_on_rounded,
    Icons.lightbulb,
    Icons.flash_off_rounded,
  ];
  List<File> capturedImages = [];
  File? currentImage;

  Future<void> _doInitializeCamera(int cameraIndex, int flashIndex) async {
    await controller?.dispose();
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
        await controller?.dispose();
        controller = CameraController(
          widget.cameras[cameraIndex],
          ResolutionPreset.medium,
        );
      }
    }
    await Future.delayed(const Duration(milliseconds: 500));
    controller!.setFlashMode(_flashModeFor(flashIndex));
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
      await oldController.dispose();
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
                      controller!.value.isInitialized) {
                    // Only show the preview when the camera is really live —
                    // rendering CameraPreview on a failed/half-initialized
                    // controller is exactly what produced the blank white frame.
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
                          if (gotPicture || _processing || _finalizing) return;
                          setState(() => _processing = true);
                          try {
                            await _initializeControllerFuture;
                            final xFile = await controller!.takePicture();
                            // restore flash for the next shot
                            controller!.setFlashMode(_flashModeFor(flashIndex));

                            // Show the just-captured frame IMMEDIATELY from the
                            // raw file (native codec = instant). The multi-second
                            // wait was the pure-Dart decode/resize/watermark
                            // pipeline sitting BETWEEN the shutter and the
                            // preview; it now runs AFTER, in the background, then
                            // swaps in the watermarked file. Accept stays disabled
                            // (_finalizing) until that swap, so the saved file is
                            // always the watermarked one.
                            final File rawFile = File(xFile.path);
                            setState(() {
                              currentImage = rawFile;
                              gotPicture = true;
                              _processing = false;
                              _finalizing = true;
                            });

                            final String imagePath =
                                "${xFile.path.split("/CAP")[0]}/$localImageArtifact${globalRandom.nextInt(999999999)}.jpg";
                            final String formattedDateTime = DateFormat(
                              dateTimeFormat,
                            ).format(DateTime.now());
                            final Uint8List rawBytes = await rawFile
                                .readAsBytes();
                            Uint8List watermarkedImage;
                            try {
                              // A stalled / OOM-killed isolate on low-RAM
                              // devices decoding the full-res capture never
                              // settles — the await would hang with _finalizing
                              // stuck true, permanently disabling Accept ("foto
                              // tidak berhasil, tanpa hasil"). Cap it and fall
                              // back to the raw (un-watermarked) bytes so the
                              // capture always completes.
                              // ponytail: 12s cap; move to a scaled-decode if
                              // watermarking full-res is measurably too slow.
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
                              await File(
                                imagePath,
                              ).writeAsBytes(watermarkedImage);
                              wrote = true;
                            } catch (e) {
                              errorReport('write captured image error: $e');
                            }
                            if (!mounted) return;
                            setState(() {
                              // write failed -> keep the valid raw file rather
                              // than pointing at a missing watermarked path.
                              if (wrote) currentImage = File(imagePath);
                              _finalizing = false;
                            });
                            // drop the raw temp only once the watermarked file
                            // is safely written and now the shown image.
                            if (wrote) {
                              try {
                                await rawFile.delete();
                              } catch (e) {
                                devPrint('delete temp capture error: $e');
                              }
                            }
                          } catch (e) {
                            errorReport('capture error: $e');
                            if (mounted) {
                              setState(() {
                                _processing = false;
                                _finalizing = false;
                              });
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
                        onPressed: () {
                          if (gotPicture && !_finalizing) {
                            inputPath = currentImage!.path;
                            widget.imageUrl[0] = currentImage!.path;
                            Get.back();
                            //Navigator.of(context).pop();
                          }
                        },
                        icon: Icon(
                          Icons.check_circle,
                          color: !gotPicture || _finalizing
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
        if (_processing)
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
