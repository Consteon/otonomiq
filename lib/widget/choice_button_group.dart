import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import "package:http/http.dart" as http;

import '../global.dart';

class ChoiceButtonGroup extends StatefulWidget {
  const ChoiceButtonGroup({
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
  State<ChoiceButtonGroup> createState() => _ChoiceButtonGroupState();
}

class _ChoiceButtonGroupState extends State<ChoiceButtonGroup> {
  String? _selectedValue;

  Color _colorFromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.amber;
      case 'red':
        return Colors.red;
      case 'neutral':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _iconFromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'check':
        return Icons.check_circle_outline;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'alert':
        return Icons.cancel_outlined;
      case 'siren':
        return Icons.campaign;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  dynamic _decodeChain(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        return jsonDecode(raw);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _handleChain(dynamic chainData, String route) async {
    if (chainData == null) {
      _navigate(route);
      return;
    }
    final type = chainData['type']?.toString().toLowerCase() ?? '';
    if (type == 'do_next') {
      _navigate(route);
    } else if (type == 'do_dialog') {
      await _showChainDialog(chainData, route);
    }
  }

  void _navigate(String route) {
    if (routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
  }

  Color _accentColor(String? iconStr) {
    switch (iconStr?.toLowerCase()) {
      case 'siren':
        return Colors.red;
      case 'warning':
        return Colors.amber;
      default:
        return Colors.amber;
    }
  }

  Widget _dialogIcon(String iconStr, Color accent) {
    if (iconStr.toLowerCase() == 'siren') {
      return const Center(child: Text('🚨', style: TextStyle(fontSize: 28)));
    }
    return Center(
        child: Icon(_iconFromString(iconStr), size: 30, color: accent));
  }

  Future<void> _showChainDialog(dynamic chainData, String originalRoute) async {
    final String title = chainData['title'] ?? '';
    final String description = chainData['description'] ?? '';
    final String iconStr = chainData['icon'] ?? '';
    final List<dynamic> buttons = chainData['buttons'] ?? [];
    final Color accent = _accentColor(iconStr);

    await Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _dialogIcon(iconStr, accent),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: buttons.map<Widget>((btn) {
                  final String rawText = btn['text']?.toString() ?? '';
                  final String displayText =
                      rawText.replaceAll('◆', ' ').trim();
                  final bool isNeutral =
                      (btn['color'] ?? '').toString().toLowerCase() ==
                          'neutral';
                  final Color btnColor = isNeutral
                      ? Colors.grey.shade400
                      : _colorFromString(btn['color']);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: btnColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          Get.back();
                          final String action =
                              (btn['action'] ?? '').toString().toLowerCase();
                          if (action == 'hitapi') await _hitApi(btn);
                          final dynamic next = _decodeChain(btn['next']);
                          if (next != null) {
                            final String nextType =
                                next['type']?.toString().toLowerCase() ?? '';
                            if (nextType == 'do_next') _navigate(originalRoute);
                          }
                        },
                        child: Text(
                          displayText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _hitApi(dynamic btn) async {
    final String? url = btn['apiUrl'];
    final String method = (btn['apiMethod'] ?? 'POST').toString().toUpperCase();
    final dynamic body = btn['apiBody'];
    if (url == null || url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      final headers = {'Content-Type': 'application/json'};
      final bodyStr = body != null ? jsonEncode(body) : '{}';
      if (method == 'POST') {
        await http.post(uri, headers: headers, body: bodyStr);
      } else if (method == 'GET') {
        await http.get(uri, headers: headers);
      }
    } catch (e) {
      debugPrint('[ChoiceButtonGroup] hitApi error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String label = widget.component['label'] as String? ?? '';
    final String badge = widget.component['labelBadge'] as String? ?? '';
    final List<dynamic> children =
        widget.component['children'] as List<dynamic>? ?? [];

    return Container(
      margin: EdgeInsets.only(
        top: (widget.component['beforeSpacing'] ?? 0.0).toDouble(),
        bottom: (widget.component['afterSpacing'] ?? 0.0).toDouble(),
      ),
      padding: EdgeInsets.fromLTRB(
        widget.lPad + (widget.component['leftPadding'] ?? 0.0).toDouble(),
        widget.tPad,
        widget.rPad + (widget.component['rightPadding'] ?? 0.0).toDouble(),
        widget.bPad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                if (badge.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final int perRow = children.length > 3 ? 3 : children.length;
              const double spacing = 8.0;
              final double btnWidth =
                  (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: children
                    .map<Widget>((child) => _buildChoiceButton(child, btnWidth))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceButton(dynamic buttonData, double width) {
    final String value = buttonData['value']?.toString() ?? '';
    final String textRaw = buttonData['text']?.toString() ?? '';
    final List<String> parts = textRaw.split('◆');
    final String labelText = parts.length > 1 ? parts[1] : parts[0];
    final Color baseColor = _colorFromString(buttonData['color']);
    final IconData iconData = _iconFromString(buttonData['icon']);
    final String route = buttonData['route']?.toString() ?? '';
    final bool isSelected = _selectedValue == value;
    final dynamic chainData = _decodeChain(buttonData['chain']);

    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () async {
          setState(() => _selectedValue = value);
          await _handleChain(chainData, route);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? baseColor : baseColor.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? baseColor : baseColor.withValues(alpha: 0.6),
              width: isSelected ? 2.5 : 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconData,
                  size: 36, color: isSelected ? Colors.white : baseColor),
              const SizedBox(height: 8),
              Text(
                labelText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : baseColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
