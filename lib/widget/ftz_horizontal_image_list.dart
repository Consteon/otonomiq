import 'package:flutter/material.dart';

import '../api.dart';
// chat gpt : how to create a widget in flutter that can display a list of images, scroll horizontally with dots image indicator

class HorizontalImageList extends StatefulWidget {
  final List<String> imageUrls;
  final double height;

  const HorizontalImageList({
    super.key,
    required this.imageUrls,
    this.height = 200,
  });

  @override
  HorizontalImageListState createState() => HorizontalImageListState();
}

class HorizontalImageListState extends State<HorizontalImageList> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: widget.height, // adjust the height according to your needs
          child: PageView.builder(
            // physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.imageUrls.length,
            controller: _pageController,
            onPageChanged: (int page) {
              setState(() {
                _currentPage = page;
              });
            },
            itemBuilder: (BuildContext context, int index) {
              // return Image.network(
              //   widget.imageUrls[index],
              //   fit: BoxFit.cover,
              // )
              return displayImage(
                imageUrl: widget.imageUrls[index],
                cached: true,
              );
            },
          ),
        ),
        // A single dot conveys nothing — only paginate when there is more than
        // one page to move between.
        if (widget.imageUrls.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.imageUrls.length, (index) {
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context).disabledColor,
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}
