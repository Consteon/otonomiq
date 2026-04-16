import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../global2.dart';
import '../api.dart';
import '../global.dart';
import '../otq_icons.dart';
import 'ftz_horizontal_image_list.dart';
// import 'dart:math';

class FtzArraySearch extends StatefulWidget {
  const FtzArraySearch({
    super.key,
    required this.localTable,
    this.resultController,
    required this.component,
    this.startPosition = 0,
  });
  final List<dynamic> localTable;
  final TextEditingController? resultController;
  final dynamic component;
  final int startPosition;

  @override
  State<FtzArraySearch> createState() => _FtzArraySearchState();
}

class _FtzArraySearchState extends State<FtzArraySearch> {
  late List<dynamic> initialTable;
  late List<dynamic> pickTable; // searched localTable
  TextEditingController searchController = TextEditingController();
  late List<dynamic> textArray, style;
  var displayObject = {};
  String title = '', searchLabel = '', hint = '';
  String searchValue = '';
  String? finalFilter;

  @override
  void initState() {
    try {
      if (widget.component['filter'] != null) {
        List<String> parts = (autheniumDecode(widget.component['filter']) ?? '')
            .split(separator[8]); // white hollow circle
        if (parts.length > 1) {
          finalFilter = parts[1];
        }
      }
    } catch (e) {
      // do nothing}
    }
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
          "content": widget.component['content']
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
      initialTable =
          searchTable(finalFilter ?? '', List.from(widget.localTable));
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
      detailContent.add(GestureDetector(
        onTap: () {
          Get.back();
        },
        child: HorizontalImageList(
          imageUrls: imageList,
          height: currentWidth - imageMargin,
        ),
      ));
      detailContent.add(const SizedBox(
        height: 8,
      ));
    } // end if ((widget.component['image'] ?? '') != '')
    detailContent.add(ListTile(
      onTap: () {
        Get.back();
      },
      subtitle: Text(
        // stringContent.replaceAll('\n', '\n\n'),
        // stringContent.replaceAll('\n', '--'),
        stringContent,
        style: TextStyle(color: Colors.black.withOpacity(0.6)),
        // overflow: TextOverflow.,
        softWrap: true,
      ),
    ));
    return Get.dialog(AlertDialog(
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
    ));
  } // end of detailDialog

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          // key: txfKey,
          controller: searchController,
          keyboardType: TextInputType.text,
          // obscureText: obscure,
          // enabled: editable,
          // inputFormatters: tiFormatter,
          // onTap: txfOnTap,
          onChanged: (value) {
            // search
            setState(() {
              searchValue = value;
              // by ai : pickTable = searchTable(searchValue, initialTable);
            });
          },
          //end of onChanged
          decoration: InputDecoration(
            prefixIcon: widget.component['icon'].toString().isNotEmpty
                ? Icon(
                    otqIcons[widget.component['icon'].toString()],
                  )
                : null,
            labelText: searchLabel,
            hintText: hint,
            border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide()),
          ),
          style: TextStyle(
            color: (widget.component['color'] ?? 'default') != 'default'
                ? Color(int.parse(widget.component['color']))
                : Theme.of(context).textTheme.bodyLarge!.color,
            backgroundColor:
                (widget.component['background'] ?? 'default') != 'default'
                    ? Color(int.parse(widget.component['background']))
                    : Theme.of(context).textTheme.bodyLarge!.backgroundColor,
            // fontWeight: style[0],
            // fontStyle: style[1],
            // decoration: style[2],
            // fontSize: 0.0 + (widget.component['size'] ?? 16.0).toDouble(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          // height: 200,
          child: Obx(() {
            String tableCode = normalizeTableName(
                autheniumDecode(widget.component['table'] ?? 'default') ?? '');
            '';
            debugPrint(
                'ftz_array_search Obx for table ${widget.component['table']} triggered');
            // --- FIX by AI STARTS HERE ---
            // 1. Directly use the reactive tableContent to get the latest data.
            List<dynamic> currentTableData =
                List.from(tableContent[tableCode] ?? []);

            // 2. Perform all data preparation here, without modifying any reactive state.
            initialTable = searchTable(finalFilter ?? '', currentTableData);

            String sortParam = widget.component['sort'] ?? '';
            if (sortParam == 'asc' || sortParam == 'desc') {
              int sortFactor = sortParam == 'asc' ? 1 : -1;
              try {
                initialTable.sort((a, b) =>
                    sortFactor *
                    int.parse(a[0].toString())
                        .compareTo(int.parse(b[0].toString())));
              } catch (e) {
                devPrint(e);
              }
            }

            // 3. Filter based on the local search value.
            pickTable = searchTable(searchValue, initialTable);
            // --- FIX ENDS HERE ---

            // debugPrint(
            //     'ftz_array_search Obx widget.localTable len = ${widget.localTable.length}. ');
            // if (tableSourceUpdated[tableCode] ?? true) {
            //   // tableSourceUpdated[tableCode] = false;
            //   int sortFactor = 0;
            //   String sortParam = widget.component['sort'] ?? '';
            //   switch (sortParam) {
            //     case 'asc':
            //       sortFactor = 1;
            //       break;
            //     case 'desc':
            //       sortFactor = -1;
            //       break;
            //     default:
            //       sortFactor = 0;
            //   }
            //   initialTable = searchTable(widget.component['filter'] ?? '',
            //       List.from(tableContent[tableCode] ?? []));
            //   if (sortFactor != 0) {
            //     try {
            //       initialTable.sort((a, b) =>
            //           sortFactor * int.parse(a[0].toString()).compareTo(int.parse(b[0].toString())));
            //     } catch (e) {
            //       devPrint(e);
            //     }
            //   } //if (sortFactor != 0)
            //   pickTable = searchTable(searchValue, initialTable);
            // }
            debugPrint('pickTable length = ${pickTable.length}');
            return ListView.builder(
              itemCount: pickTable.length,
              cacheExtent: 1000,
              prototypeItem: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: AspectRatio(
                        aspectRatio: 1,
                        child:
                            displayImage(imageUrl: defaultImage, cached: true),
                        // child: FadeInImage.memoryNetwork(
                        //     placeholder: kTransparentImage,
                        //     image: defaultImage),
                      ),
                      subtitle: pickTable.isEmpty
                          ? const Text('\n--\n\n')
                          : Text(
                              displayObject['content'] == null
                                  ? '${pickTable.first[0].value}\n${pickTable.first[1].value}\n${pickTable.first[5].value}'
                                  : replaceMarkerPrototype(
                                      displayObject['content'],
                                      pickTable.first,
                                      widget.component['indexStart'] ?? 0),
                              style: TextStyle(
                                  color: Colors.black.withOpacity(0.6)),
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                    ),
                    const SizedBox(height: 5), //bottom padding
                  ],
                ),
              ),
              itemBuilder: (context, index) {
                // String? imageUrl;
                // if (widget.component['image'] != null) {
                //   try {
                //     imageUrl = pickTable[index][int.parse(widget
                //         .component['image']
                //         .replaceAll('<', '')
                //         .replaceAll('>', ''))];
                //   } catch (e) {}
                // } // end if (widget.component['image'] != null)
                // if (imageUrl != null || imageUrl.toString().trim().isEmpty) {
                //   imageUrl = null;
                // }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        onTap: () {
                          if (widget.resultController != null) {
                            widget.resultController!.text =
                                pickTable[index][1].toString();
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
                                        false));
                          }
                        },
                        leading: (widget.component['image'] ?? '') == ''
                            ? null
                            : AspectRatio(
                                aspectRatio: 1,
                                child: displayImage(
                                    imageUrl: getImageList(pickTable[index],
                                        widget.component['image'])[0],
                                    cached: false),
                                // child: FadeInImage.memoryNetwork(
                                //   placeholder: kTransparentImage,
                                //   image: getImageList(pickTable[index],
                                //       widget.component['image'])[0],
                                // ),
                              ),
                        // leading: AspectRatio(
                        //   aspectRatio: 1,
                        //   child: FadeInImage.memoryNetwork(
                        //       placeholder: kTransparentImage,
                        //       image:
                        //       'https://firebasestorage.googleapis.com/v0/b/otq-01-ase2/o/vt%2F2020%2Fs%2Fkrusty-services%2Fattendance-selfie%2Fsurya-widjaja%2F60181816889090-2020-11-06-13-07-12.jpg?alt=media&token=d04a568d-5de5-4b98-bc9a-7dbdfacc58ae'),
                        // ),
                        subtitle:
                            // FittedBox(
                            // // fit: BoxFit.scaleDown,
                            // fit: BoxFit.fitHeight,
                            // clipBehavior: Clip.hardEdge,
                            // alignment: Alignment.centerLeft,
                            // child:
                            pickTable.isEmpty
                                ? const Text('--')
                                : Text(
                                    displayObject['content'] == null
                                        ? '${pickTable.first[0]}\n${pickTable.first[1]}\n${pickTable.first[5]}'
                                        : replaceMarker(
                                            displayObject['content'],
                                            pickTable[index],
                                            widget.component['indexStart'] ?? 0,
                                            false),
                                    style: TextStyle(
                                        color: Colors.black.withOpacity(0.6)),
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                  ),
                        // ),
                      ),
                    ],
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}
