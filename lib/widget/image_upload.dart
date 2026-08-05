import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../bloc_timer/timer_bloc.dart';
import '../bloc_timer/timer_event.dart';
import '../firestore_repository/firestore_generic_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../model/input_controller.dart';
import '../redux/screen_transaction.dart';

class ImageUpload extends StatefulWidget {
  const ImageUpload({
    required Key key,
    required this.component,
    required this.scrName,
  }) : super(key: key);
  final String scrName;
  final dynamic component;

  @override
  ImageUploadState createState() => ImageUploadState();
}

class ImageUploadState extends State<ImageUpload> {
  File? _imageFile;
  final _picker = ImagePicker();
  double width = 540, height = 540;
  String ext = 'jpg';
  int quality = 80;
  late String filename;

  @override
  Widget build(BuildContext context) {
    switch (widget.component['imageType']) {
      case 1:
        width = 540;
        height = 540;
        ext = 'jpg';
        quality = 80;
        break;

      case 2: // more than 12mp
        width = 4096;
        height = 4096;
        ext = 'jpg';
        quality = 80;
        break;

      default:
        width = 540;
        height = 540;
        ext = 'jpg';
        quality = 80;
    }
    filename = "${widget.component['filename']}.$ext";
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        OverflowBar(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.photo_camera),
              onPressed: () async =>
                  await _pickImageFromCamera(width, height, quality),
              tooltip: 'Dari kamera',
            ),
            IconButton(
              icon: const Icon(Icons.photo),
              onPressed: () async =>
                  await _pickImageFromGallery(width, height, quality),
              tooltip: 'Ambil dari gallery',
            ),
            IconButton(
              icon: const Icon(Icons.file_upload),
              onPressed: () async {
                _saveFile(ext, widget.component, widget.scrName, widget.key!);
                //gotoRoute(widget.component['route']);
              },
              tooltip: 'Upload',
            ),
          ],
        ),
        _imageFile == null
            ? const Placeholder()
            : Image.file(
                _imageFile!,
                // picked file lives in /cache; it can vanish before the async
                // load lands → PathNotFoundException outside any try/catch
                errorBuilder: (_, _, _) => const Placeholder(),
              ),
      ],
    );
  }

  void saveData(String scrName, String locString) {
    TimerBloc timerBloc = transactionStore.state.screenTx['#TIMER_BLOC'];
    var route = widget.component['route'] ?? widget.scrName;
    rootThis.setState(() {
      rootThis.wait = true;
    });
    timerBloc.add(
      const Start(duration: 5),
    ); //  get timerBloc from transactionStore
    transactionStore.dispatch(
      UpdateScreenTxAction(
        ScreenTransaction({
          '#NEXTROUTE': route,
          '#TIMER_CONTEXT': context,
          '#TIMER_DURATION': widget.component['delay'] ?? 5,
        }),
      ),
    ); // set state #NEXTROUTE route that will be displayed after waitScreen
    saveSend(null, scrName, widget.component, locString, defaultVid());
  } // end of saveData

  Future<void> _pickImageFromGallery(double w, double h, int q) async {
    final XFile pickedFile = (await _picker.pickImage(
      source: ImageSource.gallery,
      maxHeight: h,
      maxWidth: w,
      imageQuality: q,
    ))!;
    setState(() => _imageFile = File(pickedFile.path));
  } // end of _pickImageFromGallery

  Future<void> _pickImageFromCamera(double w, double h, int q) async {
    final XFile pickedFile = (await _picker.pickImage(
      source: ImageSource.camera,
      maxHeight: h,
      maxWidth: w,
      imageQuality: q,
    ))!;
    setState(() => _imageFile = File(pickedFile.path));
  } // end of _pickImageFromCamera

  Future<void> _saveFile(
    String ext,
    var component,
    String scrName,
    Key txfKey,
  ) async {
    if (await dataOk(context)) {
      actionLock('_saveFile IMG_UPLOAD');
      var state = transactionStore.state.screenTx;
      String vid = state['#VID'].toString();
      String downloadUrl = await uploadToCloudStorage(
        _imageFile!.path,
        "${component['folder']}/${component['filename']}.$ext",
      );

      // create parse diamond for parsing parameter.
      String content = 'IMG_UPLOAD'; //= position 1
      txfController[scrName]![1] = InputController(
        1,
        TextEditingController(text: content),
        content,
        content,
      );
      content = component['folder']; //= position 2
      txfController[scrName]![2] = InputController(
        2,
        TextEditingController(text: content),
        content,
        content,
      );
      content = '${component['filename']}.$ext'; //= position 3
      txfController[scrName]![3] = InputController(
        3,
        TextEditingController(text: content),
        content,
        content,
      );

      content = downloadUrl; //= position 4. image URL
      txfController[scrName]![4] = InputController(
        4,
        TextEditingController(text: content),
        content,
        content,
      );
      component['route'] = component['route'] ?? home; //= default route = Home
      saveData(scrName, separator[1] * 15); //= send record to event
      actionUnLock('_saveFile IMG_UPLOAD');
      String toGo = widget.component['route'] ?? home;
      routeStack.push(toGo);
      gotoRoute(toGo);
    }
  }
}
