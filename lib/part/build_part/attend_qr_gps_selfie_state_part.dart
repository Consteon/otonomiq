// ios
// HH 01 Oct 2024 13:44 +08:00
part of '../../widget/attendance_qr_selfie_gps_verify.dart';

extension TakeQr on AttendQrGpsSelfieState {
  Future<String?> attendanceTakeQR(
      String label, String scrName, dynamic component, String caller) async {
    // by AI :String qrResult = empty;
    try {
      // dynamic scanResult = await BarcodeScanner.scan();
      // by AI : dynamic scanResult = await BarcodeScanner.scan(
      //   options: const ScanOptions(
      //     useCamera: 0,
      //   ),
      // );
      final qrResult = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => FtzScannerScreen(title: label, camera: 'back'),
        ),
      ) ;
      // qrResult = scanResult.rawContent ?? empty;
      // qrResult = qrResult.isEmpty ? empty : qrResult;
      return qrResult ?? empty;
    } catch (e) {
      return empty;
    }
    // return qrResult;
  } // end of takeQR
} // end of extension
