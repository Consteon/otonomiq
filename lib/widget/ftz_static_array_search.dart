import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../api.dart';
import '../global.dart';
import '../otq_icons.dart';
import 'ftz_horizontal_image_list.dart';
// import 'dart:math';

class FtzStaticArraySearch extends StatefulWidget {
  const FtzStaticArraySearch({
    super.key,
    required this.localTable,
    this.resultController,
    required this.component,
  });
  final List<dynamic> localTable;
  final TextEditingController? resultController;
  final dynamic component;

  @override
  State<FtzStaticArraySearch> createState() => _FtzStaticArraySearchState();
}

class _FtzStaticArraySearchState extends State<FtzStaticArraySearch> {
  late List<dynamic> initialTable;
  late List<dynamic> pickTable; // searched localTable
  TextEditingController searchController = TextEditingController();
  late List<dynamic> textArray, style;
  var displayObject = {};
  String title = '', searchLabel = '', hint = '';
  String searchValue = '';
  double? listHeight;

  @override
  void initState() {
    try {
      textArray = (widget.component['text'] == null)
          ? []
          : diamondTextToList(widget.component['text']);
    } catch (e) {
      // do nothing}
    }
    try {
      if (widget.component['content'] != null) {
        displayObject = {
          "searchDisplayType": "text1",
          "content": widget.component['content'],
        };
        title = textArray[0];
        searchLabel = textArray[1];
        hint = textArray[2];
      } else if (textArray.length > 6) {
        displayObject = jsonDecode(textArray[6]);
        title = textArray[0];
        searchLabel = textArray[4];
        hint = textArray[5];
      }
    } catch (e) {
      // do nothing}
    }
    try {
      style = styleArray(widget.component['style']);
    } catch (e) {
      // do nothing}
    }
    try {
      searchValue = '';
      initialTable = searchTable(
        widget.component['filter'] ?? '',
        List.from(widget.localTable),
      );
      // pickTable = List.from(initialTable);
      pickTable = searchTable(searchValue, initialTable);
    } catch (e) {
      // do nothing}
    }

    super.initState();
  } // end of initState

  @override
  void dispose() {
    pickTable.clear();
    textArray.clear();
    style.clear();
    searchController.dispose();
    super.dispose();
  } // end of dispose

  Future<int?> detailDialog(dynamic dataContent, String stringContent) {
    const double imageMargin = 110.0;
    var currentWidth = MediaQuery.of(context).size.width;
    List<Widget> detailContent = [];
    List<String> imageList = widget.component['image'] == null
        ? [defaultImage]
        : getImageList(dataContent, widget.component['image']); // white diamond
    if ((widget.component['image'] ?? '') != '') {
      detailContent.add(
        GestureDetector(
          onTap: () {
            Get.back();
          },
          child: HorizontalImageList(
            imageUrls: imageList,
            height: currentWidth - imageMargin,
          ),
        ),
      );
      detailContent.add(const SizedBox(height: 8));
    } // end if ((widget.component['image'] ?? '') != '')
    detailContent.add(
      ListTile(
        onTap: () {
          Get.back();
        },
        subtitle: Text(
          // stringContent.replaceAll('\n', '\n\n'),
          // stringContent.replaceAll('\n', '--'),
          stringContent,
          style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
          // overflow: TextOverflow.,
          softWrap: true,
        ),
      ),
    );
    return Get.dialog(
      AlertDialog(
        content: SizedBox(
          width: currentWidth,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: detailContent.length,
            itemBuilder: (context, position) {
              return detailContent[position];
            },
          ),
        ),
      ),
    );
  } // end of detailDialog

  @override
  Widget build(BuildContext context) {
    listHeight ??= (MediaQuery.of(context).size.height * 0.6).round() * 1.0;
    devPrint('listHeight = $listHeight');
    return Column(
      // direction: Axis.vertical,
      children: [
        TextFormField(
          controller: searchController,
          keyboardType: TextInputType.text,
          onChanged: (value) {
            // search
            setState(() {
              searchValue = value;
              pickTable = searchTable(searchValue, initialTable);
            });
          },
          //end of onChanged
          decoration: InputDecoration(
            prefixIcon: widget.component['icon'].toString().isNotEmpty
                ? Icon(otqIcons[widget.component['icon'].toString()])
                : null,
            labelText: searchLabel,
            hintText: hint,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              borderSide: BorderSide(),
            ),
          ),
          style: TextStyle(
            color: (widget.component['color'] ?? 'default') != 'default'
                ? Color(int.parse(widget.component['color']))
                : Theme.of(context).textTheme.bodyLarge!.color,
            backgroundColor:
                (widget.component['background'] ?? 'default') != 'default'
                ? Color(int.parse(widget.component['background']))
                : Theme.of(context).textTheme.bodyLarge!.backgroundColor,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          // width: double.maxFinite,
          // height: 300, // Specify the height explicitly
          // child: ListView.builder(
          //   shrinkWrap: true,
          //   itemCount: 100,
          //   itemBuilder: (context, index) {
          //     return Text('Item $index');
          //   },
          // ),
          child: ListView.builder(
            itemCount: pickTable.isEmpty ? 1 : pickTable.length,
            shrinkWrap: true,
            prototypeItem: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: AspectRatio(
                      aspectRatio: 1,
                      child: displayImage(imageUrl: defaultImage, cached: true),
                      // child: FadeInImage.memoryNetwork(
                      //     placeholder: kTransparentImage, image: defaultImage),
                    ),
                    subtitle: pickTable.isEmpty
                        ? const Text('\n--\n\n')
                        : Text(
                            displayObject['content'] == null
                                ? '${pickTable.first[0].value}\n${pickTable.first[1].value}\n${pickTable.first[5].value}'
                                : replaceMarkerPrototype(
                                    displayObject['content'],
                                    pickTable.first,
                                    widget.component['indexStart'] ?? 0,
                                  ),
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.6),
                            ),
                            overflow: TextOverflow.fade,
                            softWrap: false,
                          ),
                  ),
                ],
              ),
            ),
            itemBuilder: (context, index) {
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      onTap: () {
                        if (widget.resultController != null) {
                          widget.resultController!.text = pickTable[index][1]
                              .toString();
                          Get.back();
                        } else {
                          detailDialog(
                            pickTable[index],
                            displayObject['content'] == null
                                ? '${pickTable.first[0]}\n${pickTable.first[1]}'
                                : replaceMarker(
                                    displayObject['content'],
                                    pickTable[index],
                                    widget.component['indexStart'] ?? 0,
                                    false,
                                  ),
                          );
                        }
                      },
                      leading: (widget.component['image'] ?? '') == ''
                          ? null
                          : AspectRatio(
                              aspectRatio: 1,
                              child: displayImage(
                                imageUrl: getImageList(
                                  pickTable[index],
                                  widget.component['image'],
                                )[0],
                                cached: false,
                              ),
                              // child: FadeInImage.memoryNetwork(
                              //   placeholder: kTransparentImage,
                              //   image: getImageList(pickTable[index],
                              //       widget.component['image'])[0],
                              // ),
                            ),
                      subtitle: pickTable.isEmpty
                          ? const Text('--')
                          : Text(
                              displayObject['content'] == null
                                  ? '${pickTable.first[0]}\n${pickTable.first[1]}\n${pickTable.first[5]}'
                                  : replaceMarker(
                                      displayObject['content'],
                                      pickTable[index],
                                      widget.component['indexStart'] ?? 0,
                                      false,
                                    ),
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ], // end of children
    );
  } // end of build
} // end of _FtzStaticArraySearchState
