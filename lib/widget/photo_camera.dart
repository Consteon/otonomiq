import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_watermark/image_watermark.dart';
import 'package:intl/intl.dart';

import '../global.dart';

String inputPath = emptyString; // temporary path variable

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
    initializeCamera(selectedCamera, flashIndex); //Initially selectedCamera = 0
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
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

    await controller!.initialize();
    await Future.delayed(const Duration(milliseconds: 500));
    switch (flashIndex) {
      case 0:
        controller!.setFlashMode(FlashMode.auto);
        break;
      case 1:
        controller!.setFlashMode(FlashMode.always);
        break;
      case 2:
        controller!.setFlashMode(FlashMode.torch);
        break;
      case 3:
        controller!.setFlashMode(FlashMode.off);
        break;
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
                      fit: BoxFit.cover),
                ),
              )
            : FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    // If the Future is complete, display the preview.
                    return Container(
                        //width: pictureWidth,
                        height: pictureHeight,
                        //width: MediaQuery.of(context).size.width * picFactor,
                        alignment: Alignment.center,
                        child: CameraPreview(controller!));
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
                          if (!gotPicture) {
                            await _initializeControllerFuture;
                            var xFile = await controller!.takePicture();
                            controller!.setFlashMode(FlashMode.off);
                            switch (flashIndex) {
                              case 0:
                                controller!.setFlashMode(FlashMode.auto);
                                break;

                              case 1:
                                controller!.setFlashMode(FlashMode.always);
                                break;

                              case 2:
                                controller!.setFlashMode(FlashMode.torch);
                                break;

                              case 3:
                                controller!.setFlashMode(FlashMode.off);
                                break;
                            } // end switch
                            String imagePath =
                                "${xFile.path.split("/CAP")[0]}/$localImageArtifact${globalRandom.nextInt(999999999).toString()}.jpg";
                            final now = DateTime.now();
                            final String formattedDateTime =
                                DateFormat(dateTimeFormat).format(now);
                            dynamic image = img.decodeImage(
                                File(xFile.path).readAsBytesSync());
                            try {
                              image = img.bakeOrientation(image!);
                            } catch (e) {
                              devPrint('orientation error: $e');
                            }
                            File(xFile.path).delete();
                            img.Image resizedImage = image;
                            try {
                              if (image.height > image.width) {
                                resizedImage = img.copyResize(image,
                                    height: widget.maxSize ?? 500);
                              } else {
                                resizedImage = img.copyResize(image,
                                    width: widget.maxSize ?? 500);
                              }
                            } catch (e) {
                              devPrint('resize error: $e');
                            }
                            final imageBytes = Uint8List.fromList(img.encodeJpg(
                                resizedImage,
                                quality: widget.quality ?? 80));
                            dynamic watermarkedImage = imageBytes;
                            try {
                              watermarkedImage =
                                  await ImageWatermark.addTextWatermark(
                                imgBytes: imageBytes,

                                ///image bytes
                                watermarkText: formattedDateTime,

                                ///watermark text
                                // color: const Color(0xffF08118),
                                color: const Color.fromARGB(150, 10, 10, 10),
                                // b, g, r
                                // color: Colors.black,
                                font: img.arial14,
                                dstX: 11,
                                dstY: 9,
                              );
                            } catch (e) {
                              devPrint('watermark error: $e');
                            }
                            try {
                              watermarkedImage =
                                  await ImageWatermark.addTextWatermark(
                                imgBytes: watermarkedImage,

                                ///image bytes
                                watermarkText: formattedDateTime,

                                ///watermark text
                                // color: const Color(0xffF08118),
                                // color: const Color.fromARGB(255, 10, 30, 180), // b, g, r
                                color: const Color.fromARGB(255, 24, 129, 240),
                                // b, g, r
                                // color: Colors.black,
                                font: img.arial14,
                                dstX: 10,
                                dstY: 8,
                              );
                            } catch (e) {
                              devPrint('watermark error: $e');
                            }
                            File(imagePath).writeAsBytesSync(watermarkedImage!);
                            setState(() {
                              // capturedImages.add(File(xFile.path));
                              if (currentImage != null) {
                                currentImage!.delete();
                              }
                              currentImage = File(imagePath);
                              // capturedImages.add(File(
                              //     '/data/user/0/com.example.camera_app/cache/a1.jpg'));
                              gotPicture = true;
                            });
                          }
                        },
                        icon: Icon(
                          Icons.camera, // camera
                          color: gotPicture
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
                            Future.delayed(const Duration(milliseconds: 1200),
                                () {
                              // wait until the camera is stable
                              tapDetector = false;
                            });
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
                          if (gotPicture) {
                            inputPath = currentImage!.path;
                            widget.imageUrl[0] = currentImage!.path;
                            Get.back();
                            //Navigator.of(context).pop();
                          }
                        },
                        icon: Icon(
                          Icons.check_circle,
                          color: !gotPicture
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
  await Get.dialog(AlertDialog(
    insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 20),
    title: Text(
      label,
      textAlign: TextAlign.center,
    ),
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
  ));
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
