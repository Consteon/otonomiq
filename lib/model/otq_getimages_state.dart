import 'package:flutter/material.dart';

class OtqGetImagesStateObject extends ChangeNotifier {
  // modify this properties, to control the widget
  final List<Widget> _imageListNotifier = [];
  final List<String> _urlListNotifier = [];
  bool _changeNotifier = false;

  List<Widget> get imageList => _imageListNotifier;
  List<String> get urlList => _urlListNotifier;
  bool get changeNotifier => _changeNotifier;

  @override
  void dispose() {
    // Cancel any subscriptions or close resources here
    super.dispose(); // Call dispose on parent class
  } // end of dispose

  void addImage(Widget newWidget, String newUrl) {
    _imageListNotifier.add(newWidget);
    _urlListNotifier.add(newUrl);
    _changeNotifier = !_changeNotifier;
    notifyListeners(); // Notify listeners of the change
  } // end of addImageList

  void deleteImageAt(int index) {
    _imageListNotifier.removeAt(index);
    _urlListNotifier.removeAt(index);
    _changeNotifier = !_changeNotifier;
    notifyListeners(); // Notify listeners of the change
  } // end of deleteImageWidget

  void deleteAllImages() {
    _imageListNotifier.length = 0;
    _urlListNotifier.length = 0;
    // _imageListNotifier.clear();
    // _urlListNotifier.clear();
    _changeNotifier = !_changeNotifier;
    notifyListeners(); // Notify listeners of the change
  }
} // end of OtqGetImagesStateObject
