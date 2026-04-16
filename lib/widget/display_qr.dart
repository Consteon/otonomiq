import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class DisplayQR extends StatelessWidget {
  final String data;
  final int size;

  const DisplayQR({super.key, required this.data, required this.size});

  @override
  Widget build(BuildContext context) {
    int dataLength = data.length;
    int qrVersion = 40;
    if (dataLength < 10) {
      qrVersion = 1;
    } else if (dataLength < 20) {
      qrVersion = 2;
    } else if (dataLength < 35) {
      qrVersion = 3;
    } else if (dataLength < 50) {
      qrVersion = 4;
    } else if (dataLength < 64) {
      qrVersion = 5;
    } else if (dataLength < 84) {
      qrVersion = 6;
    } else if (dataLength < 93) {
      qrVersion = 7;
    } else if (dataLength < 122) {
      qrVersion = 8;
    } else if (dataLength < 143) {
      qrVersion = 9;
    } else if (dataLength < 174) {
      qrVersion = 10;
    } else if (dataLength < 200) {
      qrVersion = 11;
    } else if (dataLength < 227) {
      qrVersion = 12;
    } else if (dataLength < 259) {
      qrVersion = 13;
    } else if (dataLength < 283) {
      qrVersion = 14;
    } else if (dataLength < 321) {
      qrVersion = 15;
    } else if (dataLength < 365) {
      qrVersion = 16;
    } else if (dataLength < 408) {
      qrVersion = 17;
    } else if (dataLength < 452) {
      qrVersion = 18;
    } else if (dataLength < 493) {
      qrVersion = 19;
    } else if (dataLength < 557) {
      qrVersion = 20;
    } else if (dataLength < 587) {
      qrVersion = 21;
    } else if (dataLength < 640) {
      qrVersion = 22;
    } else {
      qrVersion = 32;
    }
    return QrImageView(
      data: data,
      size: 0.0 + size,
      version: qrVersion,
//    version: 5,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }
}
