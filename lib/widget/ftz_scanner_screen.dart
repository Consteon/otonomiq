import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A screen that displays a camera view for scanning QR codes.
class FtzScannerScreen extends StatefulWidget {
  // NEW: Parameter for the AppBar title.
  final String title;

  // UPDATED: The initial camera is now a String ('front' or 'back').
  final String camera;

  const FtzScannerScreen({
    super.key,
    required this.title,
    this.camera = 'back',
  });

  @override
  State<FtzScannerScreen> createState() => _FtzScannerScreenState();
}

class _FtzScannerScreenState extends State<FtzScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    // UPDATED: Logic to convert the 'cameraSide' string to a CameraFacing enum.
    facing: widget.camera == 'front' ? CameraFacing.front : CameraFacing.back,
  );
  bool _isProcessing = false;

  // Manually manage the torch state
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    // mobile_scanner only self-manages the app lifecycle when it OWNS the
    // controller (see its _initializeController: addObserver runs only when
    // widget.controller == null). We pass our own controller, so we must
    // restart/stop the camera on resume/inactive here — otherwise the preview
    // stays blank white after a permission dialog or app background/foreground.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
        break;
      case AppLifecycleState.inactive:
        unawaited(_controller.stop());
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // UPDATED: Using the 'title' parameter from the widget.
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_isProcessing) return;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? qrResult = barcodes.first.rawValue;
                if (qrResult != null && qrResult.isNotEmpty) {
                  setState(() {
                    _isProcessing = true;
                  });
                  Navigator.of(context).pop(qrResult);
                }
              }
            },
          ),
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withAlpha(128),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 250,
                    width: 250,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.only(top: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    iconSize: 32.0,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                    ),
                    onPressed: () => _controller.switchCamera(),
                    iconSize: 32.0,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.bolt,
                      color: _isTorchOn ? Colors.amber : Colors.white,
                    ),
                    onPressed: () {
                      _controller.toggleTorch();
                      setState(() {
                        _isTorchOn = !_isTorchOn;
                      });
                    },
                    iconSize: 32.0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }
}
