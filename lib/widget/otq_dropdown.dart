import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../global.dart';
import '../global2.dart';
import '../init_values.dart';
import 'otq_formatted_text.dart';

class OtqDropdown extends StatefulWidget {
  const OtqDropdown({
    required Key key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  State<StatefulWidget> createState() => _OtqDropdownState();
}

class _OtqDropdownState extends State<OtqDropdown>
    with AutomaticKeepAliveClientMixin<OtqDropdown> {
  String _itemSelected = "";
  List<DropdownMenuItem<String>> dropDownMenuItems = [];
  List<double> margin = [];
  late Widget drd;
  late List<String> dropdownItems;
  late bool dataSeparated;
  List<String> dropdownData = [];
  dynamic dataMap = {};
  bool expanded = false;
  String labelPosition = 'left';
  late final int? _position;

  @override
  void initState() {
    super.initState();
    _position = widget.component['position'] as int?;

    if (widget.component['menu'] != null) {
      dropdownItems = List<String>.from(widget.component['menu'] ?? ['--']);
    } else {
      dropdownItems = List<String>.from(widget.component['option'] ?? ['--']);
    }

    if (widget.component['data'] != null) {
      dropdownData = List<String>.from(widget.component['data']);
    }

    dropDownMenuItems = dropdownItems
        .map(
          (String value) => DropdownMenuItem<String>(
        value: value,
        child: Text(value),
      ),
    )
        .toList();

    // The widget's internal UI state is initialized from the controller,
    // which was set up by buildDisplayComponent.
    _itemSelected = getInitialValue(widget.scrName, widget.component);
    if (!(dropdownItems.contains(_itemSelected))) {
      _itemSelected = '';
    }

    margin = marginArray(widget.component['margin']);
    if (dropdownData.length == dropdownItems.length) {
      dataSeparated = true;
      for (int i = 0; i < dropdownItems.length; i++) {
        dataMap[dropdownItems[i]] = dropdownData[i];
      }
    } else {
      dataSeparated = false; // Set to false if lengths don't match
    }
    labelPosition =
        (widget.component['labelPosition'] ?? "left").toString().toLowerCase();
    if (labelPosition == 'top' || labelPosition == 'bottom') {
      expanded = true;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // needed by AutomaticKeepAliveClientMixin

    if (_position == null) {
      return _buildContent(context, true);
    }

    return GetBuilder<WidgetUpdateController>(
      id: '${widget.scrName}-$_position',
      builder: (_) {
        final controller = txfController[widget.scrName]![_position]!;
        final bool isEnabled = controller.isEnabled;
        return _buildContent(context, isEnabled);
      },
    );
  }

  Widget _buildContent(BuildContext context, bool isEnabled) {
    // Set onChanged to null when disabled to get the default disabled visual style
    final onChangedCallback = isEnabled
        ? (String? val) {
      setState(() {
        _itemSelected = val ?? "";
      });
      if (widget.component['position'] != null) {
        txfControllerCheck(widget.scrName, widget.component['position']);
        txfController[widget.scrName]![widget.component['position']]!
            .finalData = dataSeparated ? dataMap[val] ?? "" : val ?? "";
      }
    }
        : null;

    // Define the DropdownButton widget itself
    final dropdownWidget = _itemSelected == ""
        ? DropdownButton<String>(
      hint: Text(widget.component['hint'] ?? emptyString),
      isExpanded: expanded,
      onChanged: onChangedCallback,
      items: dropDownMenuItems,
    )
        : DropdownButton<String>(
      isExpanded: expanded,
      value: _itemSelected,
      onChanged: onChangedCallback,
      items: dropDownMenuItems,
    );

    // Wrap the dropdown in an IgnorePointer to block all touch events when disabled
    drd = IgnorePointer(
      ignoring: !isEnabled,
      child: dropdownWidget,
    );

    late Widget resultWidget;
    if (labelPosition == 'right') {
      resultWidget = Row(
        mainAxisAlignment: mainAlignmentConst(widget.component['alignment']),
        children: <Widget>[
          drd,
          Container(width: 8),
          OtqFormattedText(
              textData: widget.component['label'] ?? "",
              component: widget.component),
        ],
      );
    } else if (labelPosition == 'top') {
      resultWidget = Column(
        crossAxisAlignment:
        crossAlignmentConst(widget.component['alignment']),
        children: [
          OtqFormattedText(
              textData: widget.component['label'] ?? "",
              component: widget.component),
          drd,
        ],
      );
    } else if (labelPosition == 'bottom') {
      resultWidget = Column(
        crossAxisAlignment:
        crossAlignmentConst(widget.component['alignment']),
        children: [
          drd,
          OtqFormattedText(
              textData: widget.component['label'] ?? "",
              component: widget.component),
        ],
      );
    } else {
      // default || left
      resultWidget = Row(
        mainAxisAlignment: mainAlignmentConst(widget.component['alignment']),
        children: <Widget>[
          OtqFormattedText(
              textData: widget.component['label'] ?? "",
              component: widget.component),
          Container(width: 8),
          drd,
        ],
      );
    }
    return Container(
      margin: EdgeInsets.only(top: margin[0], bottom: margin[1]),
      padding: EdgeInsets.fromLTRB(max(0, widget.lPad + margin[2] - 0),
          widget.tPad, max(0, widget.rPad + margin[3] - 0), widget.bPad),
      child: resultWidget,
    );
  }

  @override
  bool get wantKeepAlive => true;
}