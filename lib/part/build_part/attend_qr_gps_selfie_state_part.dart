// ios
// HH 01 Oct 2024 13:44 +08:00
part of '../../widget/attendance_qr_selfie_gps_verify.dart';

extension TakeQr on AttendQrGpsSelfieState {
  Future<String?> attendanceTakeQR(
    String label,
    String scrName,
    dynamic component,
    String caller,
  ) async {
    // by AI :String qrResult = empty;
    try {
      // dynamic scanResult = await BarcodeScanner.scan();
      // by AI : dynamic scanResult = await BarcodeScanner.scan(
      //   options: const ScanOptions(
      //     useCamera: 0,
      //   ),
      // );
      // Vertika v6 camera screen. `variant`/`blockTitle` are stamped onto this
      // component by the horizontal_icon v6 branch, so a block that never opts
      // in gets the classic screen with the same title it has today.
      final String variant = (component['variant'] ?? '').toString();
      final List methodText = diamondTextToList(
        (component['text'] ?? '').toString(),
      );
      final String barTitle = scannerBarTitle(
        (component['blockTitle'] ?? '').toString(),
        methodText.isEmpty ? '' : methodText[0].toString(),
        label,
      );
      final qrResult = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => FtzScannerScreen(
            title: barTitle,
            camera: 'back',
            variant: variant,
            // The sheet's own scanner title (text slot 26) becomes the second
            // line once the bar carries the action; blank when it IS the title.
            subtitle: barTitle == label.trim() ? '' : label,
          ),
        ),
      );
      // qrResult = scanResult.rawContent ?? empty;
      // qrResult = qrResult.isEmpty ? empty : qrResult;
      return qrResult ?? empty;
    } catch (e) {
      return empty;
    }
    // return qrResult;
  } // end of takeQR
} // end of extension
