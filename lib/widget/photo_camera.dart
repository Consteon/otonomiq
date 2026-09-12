import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../global.dart';
import '../theme_tokens.dart';
import 'ocr_capture_support.dart'; // ocrGuideRect -- shared geometry, see OcrGuidePainter

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

/// Where the v6 selfie oval sits inside [box], given the screen's safe areas.
///
/// v6 sizes the oval from the SCREEN, not from a fixed dp box: 77 % of the
/// width (300 dp on a 390 dp phone), clamped to 280..340 dp so a narrow phone
/// still frames a face and a wide one does not turn the oval into a portal.
/// Height is 1.27x the width -- room for the face AND the shoulders, which on
/// an attendance selfie are evidence in their own right: the uniform and the
/// post behind it are what show the guard was really there.
///
/// It sits 32 dp under the 56 dp bar. On a shorter screen that gap collapses
/// first and only then does the oval shrink, keeping the 1:1.27 ratio, so the
/// hint under it clears the bottom sheet on every phone shape this app meets.
///
/// The oval never goes below 170 dp wide. On a screen too short to hold even
/// that AND the furniture (roughly under 500 dp tall) the floor wins and the
/// hint is what gets squeezed -- an oval too small to frame anything guides
/// nothing, so it is the last thing to give.
///
/// Sibling of `scannerFrameRect` in `ftz_scanner_screen.dart`, deliberately not
/// merged with it: the QR frame is a square that collapses its gap FIRST, and
/// the two blocks it has to clear are different heights.
Rect selfieOvalRect({
  required Size box,
  required double topInset,
  required double bottomInset,
}) {
  const double bar = 56; // camera top bar
  const double gapMax = 32; // v6: oval sits 32 dp below the bar
  const double hintBlock = 100; // 28 dp gap + a two-line hint
  const double sheetBlock = 120; // grab + the 72 dp shutter row + padding
  const double share = 0.77; // of the screen width
  const double wMin = 280;
  const double wMax = 340;
  const double ratio = 1.27; // height / width
  const double floor = 170; // last resort on a very short screen
  const double margin = 8; // so the ring is never clipped by the edge

  final double fixed = topInset + bar + hintBlock + sheetBlock + bottomInset;
  double w = (box.width * share).clamp(wMin, wMax).toDouble();
  w = math.min(w, box.width - margin * 2);
  if (w < floor) w = floor;
  double h = w * ratio;
  double room = box.height - fixed - h;
  if (room < 0) {
    h = math.max(floor * ratio, h + room);
    w = h / ratio;
    room = box.height - fixed - h;
  }
  final double gap = room > 0 ? math.min(gapMax, room) : 0;
  return Rect.fromLTWH(
    math.max(0, (box.width - w) / 2),
    topInset + bar + gap,
    w,
    h,
  );
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

  /// Capture resolution. DEFAULT `ResolutionPreset.medium` -- every existing
  /// caller keeps the exact behaviour it has today (720x480 camerax /
  /// 480x360 avfoundation). OCR_CAPTURE passes `high` (1280x720) because
  /// `medium` makes a 0.35 MP frame that no OCR can read reliably.
  final ResolutionPreset? preset;

  /// Aspect ratio of an optional centred guide box drawn OVER the preview
  /// (`"4:1"` -> 4.0). null = no overlay = today's behaviour.
  final double? guideRatio;

  /// `v6` (trimmed, case-folded) selects the Vertika v6 selfie screen: a
  /// full-screen camera with an oval face frame, labelled controls and an
  /// explicit review step. Anything else -- absent, blank, `v7` -- keeps the
  /// classic four-icon tree byte for byte.
  final String variant;

  /// v6 bar title, e.g. `"Absen Masuk · Selfie"`. Blank falls back to [label].
  /// The SUBTITLE is not a parameter: it is a function of screen state
  /// (`Ambil foto wajah` -> `Periksa foto`), so the screen owns it.
  final String barTitle;

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
    this.preset,
    this.guideRatio,
    this.variant = '',
    this.barTitle = '',
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

  /// Bumped on every shutter press and on every v6 "Ulangi".
  ///
  /// ★ The bake in [_finalizeCapture] runs BEHIND the preview, so on the v6
  /// screen a retake can start while the discarded shot is still being
  /// watermarked. Without this token the late bake would finish last and point
  /// [currentImage] back at the photo the user just threw away -- and "Gunakan
  /// foto" would send it. The classic tree has no retake, so there the token
  /// never changes mid-flight and nothing about it behaves differently.
  int _shotId = 0;

  bool get _isV6 => widget.variant.trim().toLowerCase() == 'v6';

  /// The lens actually selected, read from the camera list rather than assumed.
  /// The classic tree hardcodes "index 1 == front", which is only true on a
  /// two-camera phone whose list happens to be ordered back-then-front.
  bool get _isFront =>
      selectedCamera >= 0 &&
      selectedCamera < widget.cameras.length &&
      widget.cameras[selectedCamera].lensDirection == CameraLensDirection.front;

  /// v6 collapses the classic four-mode flash cycle to one toggle: index 1
  /// (`FlashMode.always`) on, index 3 (`FlashMode.off`) off. Reusing
  /// [flashIndex] rather than adding a second source of truth keeps the
  /// existing "restore flash after the shot" path correct for both trees.
  bool get _v6FlashOn => flashIndex == 1;

  /// White overlay held over the preview while the front camera fires: that
  /// lens has no flash, so the screen itself is the light.
  // ponytail: uses whatever brightness the phone is already at; raising it
  // needs a plugin (screen_brightness) for maybe one stop at a dark post.
  bool _screenFlash = false;
  List<IconData> flashIcons = [
    Icons.flash_auto_rounded,
    Icons.flash_on_rounded,
    Icons.lightbulb,
    Icons.flash_off_rounded,
  ];
  List<File> capturedImages = [];
  File? currentImage;

  /// A controller that reports its own death.
  ///
  /// ★★★ The camera can fail AFTER `initialize()` has already succeeded.
  /// `initializeCamera` binds the use cases (`bindToLifecycle`) and returns —
  /// it does NOT wait for the physical camera to open. CameraX reports the real
  /// failure later on `onCameraError`, which the plugin lands in
  /// `value.errorDescription` **without clearing `value.isInitialized`**
  /// (camera-0.12.0+1 `camera_controller.dart:359-365`). So a guard that only
  /// asks `isInitialized` happily renders `CameraPreview` on a dead camera: a
  /// texture that never receives a frame — the black preview.
  ///
  /// Nothing rebuilt on that either: only `onNewCameraSelected` attached a
  /// listener, and the open path never goes through it.
  CameraController _newController(int cameraIndex) {
    final CameraController c = CameraController(
      widget.cameras[cameraIndex],
      widget.preset ?? ResolutionPreset.medium,
    );
    c.addListener(() {
      if (!mounted || !identical(c, controller)) return;
      if (c.value.hasError && !_errorReported) {
        _errorReported = true;
        errorReport(
          'camera died after initialize: ${c.value.errorDescription}',
        );
      }
      setState(() {});
    });
    return c;
  }

  /// One report per open, not one per `value` change.
  bool _errorReported = false;

  /// The controller initialised, then the camera died under it.
  bool get _cameraDead {
    final CameraController? c = controller;
    return c != null && !identical(c, _disposedController) && c.value.hasError;
  }

  Future<void> _doInitializeCamera(int cameraIndex, int flashIndex) async {
    await _safeDisposeCamera(controller);
    controller = _newController(cameraIndex);

    // The previous camera owner (QR scanner via mobile_scanner) may still be
    // releasing the hardware, so initialize() fails and the preview shows blank
    // white. Retry a few times on a fresh controller with a short backoff
    // before giving up.
    const int maxAttempts = 3;
    for (int attempt = 0; ; attempt++) {
      try {
        // A SECOND way this never finishes: initialize() awaits
        // `initializeCompleter`, fed by onCameraInitialized. If CameraX never
        // gets far enough to emit it, the Future does not settle at all. That
        // is a different failure from the one _newController covers (a camera
        // that dies AFTER initialize succeeded), and it needs its own bound.
        // The first attempt gets the longer budget because a genuine recovery
        // from a just-released camera was logged taking ~4.2 s across nine
        // internal opens.
        await controller!.initialize().timeout(
          Duration(seconds: attempt == 0 ? 6 : 3),
          onTimeout: () => throw CameraException(
            'initializeTimeout',
            'camera did not open in time (attempt ${attempt + 1})',
          ),
        );
        break;
      } catch (e) {
        if (attempt >= maxAttempts - 1) {
          // ★★★ LET GO. Giving up used to leave the last controller bound, and
          // CameraX does not treat a failed open as final: it logs
          // "Failed to open camera CameraId-N after 21 attempts", then
          // "Restarting Camera2CameraController(CameraGraph-N)..." and starts
          // another 21-attempt cycle -- forever, while the user is already
          // looking at the empty state. On the device log that is one
          // CameraGraph churning through VirtualCamera-7..-14 with the Flutter
          // isolate idle in between. It keeps a client bound to a camera
          // service that is already refusing, so nothing can recover and the
          // NEXT screen inherits the wedge (QR black, then selfie black).
          // Unbinding is the only thing that stops the storm.
          await _safeDisposeCamera(controller);
          controller = null;
          // Always after the first frame — the dispose above already yielded.
          if (mounted) {
            setState(() {
              _initFailed = true;
              _initDenied = _isPermissionError(e);
            });
          }
          rethrow;
        }
        if (mounted) setState(() => _initAttempt = attempt + 1);
        await Future.delayed(const Duration(milliseconds: 400));
        // A controller whose initialize() just failed has no surface producer,
        // so a raw dispose() here would throw OUT of this catch block.
        await _safeDisposeCamera(controller);
        controller = _newController(cameraIndex);
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

  /// v6 only: the camera never opened, so the whole screen becomes an empty
  /// state rather than a black rectangle. Read by [_buildV6]; the classic tree
  /// never looks at it.
  bool _initFailed = false;

  /// Which empty state. A denied permission and a camera another process still
  /// holds look identical from here but need opposite advice — one is fixed in
  /// Settings, the other by waiting a moment and trying again.
  bool _initDenied = false;

  /// How many opens have already failed for this screen. v6 puts it under the
  /// spinner so a slow camera reads as "still trying", not as a dead screen.
  int _initAttempt = 0;

  static bool _isPermissionError(Object e) {
    if (e is! CameraException) return false;
    final String code = e.code.toLowerCase();
    return code.contains('accessdenied') || code.contains('restricted');
  }

  void initializeCamera(int cameraIndex, int flashIndex) {
    _initFailed = false;
    _initDenied = false;
    _initAttempt = 0;
    _errorReported = false;
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
      kIsWeb
          ? ResolutionPreset.max
          : (widget.preset ?? ResolutionPreset.medium),
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
    final int shot = _shotId;
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
        // A retake (or a newer shot) happened while this bake was running --
        // see [_shotId]. The file is still written, it is just not the one the
        // user is looking at, so it must not become `currentImage`.
        if (shot == _shotId) currentImage = File(imagePath);
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
    if (!_isV6) return _buildClassic(context);
    return _buildV6(context);
  }

  Widget _buildClassic(BuildContext context) {
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
                      controller!.value.isInitialized &&
                      // A camera that died after initialize() keeps
                      // isInitialized true — see _newController.
                      !controller!.value.hasError) {
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
                      child: widget.guideRatio == null
                          ? CameraPreview(controller!)
                          : Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                // The Stack's ONLY non-positioned child, so
                                // the Stack sizes to the preview and the
                                // Positioned.fill below maps 1:1 onto the
                                // frame the sensor is delivering.
                                CameraPreview(controller!),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: OcrGuidePainter(
                                        ratio: widget.guideRatio!,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                              _shotId++;
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

  // ── Vertika v6 selfie screen ────────────────────────────────────────────
  //
  // Same skeleton as the v6 QR camera (ftz_scanner_screen.dart): a bar over
  // the scrim, a frame, one live-region hint under it, and a white bottom
  // sheet holding every control. The differences are the ones the selfie needs
  // -- an oval instead of a square, a manual shutter, and an explicit review
  // step before the photo leaves the screen.

  Widget _buildV6(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    // The camera never opened. Replace the WHOLE screen -- a scrim, an oval
    // and a shutter over a blank rectangle explain nothing.
    if (_initFailed || _cameraDead) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: _v6CameraError(context),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final Rect oval = selfieOvalRect(
              box: Size(box.maxWidth, box.maxHeight),
              topInset: mq.padding.top,
              bottomInset: mq.padding.bottom,
            );
            return Stack(
              children: <Widget>[
                Positioned.fill(child: _v6Preview()),
                // The review photo goes UNDER the painter, so the two text
                // veils dim it exactly as they dim the live preview.
                if (gotPicture && currentImage != null) _v6Review(),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SelfieOvalPainter(
                        oval: oval,
                        barBottom: mq.padding.top + 56,
                        // On review the oval has done its job. The frame that
                        // gets sent is the full one, so it is shown whole.
                        showGuide: !gotPicture,
                      ),
                    ),
                  ),
                ),
                _v6Hint(oval),
                _v6Bar(mq.padding.top),
                _v6Sheet(mq.padding.bottom),
                // The front lens has no flash, so the screen is the light.
                if (_screenFlash)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: Colors.white),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _v6Preview() {
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (BuildContext context, AsyncSnapshot<void> snap) {
        // The classic tree spins forever here: _doInitializeCamera rethrows
        // after its retries (a denied permission never succeeds), the future
        // rejects, and `connectionState == done && !hasError` is never true.
        // `_initFailed` turns the whole screen into the empty state; this
        // branch only has to not draw a spinner underneath it.
        if (snap.hasError) return const ColoredBox(color: Colors.black);
        final CameraController? c = controller;
        if (snap.connectionState == ConnectionState.done &&
            c != null &&
            !identical(c, _disposedController) &&
            c.value.isInitialized &&
            !c.value.hasError &&
            c.value.aspectRatio > 0) {
          // CameraPreview is an AspectRatio, so inside a filled Stack it
          // letterboxes -- and the oval, placed against the SCREEN, would then
          // sit partly on a black bar. Scale to cover and clip the overflow.
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: 1000,
                height: 1000 * c.value.aspectRatio,
                child: CameraPreview(c),
              ),
            ),
          );
        }
        // Solid ground, not the live scrim: there is no preview behind this
        // yet, and white text on the 35 % scrim would be 2.23:1.
        return ColoredBox(
          color: const Color(0xFF0F172A),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _initAttempt == 0
                        ? 'Menyiapkan kamera…'
                        : 'Kamera masih dipakai proses lain, mencoba lagi…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The captured frame, WHOLE.
  ///
  /// The oval decides "sudah pas atau belum" while framing; it never crops.
  /// What gets uploaded is the full frame -- the uniform and the post around
  /// the face are half the evidence -- so showing an oval cut-out here would
  /// have the guard approve an image that is not the one that gets sent.
  Widget _v6Review() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Image.file(
          currentImage!,
          fit: BoxFit.cover,
          // The path can be gone from under us: _finalizeCapture swaps the
          // raw temp for the watermarked file and deletes the original.
          errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
              const ColoredBox(color: Colors.black26),
        ),
      ),
    );
  }

  Widget _v6Hint(Rect oval) {
    final String head;
    final String body;
    if (gotPicture) {
      head = 'Wajah terlihat jelas?';
      body = 'Gunakan foto ini, atau ulangi';
    } else if (_isFront) {
      head = 'Posisikan wajah di dalam bingkai';
      body = 'Lepas masker dan topi, hadapkan wajah ke kamera';
    } else {
      head = 'Kamera belakang aktif';
      body = 'Minta rekan mengambil foto, atau ketuk Balik kamera';
    }
    return Positioned(
      left: 24,
      right: 24,
      top: oval.bottom + 28,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                head,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  // 86% (v6's own value) measures 4.22:1 on the scrim over a
                  // fully-white scene, under the 4.5:1 a 14 dp line owes.
                  // 92% is 4.54:1 and is the same line to look at.
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _v6Bar(double topInset) {
    final String title = widget.barTitle.trim().isNotEmpty
        ? widget.barTitle.trim()
        : (widget.label ?? 'Camera');
    return Positioned(
      left: 0,
      right: 0,
      top: topInset,
      height: 56,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            height: 56,
            child: IconButton(
              tooltip: 'Tutup kamera',
              icon: const Icon(Icons.close, color: Colors.white),
              iconSize: 26,
              // Nothing is in flight that a pop would strand: the upload is
              // the caller's, and it only starts once "Gunakan foto" has
              // handed back a path. So close always just means cancel.
              onPressed: _accepting ? null : () => Get.back(),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  gotPicture ? 'Periksa foto' : 'Ambil foto wajah',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _v6Sheet(double bottomInset) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(16, 14, 16, 18 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: OtqPalette.v6DisabledFg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            if (gotPicture) _v6ReviewRow() else _v6ShutterRow(),
          ],
        ),
      ),
    );
  }

  Widget _v6ShutterRow() {
    final bool front = _isFront;
    return Row(
      children: <Widget>[
        Expanded(
          child: _v6SideButton(
            icon: _v6FlashOn ? Icons.flash_on : Icons.flash_off,
            // The front lens has no flash: what the button does there is
            // whiten the screen at the shutter, and the label says so.
            label: front
                ? (_v6FlashOn ? 'Kilat layar nyala' : 'Kilat layar')
                : (_v6FlashOn ? 'Kilat nyala' : 'Kilat'),
            on: _v6FlashOn,
            onTap: _processing ? null : _v6ToggleFlash,
          ),
        ),
        const SizedBox(width: 8),
        _v6Shutter(),
        const SizedBox(width: 8),
        Expanded(
          child: _v6SideButton(
            icon: Icons.flip_camera_ios,
            label: front ? 'Balik kamera' : 'Kamera belakang',
            on: !front,
            onTap: widget.cameras.length > 1 && !_processing && !tapDetector
                ? _v6Flip
                : null,
          ),
        ),
      ],
    );
  }

  Widget _v6Shutter() {
    final Color primary = Theme.of(context).primaryColor;
    final bool off = _processing;
    final Color ring = off ? OtqPalette.v6DisabledFg : primary;
    return Semantics(
      button: true,
      enabled: !off,
      label: 'Ambil foto',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: off ? null : _v6Capture,
          customBorder: const CircleBorder(),
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 4),
            ),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: off ? OtqPalette.v6DisabledFg : primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _v6ReviewRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _v6WideButton(
            label: 'Ulangi',
            icon: Icons.refresh,
            background: OtqPalette.v6Muted,
            foreground: OtqPalette.foreground,
            onTap: _accepting ? null : _v6Retake,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _v6WideButton(
            label: 'Gunakan foto',
            // The one filled accent element on the screen -- 6.94:1 against
            // v6OnAccent. White on this orange is 2.67:1 and never ships.
            background: OtqPalette.v6Accent,
            foreground: OtqPalette.v6OnAccent,
            busy: _accepting,
            onTap: _accepting ? null : _v6Accept,
          ),
        ),
      ],
    );
  }

  Widget _v6SideButton({
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback? onTap,
  }) {
    final Color primary = Theme.of(context).primaryColor;
    final bool off = onTap == null;
    final Color fg = off
        ? OtqPalette.v6DisabledFg
        : (on ? primary : OtqPalette.foreground);
    return Semantics(
      button: true,
      enabled: !off,
      toggled: on,
      child: Material(
        color: on ? primary.withValues(alpha: 0.10) : OtqPalette.v6Muted,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 56,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on ? primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _v6WideButton({
    required String label,
    required Color background,
    required Color foreground,
    IconData? icon,
    bool busy = false,
    required VoidCallback? onTap,
  }) {
    final bool off = onTap == null;
    final Color fg = off && !busy ? OtqPalette.v6DisabledFg : foreground;
    return Semantics(
      button: true,
      enabled: !off,
      child: Material(
        color: off && !busy ? OtqPalette.v6Muted : background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (icon != null)
                  Icon(icon, size: 20, color: fg),
                if (busy || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The camera never opened. Say which of the two things went wrong, because
  /// they need opposite advice, and offer the one action that fixes THAT one.
  ///
  /// A wedged camera -- another process still holding it, or the service in the
  /// error state camerax reports as `Unknown camera ID 0` -- is not a
  /// permission problem, and sending the guard to Settings for it would waste
  /// the walk. It usually clears on its own, so the CTA is simply to try again.
  Widget _v6CameraError(BuildContext context) {
    final bool denied = _initDenied;
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: OtqPalette.v6Muted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  denied
                      ? Icons.videocam_off_outlined
                      : Icons.no_photography_outlined,
                  size: 34,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                denied ? 'Kamera belum diizinkan' : 'Kamera tidak bisa dibuka',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: OtqPalette.foreground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Aplikasi butuh kamera untuk mengambil foto absensi. '
                          'Nyalakan izin Kamera di pengaturan, lalu buka lagi.'
                    // Not "another app is using it" -- the device log shows the
                    // camera SERVICE refusing this client
                    // (`Unknown camera ID`, `onError 4`), which a wait does not
                    // clear. Closing the app drops the client; that is the step
                    // that actually works, so it is the step we name.
                    : 'Coba lagi sekali. Kalau masih gagal, tutup aplikasi '
                          'sepenuhnya lalu buka lagi — kamera perangkat perlu '
                          'dilepas dulu.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                  color: OtqPalette.v6MutedFg,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OtqPalette.v6Accent,
                    foregroundColor: OtqPalette.v6OnAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: denied
                      ? () => openAppSettings()
                      : () => setState(
                          () => initializeCamera(selectedCamera, flashIndex),
                        ),
                  child: Text(
                    denied ? 'Buka pengaturan' : 'Coba lagi',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Get.back(),
                child: const Text(
                  'Kembali',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _v6ToggleFlash() {
    final bool next = !_v6FlashOn;
    setState(() => flashIndex = next ? 1 : 3);
    // Only the back lens has a real flash. Asking the front one for
    // FlashMode.always throws on some devices, and there is nothing to set:
    // the "flash" there is the white overlay _v6Capture holds up.
    if (!_isFront) {
      final CameraController? c = controller;
      if (c != null && !identical(c, _disposedController)) {
        safeUnawaited(
          c.setFlashMode(_flashModeFor(flashIndex)),
          'v6 selfie flash',
        );
      }
    }
  }

  void _v6Flip() {
    if (tapDetector) return;
    tapDetector = true;
    // getCameraIndex, not "0 or 1": the list is not guaranteed to be exactly
    // [back, front], and a phone with two back lenses makes the toggle land on
    // the wrong one.
    final int next = getCameraIndex(
      widget.cameras,
      _isFront ? 'back' : 'front',
    );
    setState(() {
      selectedCamera = next;
      initializeCamera(selectedCamera, flashIndex);
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      tapDetector = false; // wait until the camera is stable
    });
  }

  Future<void> _v6Capture() async {
    if (gotPicture || _processing) return;
    setState(() => _processing = true);
    try {
      await _initializeControllerFuture;
      if (_isFront && _v6FlashOn) {
        setState(() => _screenFlash = true);
        // Long enough for the panel to actually be white in the frame the
        // sensor grabs, short enough not to read as a freeze.
        await Future.delayed(const Duration(milliseconds: 300));
      }
      final XFile xFile = await controller!.takePicture();
      safeUnawaited(HapticFeedback.mediumImpact(), 'v6 selfie haptic');
      controller!.setFlashMode(_flashModeFor(flashIndex));
      final File rawFile = File(xFile.path);
      if (!mounted) return;
      setState(() {
        _shotId++;
        _screenFlash = false;
        currentImage = rawFile;
        gotPicture = true;
        _processing = false;
      });
      _finalizeFuture = _finalizeCapture(rawFile, xFile.path);
    } catch (e) {
      errorReport('capture error: $e');
      if (mounted) {
        setState(() {
          _screenFlash = false;
          _processing = false;
        });
      }
    }
  }

  void _v6Retake() {
    // Bumping the token here is what stops the discarded shot's bake from
    // finishing last and re-pointing currentImage at it -- see [_shotId].
    setState(() {
      _shotId++;
      gotPicture = false;
      currentImage = null;
      _finalizeFuture = null;
    });
  }

  Future<void> _v6Accept() async {
    if (!gotPicture || _accepting) return;
    final Future<void>? pending = _finalizeFuture;
    if (pending != null) {
      setState(() => _accepting = true);
      await pending; // never rejects — see _finalizeCapture
      if (!mounted) return;
      setState(() => _accepting = false);
    }
    final File? picked = currentImage;
    if (picked == null) return;
    inputPath = picked.path;
    widget.imageUrl[0] = picked.path;
    Get.back();
  }
}

/// [preset], [guideRatio], [variant] and [barTitle] are OPTIONAL and
/// default-off: a call site that passes none behaves EXACTLY as it did before
/// they existed.
Future<String> acquireCamera(
  List<CameraDescription> cameras,
  String label,
  String direction,
  int maxSize,
  int quality,
  double? height,
  double? width, {
  ResolutionPreset? preset,
  double? guideRatio,
  String variant = '',
  String barTitle = '',
}) async {
  // inputPath = emptyString;
  FocusManager.instance.primaryFocus?.unfocus();
  await Future.delayed(const Duration(milliseconds: 300));
  List<String> result = [emptyString];
  final PhotoCamera camera = PhotoCamera(
    preset: preset,
    guideRatio: guideRatio,
    cameras: cameras,
    label: label,
    direction: getCameraIndex(cameras, direction),
    maxSize: maxSize,
    quality: quality,
    height: height,
    width: width,
    imageUrl: result,
    variant: variant,
    barTitle: barTitle,
  );
  if (variant.trim().toLowerCase() == 'v6') {
    // A full-screen route, not a dialog: v6's first finding about this screen
    // is that the sheet leaves the page behind it visible with a generic
    // "Camera" title and no idea which action it belongs to. `_buildV6`
    // returns its own Scaffold, and Get.back() pops it exactly as the dialog
    // path pops.
    await Get.to<void>(() => camera);
  } else {
    await Get.dialog(
      AlertDialog(
        insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 20),
        title: Text(label, textAlign: TextAlign.center),
        content: camera,
      ),
    );
  }
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

/// The centred guide box drawn over the camera preview.
///
/// Geometry comes from the SAME [ocrGuideRect] the ML Kit crop uses, called with
/// `pad: 0` -- the agent sees the tight box, the crop takes 8% slack on each
/// side. One function, two consumers: the drawn box and the cropped box can
/// never drift apart.
class OcrGuidePainter extends CustomPainter {
  const OcrGuidePainter({required this.ratio});

  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final List<int> r = ocrGuideRect(
      size.width.round(),
      size.height.round(),
      ratio,
      pad: 0,
    );
    if (r.length != 4) return;
    final Rect box = Rect.fromLTWH(
      r[0].toDouble(),
      r[1].toDouble(),
      r[2].toDouble(),
      r[3].toDouble(),
    );
    // Scrim everything outside the box so the eye lands inside it.
    final Path scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(RRect.fromRectAndRadius(box, const Radius.circular(6))),
    );
    canvas.drawPath(scrim, Paint()..color = const Color(0x66000000));
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF3B82F6),
    );
  }

  @override
  bool shouldRepaint(OcrGuidePainter old) => old.ratio != ratio;
}

/// The v6 selfie frame.
///
/// Three layers, one painter, so nothing can drift:
///
///  1. A 35 % dim outside [oval]. NOT the QR screen's 62 %: on an attendance
///     selfie what surrounds the face is evidence -- the uniform, the gate, the
///     post -- so the oval has to read as a guide, not a mask.
///  2. A stronger veil behind the bar and behind the hint, and only there. 35 %
///     alone puts white text at 2.23:1 over a bright scene, which clears
///     nothing; [_veil] on top of the base composites to 62 % in those two
///     bands, which is 5.02:1 for the title and 4.54:1 for the 92 % body -- the
///     same numbers the v6 QR screen measures. Neither band reaches the oval,
///     so the shoulders and the background stay at 35 %.
///  3. The ring, white over a dark halo. A bare white line on a 35 % scrim over
///     a white wall is 2.23:1, under the 3:1 a graphical guide owes; the halo
///     makes the pair 3.99:1 against each other whatever is behind them.
///
/// [showGuide] is false on the review step: the photo that gets sent is the
/// FULL frame, so dimming it or ringing it there would misrepresent it. Only
/// the two text veils stay.
class _SelfieOvalPainter extends CustomPainter {
  const _SelfieOvalPainter({
    required this.oval,
    required this.barBottom,
    required this.showGuide,
  });

  /// Where the oval sits -- also where both veils stop.
  final Rect oval;

  /// Bottom of the 56 dp bar; the top veil holds full strength down to here.
  final double barBottom;

  /// Capture step: dim + ring. Review step: text veils only.
  final bool showGuide;

  static const Color _ink = Color(0xFF0F172A);
  static const double _base = 0.35;
  static const double _veil = 0.415; // 0.35 then 0.415 composites to 0.62

  @override
  void paint(Canvas canvas, Size size) {
    if (showGuide) {
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addOval(oval),
        ),
        Paint()..color = _ink.withValues(alpha: _base),
      );
    }
    _band(
      canvas,
      Rect.fromLTRB(
        0,
        0,
        size.width,
        math.max(0, math.min(size.height, oval.top)),
      ),
      hold: barBottom,
      fromTop: true,
    );
    _band(
      canvas,
      Rect.fromLTRB(
        0,
        math.max(0, math.min(size.height, oval.bottom)),
        size.width,
        size.height,
      ),
      hold: 28, // the gap v6 puts between the oval and the hint
      fromTop: false,
    );
    if (!showGuide) return;
    // Halo first, 6 dp on the same centre line as the 3 dp ring, so 1.5 dp of
    // it shows on each side.
    canvas.drawOval(
      oval.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = _ink.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      oval.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  /// One text veil: full strength for [hold] dp measured from the band's own
  /// edge, then fading to nothing by the time it reaches the oval.
  void _band(
    Canvas canvas,
    Rect band, {
    required double hold,
    required bool fromTop,
  }) {
    if (band.height <= 0) return;
    final double stop = (hold / band.height).clamp(0.0, 1.0);
    final Color solid = _ink.withValues(alpha: _veil);
    // Transparent INK, not Colors.transparent: a gradient to transparent BLACK
    // fades through grey and leaves a dirty edge over a bright scene.
    const Color clear = Color(0x000F172A);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: fromTop
              ? <Color>[solid, solid, clear]
              : <Color>[clear, solid, solid],
          stops: <double>[0, stop, 1],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(_SelfieOvalPainter old) =>
      old.oval != oval ||
      old.barBottom != barBottom ||
      old.showGuide != showGuide;
}
