import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/simple/get_state.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../init_values.dart';
import '../model/general_get_controller.dart';

class OtqGetImages2 extends StatefulWidget {
  const OtqGetImages2({
    required Key key,
    required this.wKey,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  }) : super(key: key);
  final Key wKey;
  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  OtqGetImages2State createState() => OtqGetImages2State();
}

class OtqGetImages2State extends State<OtqGetImages2>
    with AutomaticKeepAliveClientMixin<OtqGetImages2> {
  int maxImages = 99999;
  List<double> margin = [];
  double h = 0;
  double w = 0;
  late final int? _position;

  void buttonPressed(dynamic component, bool isEnabled) async {
    if (isEnabled) {
      late List<int> imgParameter;
      try {
        List<String> imgParStr = (component['imageParameter'] ?? "400,400,80")
            .toString()
            .split(separator[4]);
        imgParameter = [
          int.parse(imgParStr[0]),
          int.parse(imgParStr[1]),
          int.parse(imgParStr[2]),
        ];
      } catch (e) {
        imgParameter = [400, 400, 80];
      }

      final String source =
          component['source']?.toString().toLowerCase() ?? '';
      // maxSize collapses width/height into one dimension (the larger) so
      // image_picker preserves aspect ratio — matches the camera path behavior.
      final int maxSize =
          (imgParameter[0] > imgParameter[1]) ? imgParameter[0] : imgParameter[1];
      final String folderName = component['folder'] ?? 'default';
      final String fileNameBase = (component['filename'] ?? 'file') +
          '_' +
          const Uuid().v4().replaceAll('-', '').substring(2, 7);

      String imgUrl;

      if (source == 'gallery') {
        imgUrl = await getGalleryImage(
          folder: folderName,
          fileName: fileNameBase,
          maxSize: maxSize,
          quality: imgParameter[2],
        );
      } else {
        // Camera path (default / unknown source values).
        // Note: fileNameBase is computed above unconditionally; in camera mode
        // on a device with empty #CAMS, the UUID is generated and discarded.
        // This is harmless and keeps the code flat.
        final List<CameraDescription> cams = await ensureCams();
        if (cams.isEmpty) return;

        imgUrl = await getPhotoCameraImage(
          cams,
          component['label'] ?? 'Camera',
          (component['camera'] ?? 1) == 0 ? 'front' : 'back',
          maxSize,
          imgParameter[2],
          folderName,
          fileNameBase,
          h,
          w,
        );
      }

      if (!mounted) return;

      if (imgUrl != emptyImageUrl) {
        setState(() {
          GeneralGetXController.to.addWidget(
            widget.scrName,
            widget.component['position'],
            buildImageWidget(imgUrl, isEnabled),
            imgUrl,
          );
        });

        String urlOutput = processData(
          GeneralGetXController.to.getStringList(
            widget.scrName,
            widget.component['position'],
          ),
        );
        try {
          if (widget.component['position'] != null) {
            txfControllerCheck(widget.scrName, widget.component['position']);
            txfController[widget.scrName]![widget.component['position']]!
                    .controller
                    .text =
                urlOutput;
            txfController[widget.scrName]![widget.component['position']]!
                    .finalData =
                urlOutput;
          }
        } catch (e) {
          errorReport(e);
        }
      } //
    } else {
      setState(() {
        GeneralGetXController.to.redraw(
          widget.scrName,
          widget.component['position'],
        );
      });
    } // end if isEnabled
  } // end buttonPressed

  @override
  void initState() {
    super.initState();
    _position = widget.component['position'] as int?;

    if (widget.component['position'] != null &&
        widget.component['currentValue'] != null) {
      txfControllerCheck(widget.scrName, widget.component['position']);
      final bool initialIsEnabled =
          txfController[widget.scrName]![widget.component['position']]!
              .initialIsEnabled;

      List<String> currentUrlList =
          widget.component['currentValue'].toString().trim().isNotEmpty
          ? widget.component['currentValue'].toString().trim().split('_u2605_')
          : [];
      for (String url in currentUrlList) {
        if (url.trim().isNotEmpty) {
          GeneralGetXController.to.addWidget(
            widget.scrName,
            widget.component['position'],
            buildImageWidget(url, initialIsEnabled),
            url,
          );
        }
      }

      String urlOutput = getImageInitValue(widget.scrName, widget.component);
      try {
        if (widget.component['position'] != null) {
          txfControllerCheck(
            widget.scrName,
            widget.component['position'],
          ); // build txfController if necessary
          if (canInitializePage(widget.scrName)) {
            txfController[widget.scrName]![widget.component['position']]!
                    .controller
                    .text =
                urlOutput;
            txfController[widget.scrName]![widget.component['position']]!
                    .initialValue =
                urlOutput;
            txfController[widget.scrName]![widget.component['position']]!
                    .finalData =
                urlOutput;
          }
        }
      } catch (e) {
        errorReport(e);
      }
    }
    margin = marginArray(widget.component['margin']);
    try {
      maxImages = widget.component['max'] ?? 9999;
    } catch (e) {
      maxImages = 9999;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    h = MediaQuery.of(context).size.height;
    w = MediaQuery.of(context).size.width;

    if (_position == null) {
      return _buildContent(context, true);
    }

    return GetBuilder<WidgetUpdateController>(
      id: '${widget.scrName}-$_position',
      builder: (_) {
        txfControllerCheck(widget.scrName, _position);
        final controller = txfController[widget.scrName]![_position]!;
        final bool isEnabled = controller.isEnabled;
        return _buildContent(context, isEnabled);
      },
    );
  }

  Widget _buildContent(BuildContext context, bool isEnabled) {
    final imageItem = GeneralGetXController.to.getWidgetItem(
      widget.scrName,
      widget.component['position'],
    );
    final imageWidgets = imageItem?.widgetList ?? [];
    final imageUrls = imageItem?.stringList ?? [];

    final List<String> texts = diamondTextToList(
      widget.component['text']?.toString() ?? '',
    );
    final String source =
        widget.component['source']?.toString().toLowerCase() ?? '';
    final IconData sourceIcon = source == 'gallery'
        ? Icons.photo_library_outlined
        : Icons.camera_alt_outlined;
    final String emptyTitle = 'Belum ada foto';
    final String emptySubtitle = 'Ambil foto untuk melengkapi data';
    final String fotoLabel = texts.length > 2 ? texts[2] : 'foto';
    final String addLabel = texts.length > 3 ? texts[3] : 'Tambah Foto';

    final String headerLabel = (widget.component['label'] ?? '')
        .toString()
        .toUpperCase();
    final bool canAddMore = imageUrls.length < maxImages;
    final double thumbSize = (widget.component['previewSize'] ?? 90.0)
        .toDouble();

    return Container(
      margin: EdgeInsets.only(
        top: margin[0],
        bottom: margin[1],
        left: widget.lPad + margin[2],
        right: widget.rPad + margin[3],
      ),
      padding: EdgeInsets.fromLTRB(16, widget.tPad + 14, 16, widget.bPad + 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  sourceIcon,
                  size: 16,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headerLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                '${imageUrls.length} / $maxImages $fotoLabel',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Photo zone
          if (imageWidgets.isEmpty)
            GestureDetector(
              onTap: canAddMore && isEnabled
                  ? () => buttonPressed(widget.component, isEnabled)
                  : null,
              child: CustomPaint(
                painter: _DashedBorderPainter(color: const Color(0xFFBFDBFE)),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2F8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            sourceIcon,
                            size: 26,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          emptyTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (emptySubtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            emptySubtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF94A3B8),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: thumbSize,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: imageWidgets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => SizedBox(
                      width: thumbSize,
                      height: thumbSize,
                      child: imageWidgets[i],
                    ),
                  ),
                ),
                if (canAddMore && isEnabled) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => buttonPressed(widget.component, isEnabled),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2F8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add_a_photo_outlined,
                            size: 15,
                            color: Color(0xFF3B82F6),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            addLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF3B82F6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget buildImageWidget(String imageUrl, bool isEnabled) {
    return Stack(
      children: <Widget>[
        Card(
          child: InkWell(
            onTap: () {},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 1,
                  child: displayImage(imageUrl: imageUrl, cached: true),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: InkWell(
            onTap: isEnabled
                ? () {
                    // delete image
                    int imageIndex = GeneralGetXController.to
                        .getStringList(
                          widget.scrName,
                          widget.component['position'],
                        )
                        .indexOf(imageUrl);
                    if (imageIndex >= 0) {
                      setState(() {
                        GeneralGetXController.to.deleteWidgetAt(
                          widget.scrName,
                          widget.component['position'],
                          imageIndex,
                        );
                      });
                      String urlOutput = processData(
                        GeneralGetXController.to.getStringList(
                          widget.scrName,
                          widget.component['position'],
                        ),
                      );
                      try {
                        if (widget.component['position'] != null) {
                          txfControllerCheck(
                            widget.scrName,
                            widget.component['position'],
                          );
                          txfController[widget.scrName]![widget
                                      .component['position']]!
                                  .controller
                                  .text =
                              urlOutput;
                          txfController[widget.scrName]![widget
                                      .component['position']]!
                                  .finalData =
                              urlOutput;
                        }
                      } catch (e) {
                        errorReport(e);
                      }
                    }
                  }
                : null,
            child: Icon(
              Icons.cancel_outlined,
              color: isEnabled ? Colors.red : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
    try {
      GeneralGetXController.to.deleteAllWidget(
        widget.scrName,
        widget.component['position'],
      );
    } catch (e) {
      errorReport(e);
    }
  }

  @override
  bool get wantKeepAlive => true;
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  static const double _stroke = 1.5;
  static const double _dash = 6;
  static const double _gap = 5;
  static const double _radius = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            _stroke / 2,
            _stroke / 2,
            size.width - _stroke,
            size.height - _stroke,
          ),
          const Radius.circular(_radius),
        ),
      );

    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + _dash),
          Offset.zero,
        );
        distance += _dash + _gap;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
