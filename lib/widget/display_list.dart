//
// display_list.dart
//
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../widget/ui_component.dart';
import 'ftz_array_search.dart';
import 'otq_formatted_text.dart';

class DisplayList extends StatefulWidget {
  const DisplayList({
    super.key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  });
  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  State<DisplayList> createState() => _DisplayListState();
}

class _DisplayListState extends State<DisplayList> {
  late List<double> margin;
  List<Widget> dialogWidgets = [Container()];
  bool hasChain = false;
  RxList<dynamic> pickTable = [].obs; // source of table will be copied here
  bool useTable = false;
  String variant = '';
  late Widget listItems;
  late List<dynamic> textArray;
  bool tableLoaded = false;
  String currentTableCode =
      '-1'; // Initialize with a value that is unlikely to be a real table name

  @override
  void initState() {
    super.initState();
    try {
      textArray = (widget.component['text'] == null)
          ? []
          : diamondTextToList(widget.component['text']);
    } catch (e) {
      // do nothing}
    }
    variant = (widget.component['variant'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    margin = marginArray(widget.component['margin']);
    hasChain = widget.component['chain'] != null;

    if (variant == 'widget') {
      dialogWidgets = buildPage(
        widget.component['children'],
        widget.scrName,
        dialog: true,
        clear: false,
      );
    } else if (variant == 'tablecard1' || variant == 'tablecardinteractive') {
      useTable = true;
    }
  }

  void _loadTable(String tableCode) {
    if (tableCode.isEmpty) {
      if (mounted) {
        setState(() {
          currentTableCode = '';
          tableLoaded = true; // Considered "loaded" an empty state
          pickTable = [].obs;
        });
      }
      return;
    }

    if (tableCode == currentTableCode) {
      return; // Do not reload the same table
    }

    // Set loading state
    if (mounted) {
      setState(() {
        currentTableCode = tableCode;
        tableLoaded = false;
        pickTable = [].obs;
      });
    }

    tableSourceUpdated[tableCode] = true;
    subscribeToTable(tableCode, appCodeController.applicationTableVid).then((
      _,
    ) {
      if (mounted) {
        // Check if the widget is still in the tree
        setState(() {
          pickTable = tableToArray(
            transactionStore.state.screenTx['#TABLE$tableCode'],
            tableCode,
            widget.component['sort'],
          ).obs;
          pickTable = searchTable(
            widget.component['filter'] ?? '',
            List.from(pickTable),
          ).obs;
          tableLoaded = true;
        });
        debugPrint(
          ' ==> pickTable for $tableCode loaded, len=${pickTable.length}',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    String? builderId;
    if (widget.component['position'] != null) {
      builderId =
          '${widget.scrName}-${getPosition(widget.component['position'])}';
    }

    return GetBuilder<WidgetUpdateController>(
      id: builderId,
      builder: (controller) {
        String tableCodeToLoad = '';

        if (useTable && widget.component['position'] != null) {
          final int position = getPosition(widget.component['position']);
          if (txfController.containsKey(widget.scrName) &&
              txfController[widget.scrName]!.containsKey(position)) {
            tableCodeToLoad =
                txfController[widget.scrName]![position]!.finalData;
          }
        } else if (useTable) {
          // Fallback for components without a position
          tableCodeToLoad = widget.component['table']?.toString().trim() ?? '';
        }

        // Trigger table load if it has changed
        if (tableCodeToLoad != currentTableCode) {
          // Use a post-frame callback to safely update state after the build phase
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadTable(tableCodeToLoad);
          });
        }

        // Build the list items based on the current state
        if (variant == 'tablecardinteractive') {
          listItems = FtzArraySearch(
            localTable: pickTable,
            component: widget.component,
          );
        } else if (variant == 'tablecard1') {
          if (!tableLoaded) {
            listItems = const Center(child: CircularProgressIndicator());
          } else {
            listItems = pickTable.isEmpty
                ? const Center(child: Text('No data'))
                : ListView.builder(
                    itemCount: pickTable.length,
                    prototypeItem: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          ListTile(
                            subtitle: Text(
                              widget.component['content'] == null
                                  ? '${pickTable.first[0]}\n${pickTable.first[1]}\n${pickTable.first[5]}'
                                  : replaceMarkerPrototype(
                                      widget.component['content'],
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
                              subtitle: Text(
                                widget.component['content'] == null
                                    ? '${pickTable.first[0]}\n${pickTable.first[1]}\n${pickTable.first[5]}'
                                    : replaceMarker(
                                        widget.component['content'],
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
                  );
          }
        } else if (variant == 'widget') {
          listItems = ListView(
            shrinkWrap: true,
            scrollDirection: Axis.vertical,
            controller: ScrollController(),
            children: dialogWidgets,
          );
        } else {
          listItems = Container();
        }

        const double padWithTitle = 40;
        final double topPad =
            (textArray.isNotEmpty && textArray[0].toString().trim() == '')
            ? 8
            : padWithTitle;

        return Container(
          constraints: BoxConstraints(
            maxHeight: (widget.component['height'] ?? 150) + 0.0,
          ),
          margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
          padding: EdgeInsets.fromLTRB(
            max(0, widget.lPad + margin[2]),
            widget.tPad,
            max(0, widget.rPad + margin[3]),
            widget.bPad,
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: const BorderRadius.all(Radius.circular(16.0)),
                ),
                padding: EdgeInsets.fromLTRB(10, topPad, 10, 10),
                child: listItems,
              ),
              (topPad != padWithTitle || textArray.isEmpty)
                  ? Container()
                  : Positioned(
                      left: 8,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.only(left: 10, right: 10),
                        // Match the page, not white: the title chip sits ON the
                        // frame border, so a hardcoded white left a visible patch
                        // on any non-white scaffold.
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: OtqFormattedText(
                          textData:
                              (textArray.isNotEmpty ? textArray[0] : null) ??
                              "",
                          component: widget.component,
                        ),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }
}
