// ios
// HH 01 Oct 2024 13:44 +08:00
part of '../../widget/otq_txf.dart';

Future<String?> takeQR(BuildContext context, String label, String scrName,
    var component, String caller) async {
  // String qrResult= empty;
  try {
    // dynamic scanResult = await BarcodeScanner.scan();
    // dynamic scanResult = await BarcodeScanner.scan(
    //   options: const ScanOptions(
    //     useCamera: 0,
    //   ),
    // );
    final qrResult = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => FtzScannerScreen(title: label, camera: 'back'),
      ),
    );
    return qrResult ?? empty;
    // qrResult = scanResult.rawContent ?? empty;
    // qrResult = qrResult.isEmpty ? empty : qrResult;
  } catch (e) {
    return empty;
  }
  // return qrResult;
} // end of takeQR