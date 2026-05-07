import 'package:flutter/material.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../otq_icons.dart';

class OtqRdo2 extends StatefulWidget {
  const OtqRdo2({
    required Key key,
    required this.component,
    required this.scrName,
    required this.lPad,
    required this.tPad,
    required this.rPad,
    required this.bPad,
  }) : super(key: key);
  final dynamic component;
  final String scrName;
  final double lPad;
  final double tPad;
  final double rPad;
  final double bPad;

  @override
  _OtqRdo2State createState() => _OtqRdo2State();
}

class _OtqRdo2State extends State<OtqRdo2>
    with AutomaticKeepAliveClientMixin<OtqRdo2> {
  String? _picked;
  List<double> margin = [];
  List<String> menu = [];
  Axis axis = Axis.vertical;
  MainAxisAlignment align = MainAxisAlignment.start;

  @override
  initState() {
    super.initState();
    _picked = widget.component['currentValue'];

    if (widget.component['position'] != null) {
      txfControllerCheck(widget.scrName,
          widget.component['position']); // build txfController if necessary
      if (canInitializePage(widget.scrName)) {
        txfController[widget.scrName]![widget.component['position']]!
            .finalData = _picked ?? "";
        txfController[widget.scrName]![widget.component['position']]!
            .initialValue = _picked ?? "";
      } // end if (canInitializePage(widget.scrName))
    } // end if (widget.component['position'] != null)

    // if (widget.component['position'] != null &&
    //     txfController[widget.scrName]![widget.component['position']] == null) {
    //   txfController[widget.scrName]![widget.component['position']] =
    //       InputController(
    //           widget.component['position'],
    //           TextEditingController(),
    //           widget.component['currentValue'] ?? "",
    //           widget.component['currentValue'] ?? emptyString);
    // } else {
    //   txfController[widget.scrName]![widget.component['position']]!.finalData =
    //       _picked ?? "";
    //   txfController[widget.scrName]![widget.component['position']]!
    //       .initialValue = _picked ?? "";
    // } // end if (txfController[scrName]![_component['position']] == null)
    margin = marginArray(widget.component['margin']);
    menu = List<String>.from(widget.component['menu'] ?? ['--']);
    axis = (widget.component['buttonLayout'] ?? 'vertical')
        .toString()
        .toLowerCase() ==
        'horizontal'
        ? Axis.horizontal
        : Axis.vertical;
    align = mainAlignmentConst(widget.component['alignment']);
  } // end of initState()

  void _select(String item) {
    setState(() => _picked = item);
    if (widget.component['position'] != null) {
      txfControllerCheck(widget.scrName, widget.component['position']);
      txfController[widget.scrName]![widget.component['position']]!.finalData =
          item;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    try {
      final component = widget.component;
      final List<String> items = List<String>.from(component['menu'] ?? ['--']);
      final String iconKey = component['icon']?.toString() ?? '';
      final String labelText =
      (component['label'] ?? '').toString().toUpperCase();

      return Container(
        margin: EdgeInsets.only(
          top: margin[0],
          bottom: margin[1],
          left: widget.lPad + margin[2],
          right: widget.rPad + margin[3],
        ),
        padding:
        EdgeInsets.fromLTRB(16, widget.tPad + 12, 16, widget.bPad + 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            if (iconKey.isNotEmpty || labelText.isNotEmpty) ...[
              Row(
                children: [
                  if (iconKey.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDE4EE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        otqIcons[iconKey],
                        size: 16,
                        color: const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    labelText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // Option cards
            ...items.asMap().entries.map((entry) {
              final item = entry.value;
              final parts = item.split(separator[1]);
              final title = parts[0];
              final subtitle = parts.length > 1 ? parts[1] : null;
              final isSelected = _picked == item;
              final isLast = entry.key == items.length - 1;

              return GestureDetector(
                onTap: () => _select(item),
                child: Container(
                  margin: isLast
                      ? EdgeInsets.zero
                      : const EdgeInsets.only(bottom: 10),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Radio circle
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFCBD5E1),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      // Text
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      );
    } catch (err) {
      return Text("--Radio Button (RDO)-- [ $err]");
    }
  } // end of build

  @override
  bool get wantKeepAlive => true;
}
