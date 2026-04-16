// FILE: otq_get_images_controller.dart

import 'package:get/get.dart';
import '../global2.dart'; // For txfController
import '../../init_values.dart';
import '../global.dart'; // For processData

class OtqGetImagesController extends GetxController {
  // --- STATE VARIABLES ---
  final RxList<String> imageUrls = <String>[].obs;
  final RxBool isEnabled = true.obs;

  // --- PROPERTIES ---
  late final String scrName;
  late final dynamic component;
  late final int? position;

  // --- ADD THIS FLAG ---
  bool _isInitialized = false;

  // --- INITIALIZATION ---
  void init(String screenName, dynamic comp) {
    // --- ADD THIS CHECK ---
    // If we've already run this, do nothing.
    if (_isInitialized) return;

    scrName = screenName;
    component = comp;
    position = component['position'] as int?;

    // Set initial images from 'currentValue'
    final List<String> currentUrlList =
        component['currentValue']?.toString().trim().isNotEmpty ?? false
            ? component['currentValue'].toString().trim().split('_u2605_')
            : [];

    for (String url in currentUrlList) {
      if (url.trim().isNotEmpty) {
        imageUrls.add(url);
      }
    }

    // --- SET FLAG TO TRUE AT THE END ---
    _isInitialized = true;
  }

  // --- ACTIONS (No changes needed here) ---
  void addImage(String url) {
    if (url.isNotEmpty) {
      imageUrls.add(url);
      _updateTxfController();
    }
  }

  void deleteImage(String url) {
    imageUrls.remove(url);
    _updateTxfController();
  }

  // --- PRIVATE HELPERS (No changes needed here) ---
  void _updateTxfController() {
    if (position != null) {
      try {
        final String urlOutput = processData(imageUrls);
        txfControllerCheck(scrName, position);
        final controller = txfController[scrName]![position]!;
        controller.controller.text = urlOutput;
        controller.finalData = urlOutput;
      } catch (e) {
        errorReport(e);
      }
    }
  }
}
