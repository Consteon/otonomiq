import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';

class StepperWidget extends StatefulWidget {
  const StepperWidget({
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
  final double lPad, tPad, rPad, bPad;

  @override
  State<StepperWidget> createState() => _StepperWidgetState();
}

class _StepperWidgetState extends State<StepperWidget>
    with SingleTickerProviderStateMixin {
  late String _variant;
  late String _label;
  late String _subtitle;
  late String _unit;
  late String _helperTemplate;
  late int _currentValue;
  late int _min;
  late int _max;
  late int _step;
  late bool _longPress;
  late int _stockAvailable;
  late int? _position;
  late List<double> _margin;

  Timer? _holdTimer;
  Timer? _accelTimer;
  bool _holding = false;
  int _holdDirection = 0;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _parseConfig();
    _initController();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _accelTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _parseConfig() {
    _variant =
        (widget.component['variant'] ?? 'default').toString().trim().toLowerCase();
    _margin = marginArray(widget.component['margin'] as String?);

    String rawText = autheniumDecode(widget.component['text'] ?? '') ?? '';
    List<String> segments = diamondTextToList(rawText);
    _label = segments.isNotEmpty ? segments[0] : '';
    _subtitle = segments.length > 1 ? segments[1] : '';
    _unit = segments.length > 2 ? segments[2] : '';
    _helperTemplate = segments.length > 3 ? segments[3] : '';

    _min = _parseInt(widget.component['min'], 0);
    _max = _parseInt(widget.component['max'], 99);
    _step = _parseInt(widget.component['step'], 1);
    if (_step < 1) _step = 1;

    int initial = int.tryParse(
        (widget.component['currentValue'] ?? '0').toString()) ??
        _min;
    _currentValue = initial.clamp(_min, _max);

    _longPress =
        (widget.component['longPress'] ?? 'FALSE').toString().toUpperCase() ==
            'TRUE';
    _stockAvailable = _parseInt(widget.component['stockAvailable'], 0);
    _position = widget.component['position'] is int
        ? widget.component['position']
        : int.tryParse((widget.component['position'] ?? '').toString());
  }

  int _parseInt(dynamic val, int fallback) {
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? fallback;
    return fallback;
  }

  void _initController() {
    if (_position == null) return;
    txfControllerCheck(widget.scrName, _position);
    final controller = txfController[widget.scrName]![_position]!;
    if (canInitializePage(widget.scrName)) {
      controller.controller.text = '$_currentValue';
      controller.finalData = '$_currentValue';
      controller.initialValue = '$_currentValue';
    } else {
      String existing = controller.finalData;
      if (existing.isNotEmpty &&
          existing != emptyString &&
          existing != 'null') {
        int? restored = int.tryParse(existing);
        if (restored != null) {
          _currentValue = restored.clamp(_min, _max);
        }
      }
    }
  }

  void _updateValue(int newValue) {
    int clamped = newValue.clamp(_min, _max);
    if (clamped == _currentValue) return;
    setState(() => _currentValue = clamped);
    _syncController();
    HapticFeedback.selectionClick();
  }

  void _syncController() {
    if (_position == null) return;
    txfControllerCheck(widget.scrName, _position);
    final controller = txfController[widget.scrName]![_position]!;
    controller.controller.text = '$_currentValue';
    controller.finalData = '$_currentValue';
  }

  void _onTap(int direction) {
    _updateValue(_currentValue + (direction * _step));
    _pulseController.forward(from: 0.0);
  }

  void _onLongPressStart(int direction) {
    if (!_longPress) return;
    _holding = true;
    _holdDirection = direction;
    _holdTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_holding) return;
      _accelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_holding) {
          timer.cancel();
          return;
        }
        int newVal = _currentValue + (_holdDirection * _step);
        if (newVal < _min || newVal > _max) {
          timer.cancel();
          _holding = false;
          return;
        }
        _updateValue(newVal);
        if (timer.tick > 15) {
          timer.cancel();
          _accelTimer =
              Timer.periodic(const Duration(milliseconds: 50), (fast) {
                if (!_holding) {
                  fast.cancel();
                  return;
                }
                int fVal = _currentValue + (_holdDirection * _step);
                if (fVal < _min || fVal > _max) {
                  fast.cancel();
                  _holding = false;
                  return;
                }
                _updateValue(fVal);
              });
        }
      });
    });
  }

  void _onLongPressEnd() {
    _holding = false;
    _holdTimer?.cancel();
    _accelTimer?.cancel();
  }

  String _resolveHelper() {
    if (_helperTemplate.isEmpty) return '';
    int remain = _stockAvailable - _currentValue;
    return _helperTemplate.replaceAll('<remain>', '$remain');
  }

  bool get _isCompact => _variant == 'compact';
  bool get _canDecrement => _currentValue > _min;
  bool get _canIncrement => _currentValue < _max;

  @override
  Widget build(BuildContext context) {
    if (_min > _max) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
        child: const Text('Invalid range',
            style: TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
      );
    }

    String helper = _resolveHelper();
    bool showHelper = helper.isNotEmpty && _stockAvailable > 0;

    return Container(
      margin: EdgeInsets.only(
        top: _margin[0],
        bottom: _margin[1],
        left: widget.lPad + _margin[2],
        right: widget.rPad + _margin[3],
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_isCompact ? 10 : 12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _isCompact ? 12 : 16,
          vertical: _isCompact ? 10 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _label,
                        style: TextStyle(
                          fontSize: _isCompact ? 14 : 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                          height: 1.3,
                        ),
                      ),
                      if (_subtitle.isNotEmpty) ...[
                        SizedBox(height: _isCompact ? 1 : 2),
                        Text(
                          _subtitle,
                          style: TextStyle(
                            fontSize: _isCompact ? 12 : 13,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF94A3B8),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildStepperControls(),
              ],
            ),
            if (showHelper) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  helper,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepperControls() {
    double btnSize = _isCompact ? 34 : 40;
    double valueWidth = _isCompact ? 44 : 52;
    double fontSize = _isCompact ? 15 : 17;
    double unitFontSize = _isCompact ? 11 : 12;
    double iconSize = _isCompact ? 18 : 20;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            icon: Icons.remove,
            enabled: _canDecrement,
            direction: -1,
            size: btnSize,
            iconSize: iconSize,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)),
          ),
          Container(
            width: _unit.isNotEmpty ? valueWidth + 20 : valueWidth,
            height: btnSize,
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            alignment: Alignment.center,
            child: _unit.isNotEmpty
                ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_currentValue',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  _unit,
                  style: TextStyle(
                    fontSize: unitFontSize,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            )
                : Text(
              '$_currentValue',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          _buildButton(
            icon: Icons.add,
            enabled: _canIncrement,
            direction: 1,
            size: btnSize,
            iconSize: iconSize,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required bool enabled,
    required int direction,
    required double size,
    required double iconSize,
    required BorderRadius borderRadius,
  }) {
    return GestureDetector(
      onTap: enabled ? () => _onTap(direction) : null,
      onLongPressStart:
      enabled && _longPress ? (_) => _onLongPressStart(direction) : null,
      onLongPressEnd:
      enabled && _longPress ? (_) => _onLongPressEnd() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF8FAFC),
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: iconSize,
          color: enabled ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}
