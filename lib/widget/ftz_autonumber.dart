import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../global.dart';
import '../global2.dart';

class FtzAutoNumber extends StatefulWidget {
  final Map<String, dynamic> component;
  final String scrName;
  final Function(String)? onRun;

  const FtzAutoNumber({
    super.key,
    required this.component,
    required this.scrName,
    this.onRun,
  });

  @override
  State<FtzAutoNumber> createState() => FtzAutoNumberState();
}

class FtzAutoNumberState extends State<FtzAutoNumber> {
  late final List<String> _labels;
  late final Color _textColor;
  late final double _fontSize;
  late final int? _position;
  late final EdgeInsets _margin;
  late final String _title;
  late final String _placeholder;

  @override
  void initState() {
    super.initState();
    // ... (your existing initState logic)
    _labels = diamondTextToList(widget.component['text'] ?? '');
    _textColor = stringToColor(widget.component['color'] as String? ?? 'black');
    _position = widget.component['position'] as int?;
    _margin =
        stringToEdgeInsets(widget.component['margin'] as String? ?? '1,1,1,1');

    _title = _labels.isNotEmpty ? _labels[0] : 'Auto-Generated Number:';
    _placeholder = _labels.length > 1 ? _labels[1] : 'Press Generate';

    final dynamic sizeValue = widget.component['size'];
    if (sizeValue is num) {
      _fontSize = sizeValue.toDouble();
    } else if (sizeValue is String) {
      _fontSize = double.tryParse(sizeValue) ?? 16.0;
    } else {
      _fontSize = 16.0;
    }

    if (_position != null) {
      txfControllerCheck(widget.scrName, _position);
      final controller = txfController[widget.scrName]![_position]!;
      final existingData = controller.finalData;

      if (existingData.isNotEmpty &&
          existingData != emptyString &&
          existingData != 'null') {
        controller.controller.text = existingData;
      } else {
        controller.controller.text = _placeholder;
      }

      final String? executableString =
      widget.component['executable'] as String?;
      if (executableString != null && executableString.isNotEmpty) {
        final parts = executableString.split(',');
        if (parts.length == 2) {
          final String executableName = parts[0].trim().toLowerCase();
          final String actionName = parts[1].trim();
          final String template = widget.component['template'] as String? ?? '';

          final actionItem = [
            '${widget.scrName}-$_position',
            actionName,
            template,
          ];

          if (executableName == 'execute1') {
            controller.execute1 = [actionItem];
          } else if (executableName == 'execute2') {
            controller.execute2 = [actionItem];
          }
        }
      }
    }
  }

  // ADDED: The dispose method.
  @override
  void dispose() {
    // This method is for cleaning up resources to prevent memory leaks.
    // Examples:
    // _myOwnController.dispose();
    // _myStreamSubscription.cancel();

    // In this specific widget, we don't need to do anything here because
    // the TextEditingController is managed globally by the InputController.
    // It is NOT the correct place to reset state.

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_position == null) {
      return Padding(
        padding: _margin,
        child: const Text(
          'FtzAutoNumber requires a "position" property.',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    return GetBuilder<WidgetUpdateController>(
      id: '${widget.scrName}-$_position',
      builder: (_) {
        final controller = txfController[widget.scrName]![_position]!;
        final hasValue = controller.finalData.isNotEmpty &&
            controller.finalData != emptyString;

        return Padding(
          padding: _margin,
          child: Row(
            children: [
              Text(
                _title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: _fontSize,
                ),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: TextFormField(
                  controller: controller.controller,
                  readOnly: true,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: _placeholder,
                    hintStyle: const TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: _fontSize,
                    color: hasValue ? _textColor : Colors.grey,
                    fontWeight: hasValue ? FontWeight.bold : FontWeight.normal,
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
