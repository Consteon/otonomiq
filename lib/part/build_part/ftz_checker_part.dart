// ios
// HH 01 Oct 2024 13:44 +08:00
part of '../../widget/ftz_checker.dart';

extension CTakeQr on FtzCheckerState {
  Future<String?> checkerTakeQR(
    String label,
    String scrName,
    var component,
    String caller,
    String lens,
  ) async {
    // final camera = lens.toLowerCase() == 'front' ? CameraFacing.front : CameraFacing.back;
    // String qrResult = empty;
    // int cam = -1;
    // if (lens == 'front') {
    //   cam = 1;
    // } else if (lens == 'back') {
    //   cam = 0;
    // }
    try {
      // dynamic scanResult = await BarcodeScanner.scan(
      //   options: ScanOptions(
      //     useCamera: cam,
      //   ),
      // );
      // Settle so a just-closed selfie camera (camera plugin) releases the
      // hardware before the scanner (mobile_scanner) opens — otherwise the
      // scanner preview can come up blank on the multiple-scan handoff.
      await Future.delayed(const Duration(milliseconds: 350));
      final qrResult = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) =>
              FtzScannerScreen(title: label, camera: lens.toLowerCase()),
        ),
      );
      return qrResult ?? empty;
      // qrResult = scanResult.rawContent ?? empty;
      // qrResult = qrResult.isEmpty ? empty : qrResult;
    } catch (e) {
      // qrResult = empty;
      return empty;
    }
  } // end of takeQR
} // end of extension
