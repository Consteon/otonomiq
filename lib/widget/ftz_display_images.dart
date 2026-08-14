import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

// import '../global.dart';
import '../global2.dart';

/// A widget to display a horizontally scrollable list of images with an optional title.
///
/// Tapping on an image opens it in a full-screen viewer with zoom capabilities.
/// The widget's state is managed via txfController and rebuilt using GetBuilder.
class FtzDisplayImages extends StatefulWidget {
  final Map<String, dynamic> component;
  final String scrName;

  const FtzDisplayImages({
    super.key,
    required this.component,
    required this.scrName,
  });

  @override
  State<FtzDisplayImages> createState() => _FtzDisplayImagesState();
}

class _FtzDisplayImagesState extends State<FtzDisplayImages> {
  late final int? _position;
  late final double _height;
  late final EdgeInsets _margin;
  late final String? _title;
  late final double _titleSize;
  late final Color _titleColor;

  @override
  void initState() {
    super.initState();
    _parseComponent();
  }

  /// Parses the `component` map to configure the widget's static properties
  /// and initialize its state in the global controller.
  void _parseComponent() {
    // Extract position for txfController integration.
    _position = widget.component['position'] as int?;

    final dynamic heightValue = widget.component['height'];
    if (heightValue is num) {
      _height = heightValue.toDouble();
    } else if (heightValue is String) {
      _height = double.tryParse(heightValue) ?? 150.0;
    } else {
      _height = 150.0;
    }

    _margin = stringToEdgeInsets(widget.component['margin'] as String?);
    _title = widget.component['text'] as String?;

    final dynamic sizeValue = widget.component['size'];
    if (sizeValue is num) {
      _titleSize = sizeValue.toDouble();
    } else if (sizeValue is String) {
      _titleSize = double.tryParse(sizeValue) ?? 16.0;
    } else {
      _titleSize = 16.0;
    }

    _titleColor = stringToColor(
      widget.component['textColor'] as String? ?? 'black',
    );
    final String imageString = widget.component['images'] as String? ?? '';

    // Initialize the controller. The GetBuilder will read from this.
    if (_position != null) {
      // txfControllerCheck(widget.scrName, _position);
      // Use controller.text as the state holder for the image string.
      txfController[widget.scrName]![_position]!.controller.text = imageString;
    }
  }

  /// Navigates to a new page to show the selected image in full-screen.
  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenImageView(imageUrl: imageUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A position is required for state management.
    if (_position == null) {
      return Padding(
        padding: _margin,
        child: const Text(
          'FtzDisplayImages requires a "position" property.',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
      );
    }

    return GetBuilder<WidgetUpdateController>(
      id: '${widget.scrName}-$_position', // Unique ID for targeted updates
      builder: (_) {
        // Read the current state directly from the controller.
        final controller = txfController[widget.scrName]![_position]!;
        final String imageString = controller.controller.text;
        final List<String> imageUrls = imageString
            .split('◇')
            .where((url) => url.trim().isNotEmpty)
            .toList();

        // The main widget layout.
        return Padding(
          padding: _margin,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Display the title if it's provided.
              if (_title != null && _title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    _title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _titleSize,
                      color: _titleColor,
                    ),
                  ),
                ),
              // Display a message if there are no images to show.
              if (imageUrls.isEmpty)
                Container(
                  height: _height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: const Text('No images provided.'),
                )
              else
                SizedBox(
                  height: _height,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: imageUrls.length,
                    itemBuilder: (context, index) {
                      final imageUrl = imageUrls[index];
                      return GestureDetector(
                        onTap: () => _showFullScreenImage(context, imageUrl),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12.0),
                            child: Container(
                              width: _height,
                              color: Colors.white,
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          value:
                                              loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                        .cumulativeBytesLoaded /
                                                    loadingProgress
                                                        .expectedTotalBytes!
                                              : null,
                                        ),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Icon(
                                      Icons.error_outline,
                                      color: Colors.redAccent,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A separate screen for displaying an image in a true, immersive full-screen view.
class FullScreenImageView extends StatefulWidget {
  final String imageUrl;

  const FullScreenImageView({super.key, required this.imageUrl});

  @override
  State<FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  final TransformationController _transformationController =
      TransformationController();
  ImageStream? _imageStream;
  Size _imageSize = Size.zero;
  late ImageStreamListener _imageListener;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // onError marks a failed load as HANDLED. Without an error listener the
    // framework routes the failure to FlutterError.onError, which main.dart
    // reports as a FATAL crash (Crashlytics: NetworkImage._loadAsync, HTTP
    // 403/404/offline) even though nothing actually died. The user-visible
    // fallback is the errorBuilder on the image in build().
    _imageListener = ImageStreamListener(_onImageLoad, onError: (_, _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getImageSize();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _imageStream?.removeListener(_imageListener);
    _transformationController.dispose();
    super.dispose();
  }

  void _getImageSize() {
    final image = Image.network(widget.imageUrl);
    _imageStream = image.image.resolve(const ImageConfiguration());
    _imageStream?.addListener(_imageListener);
  }

  void _onImageLoad(ImageInfo info, bool synchronousCall) {
    final Size imageSize = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    if (mounted) {
      setState(() {
        _imageSize = imageSize;
      });
      _updateTransformation();
    }
  }

  void _updateTransformation() {
    if (_imageSize == Size.zero) return;

    final screenSize = MediaQuery.of(context).size;
    final scaleX = screenSize.width / _imageSize.width;
    final scaleY = screenSize.height / _imageSize.height;
    final scale = min(scaleX, scaleY);

    final dx = (screenSize.width - _imageSize.width * scale) / 2;
    final dy = (screenSize.height - _imageSize.height * scale) / 2;

    _transformationController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          Navigator.of(context).pop();
        },
        child: InteractiveViewer(
          transformationController: _transformationController,
          panEnabled: true,
          minScale: 0.1,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(100.0),
          constrained: false,
          child: Image.network(
            widget.imageUrl,
            // No errorBuilder ⇒ Image registers no error listener in release,
            // so a dead url becomes a Crashlytics fatal instead of an icon.
            errorBuilder: (_, _, _) => const SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
