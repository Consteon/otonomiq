import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../global.dart';
import '../global2.dart';
import '../init_values.dart';

class OtqDropdown2 extends StatefulWidget {
  const OtqDropdown2({
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
  State<StatefulWidget> createState() => _OtqDropdown2State();
}

class _OtqDropdown2State extends State<OtqDropdown2>
    with AutomaticKeepAliveClientMixin<OtqDropdown2> {
  String _itemSelected = "";
  List<double> margin = [];
  late List<String> dropdownItems;
  late bool dataSeparated;
  List<String> dropdownData = [];
  List<String> subtitleItems = [];
  dynamic dataMap = {};
  late final int? _position;
  final TextEditingController _searchController = TextEditingController();

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

    if (widget.component['subtitle'] != null) {
      subtitleItems = List<String>.from(widget.component['subtitle']);
    }

    _itemSelected = getInitialValue(widget.scrName, widget.component);
    if (!dropdownItems.contains(_itemSelected)) {
      _itemSelected = '';
    }

    margin = marginArray(widget.component['margin']);
    if (dropdownData.length == dropdownItems.length) {
      dataSeparated = true;
      for (int i = 0; i < dropdownItems.length; i++) {
        dataMap[dropdownItems[i]] = dropdownData[i];
      }
    } else {
      dataSeparated = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openBottomSheet(BuildContext context) {
    List<String> filtered = List.from(dropdownItems);
    _searchController.clear();

    final String labelStr = (widget.component['label'] ?? '').toString().trim();
    final String sheetTitle =
    (widget.component['sheetTitle'] ?? 'Pilih $labelStr').toString();
    final String searchHint =
    (widget.component['searchHint'] ?? 'Cari...').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final double maxHeight = MediaQuery.of(ctx).size.height * 0.7;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title + close button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                  child: Row(
                    children: [
                      Text(
                        sheetTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                // Search field
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        setModalState(() {
                          filtered = dropdownItems
                              .where((item) => item
                              .toLowerCase()
                              .contains(val.toLowerCase()))
                              .toList();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: searchHint,
                        hintStyle: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF9CA3AF),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 4),
                      ),
                    ),
                  ),
                ),
                // Item list — shrinks to content, scrolls when capped at maxHeight
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, index) {
                      final String item = filtered[index];
                      final int originalIndex = dropdownItems.indexOf(item);
                      final bool hasSub = originalIndex >= 0 &&
                          originalIndex < subtitleItems.length;
                      final bool isSelected = item == _itemSelected;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _itemSelected = item;
                          });
                          if (_position != null) {
                            txfControllerCheck(widget.scrName, _position);
                            txfController[widget.scrName]![_position]!
                                .finalData =
                            dataSeparated ? dataMap[item] ?? "" : item;
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFF6B7280),
                                      ),
                                    ),
                                    if (hasSub) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitleItems[originalIndex],
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check,
                                    color: Color(0xFF2563EB), size: 18),
                            ],
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
    final String labelStr = (widget.component['label'] ?? '').toString().trim();
    final String hintStr = (widget.component['hint'] ?? 'Pilih...').toString();
    final bool showTitle = labelStr.isNotEmpty;
    final bool hasValue = _itemSelected.isNotEmpty;

    final Widget selectorPill = GestureDetector(
      onTap: isEnabled ? () => _openBottomSheet(context) : null,
      child: Container(
        margin: showTitle
            ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
            : EdgeInsets.only(
          top: margin[0],
          bottom: margin[1],
          left: widget.lPad + margin[2],
          right: widget.rPad + margin[3],
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
          boxShadow: showTitle
              ? []
              : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.tPad.clamp(10.0, 16.0),
            8,
            widget.bPad.clamp(10.0, 16.0),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasValue ? _itemSelected : hintStr,
                  style: TextStyle(
                    color: Color.fromARGB(255, 88, 91, 97),
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isEnabled
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFFD1D5DB),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );

    if (!showTitle) {
      return selectorPill;
    }

    return Container(
      margin: EdgeInsets.only(
        top: margin[0],
        bottom: margin[1],
        left: widget.lPad + margin[2],
        right: widget.rPad + margin[3],
      ),
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              labelStr.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
                letterSpacing: 0.5,
              ),
            ),
          ),
          selectorPill,
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
