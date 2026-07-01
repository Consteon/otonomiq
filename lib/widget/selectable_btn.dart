import 'package:flutter/material.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import '../otq_icons.dart';

class SelectableBtn extends StatefulWidget {
  const SelectableBtn({
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
  State<SelectableBtn> createState() => _SelectableBtnState();
}

class _SelectableBtnState extends State<SelectableBtn> {
  late String _variant;
  late String _title;
  late double _btnHeight;
  late int _maxGrid;
  late int? _position;
  late Color _selectedColor;
  late List<double> _margin;
  late String _iconKey;
  int _selectedIndex = -1;

  late String _mode;
  final List<String> _routeList = [];
  final List<String> _iconList = [];

  // Grid variant: label + optional icon
  final List<_GridOption> _gridOptions = [];

  // Vertical variant: structured options with label, description, color
  final List<_VerticalOption> _verticalOptions = [];

  @override
  void initState() {
    super.initState();
    _variant =
        (widget.component['variant'] as String?)?.toLowerCase() ?? 'grid';
    _title = (widget.component['title'] as String?) ?? '';
    _btnHeight = (widget.component['height'] as num?)?.toDouble() ?? 48;
    _maxGrid = (widget.component['maxGrid'] as num?)?.toInt() ?? 2;
    _position = widget.component['position'] as int?;
    _selectedColor = _parseColor(
      widget.component['bgSelected'] as String? ?? 'gray',
    );
    _margin = marginArray(widget.component['margin'] as String?);
    _iconKey = (widget.component['icon'] ?? '').toString().trim();

    _parseOptions();
    _mode = (widget.component['mode'] ?? '').toString().trim().toLowerCase();
    _parseLauncherConfig();
    _initController();
  }

  void _parseOptions() {
    String rawText = autheniumDecode(widget.component['text'] ?? '') ?? '';
    final rawParts = diamondTextToList(rawText);
    if (_variant == 'vertical') {
      for (final part in rawParts) {
        final segments = part.split('◇');
        _verticalOptions.add(
          _VerticalOption(
            label: segments.isNotEmpty ? segments[0].trim() : '',
            description: segments.length > 1 ? segments[1].trim() : '',
            color: segments.length > 2
                ? _parseColor(segments[2].trim())
                : _selectedColor,
          ),
        );
      }
    } else {
      for (final part in rawParts) {
        final segments = part.split('◇');
        _gridOptions.add(
          _GridOption(
            label: segments.isNotEmpty ? segments[0].trim() : '',
            icon: segments.length > 1 ? segments[1].trim() : '',
          ),
        );
      }
    }
  }

  void _parseLauncherConfig() {
    if (_mode != 'launch') return;
    // Parse routes (diamond-separated, index-aligned with text)
    final String rawRoutes =
        autheniumDecode(widget.component['routes'] ?? '') ?? '';
    if (rawRoutes.isNotEmpty) {
      _routeList.addAll(diamondTextToList(rawRoutes));
    }
    // Parse icons (diamond-separated, index-aligned with text)
    // Per dev-spec section-4.1: icons:"emoji1◆emoji2◆emoji3"
    final String rawIcons =
        autheniumDecode(widget.component['icons'] ?? '') ?? '';
    if (rawIcons.isNotEmpty) {
      _iconList.addAll(diamondTextToList(rawIcons));
    }
  }

  void _initController() {
    if (_mode == 'launch') return; // launcher mode does not use txfController
    if (_position == null) return;
    txfControllerCheck(widget.scrName, _position);
    if (canInitializePage(widget.scrName)) {
      final controller = txfController[widget.scrName]![_position]!;
      controller.controller.text = '';
      controller.finalData = '';
      controller.initialValue = '';
    } else {
      final controller = txfController[widget.scrName]![_position]!;
      final existing = controller.finalData;
      if (existing.isNotEmpty &&
          existing != emptyString &&
          existing != 'null') {
        final labels = _variant == 'vertical'
            ? _verticalOptions.map((o) => o.label).toList()
            : _gridOptions.map((o) => o.label).toList();
        final idx = labels.indexOf(existing);
        if (idx >= 0) _selectedIndex = idx;
      }
    }
  }

  Color _parseColor(String color) {
    switch (color.toLowerCase()) {
      case 'blue':
        return const Color(0xFF3B82F6);
      case 'green':
        return const Color(0xFF16A34A);
      case 'red':
        return const Color(0xFFDC2626);
      case 'orange':
        return const Color(0xFFF97316);
      case 'purple':
        return const Color(0xFF7C3AED);
      case 'gray':
      default:
        return const Color(0xFF475569);
    }
  }

  void _onSelect(int index) {
    setState(() {
      _selectedIndex = _selectedIndex == index ? -1 : index;
    });

    if (_position != null) {
      txfControllerCheck(widget.scrName, _position);
      final controller = txfController[widget.scrName]![_position]!;
      String value = '';
      if (_selectedIndex >= 0) {
        value = _variant == 'vertical'
            ? _verticalOptions[_selectedIndex].label
            : _gridOptions[_selectedIndex].label;
      }
      controller.controller.text = value;
      controller.finalData = value;
    }
  }

  void _onLaunch(int index) {
    // Length-guard: routes array may be shorter than text array
    if (_routeList.length <= index) return;
    final String route = _routeList[index].trim();
    if (route.isEmpty) return;
    // Dead-route guard
    if (!routeExist(route)) return;
    routeStack.push(route);
    gotoRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: _margin[0],
        bottom: _margin[1],
        left: widget.lPad + _margin[2],
        right: widget.rPad + _margin[3],
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
          if (_title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  if (_iconKey.isNotEmpty && otqIcons[_iconKey] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        otqIcons[_iconKey] as IconData,
                        size: 14,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (_mode != 'launch')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFFECACA),
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        'wajib',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _variant == 'vertical' ? _buildVerticalList() : _buildGrid(),
          ),
        ],
      ),
    );
  }

  // ── Grid variant ──

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final btnWidth =
            (constraints.maxWidth - spacing * (_maxGrid - 1)) / _maxGrid;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(_gridOptions.length, (i) {
            return _buildGridButton(i, btnWidth);
          }),
        );
      },
    );
  }

  Widget _buildGridButton(int index, double width) {
    final bool isSelected = _mode != 'launch' && _selectedIndex == index;
    final option = _gridOptions[index];
    // In launcher mode, prefer the dedicated icons config (index-aligned).
    // Fall back to inline icon from the text◇iconKey format.
    // Length-guard: _iconList may be shorter than _gridOptions.
    final String resolvedIconKey =
        (_mode == 'launch' &&
            _iconList.length > index &&
            _iconList[index].trim().isNotEmpty)
        ? _iconList[index].trim()
        : option.icon;
    final bool hasIcon = resolvedIconKey.isNotEmpty;
    final IconData? iconData = hasIcon
        ? otqIcons[resolvedIconKey] as IconData?
        : null;

    return GestureDetector(
      onTap: () => _mode == 'launch' ? _onLaunch(index) : _onSelect(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: width,
        height: _btnHeight,
        decoration: BoxDecoration(
          color: isSelected
              ? _selectedColor.withValues(alpha: 0.08)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _selectedColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _selectedColor.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: iconData != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _selectedColor.withValues(alpha: 0.12)
                          : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      iconData,
                      size: 22,
                      color: isSelected
                          ? _selectedColor
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      option.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? _selectedColor
                            : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 4),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: _selectedColor,
                    ),
                  ],
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: _selectedColor,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      option.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? _selectedColor
                            : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Vertical variant ──

  Widget _buildVerticalList() {
    return Column(
      children: List.generate(_verticalOptions.length, (i) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: i < _verticalOptions.length - 1 ? 8 : 0,
          ),
          child: _buildVerticalItem(i),
        );
      }),
    );
  }

  Widget _buildVerticalItem(int index) {
    final option = _verticalOptions[index];
    final bool isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onSelect(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: _btnHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? option.color.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? option.color.withValues(alpha: 0.5)
                : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: option.color.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Colored dot indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 14 : 10,
              height: isSelected ? 14 : 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? option.color
                    : option.color.withValues(alpha: 0.5),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: option.color.withValues(alpha: 0.3),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected
                          ? option.color
                          : const Color(0xFF334155),
                    ),
                  ),
                  if (option.description.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      option.description,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: isSelected
                            ? option.color.withValues(alpha: 0.7)
                            : const Color(0xFF94A3B8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Check indicator
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: isSelected ? 1.0 : 0.0,
              child: Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: option.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridOption {
  final String label;
  final String icon;

  const _GridOption({required this.label, required this.icon});
}

class _VerticalOption {
  final String label;
  final String description;
  final Color color;

  const _VerticalOption({
    required this.label,
    required this.description,
    required this.color,
  });
}
