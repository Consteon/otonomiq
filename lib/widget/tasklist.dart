import 'package:flutter/material.dart';

import '../api.dart';
import '../global.dart';
import '../global2.dart';
import 'task_progress_store.dart';

class Tasklist extends StatefulWidget {
  const Tasklist({
    required Key key,
    required this.component,
    required this.scrName,
    required this.single,
    required this.lPad,
    required this.rPad,
  }) : super(key: key);
  final String scrName;
  final dynamic component;
  final bool single;
  final double lPad;
  final double rPad;

  @override
  State<Tasklist> createState() => _TasklistState();
}

class _TasklistState extends State<Tasklist> {
  late List<String> _texts;
  late List<_OptionConfig> _options;
  late double _borderRadius;
  late List<double> _margin;
  late String _category;
  late int _position;
  late String _pendingLabel;
  String _status = 'pending';
  DateTime? _completedAt;

  static const List<String> _statusKeys = [
    'done',
    'not_available',
    'skipped',
    'issue',
  ];

  @override
  void initState() {
    super.initState();
    _texts = diamondTextToList(widget.component['text'] as String? ?? '');
    _borderRadius =
        (widget.component['borderRadius'] as num?)?.toDouble() ?? 10;
    _margin = marginArray(widget.component['margin'] as String?);
    _category = widget.component['category'] as String? ?? '';
    _position = (widget.component['position'] as num?)?.toInt() ?? 0;
    _pendingLabel =
    (widget.component['pendingLabel'] as String?)?.trim().isNotEmpty == true
        ? widget.component['pendingLabel'] as String
        : 'belum';
    if (_position > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          TaskProgressStore.instance.register(widget.scrName, _position);
        }
      });
      txfControllerCheck(widget.scrName, _position);
      if (canInitializePage(widget.scrName)) {
        final initial = _serialize(_pendingLabel);
        final input = txfController[widget.scrName]![_position]!;
        input.controller.text = initial;
        input.finalData = initial;
        input.initialValue = initial;
      }
    }

    final rawOptions = widget.component['options'] as String? ?? '';
    final parts = diamondTextToList(rawOptions);
    _options = [];
    for (int i = 0; i + 2 < parts.length; i += 3) {
      _options.add(_OptionConfig(
        icon: parts[i],
        label: parts[i + 1],
        description: parts[i + 2],
      ));
    }
  }

  String _serialize(String label) {
    final title = _texts.isNotEmpty ? _texts[0] : '';
    return '$title:$label';
  }

  void _updateStore(String status) {
    if (_position > 0) {
      TaskProgressStore.instance.update(widget.scrName, _position, status);
      final label = status == 'pending'
          ? _pendingLabel
          : _statusConfigForKey(status).label;
      final value = _serialize(label);
      txfControllerCheck(widget.scrName, _position);
      final input = txfController[widget.scrName]![_position]!;
      input.controller.text = value;
      input.finalData = value;
    }
  }

  _StatusConfig _statusConfigForKey(String key) {
    switch (key) {
      case 'done':
        return _StatusConfig(
          color: const Color(0xFF22C55E),
          label: _options.isNotEmpty ? _options[0].label : 'Done',
        );
      case 'not_available':
        return _StatusConfig(
          color: const Color(0xFF9CA3AF),
          label: _options.length > 1 ? _options[1].label : 'Not Available',
        );
      case 'skipped':
        return _StatusConfig(
          color: const Color(0xFFF59E0B),
          label: _options.length > 2 ? _options[2].label : 'Skipped',
        );
      case 'issue':
        return _StatusConfig(
          color: const Color(0xFFEF4444),
          label: _options.length > 3 ? _options[3].label : 'Issue',
        );
      default:
        return const _StatusConfig(color: Color(0xFFD1D5DB), label: '');
    }
  }

  void _toggleDone() {
    final newStatus = _status == 'done' ? 'pending' : 'done';
    setState(() {
      _status = newStatus;
      _completedAt = newStatus == 'done' ? DateTime.now() : null;
    });
    _updateStore(newStatus);
  }

  @override
  void dispose() {
    if (_position > 0) {
      TaskProgressStore.instance.unregister(widget.scrName, _position);
    }
    super.dispose();
  }

  void _showStatusSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _StatusSheet(
        options: _options,
        statusKeys: _statusKeys,
        currentStatus: _status,
        onSelect: (newStatus) {
          setState(() {
            _status = newStatus;
            if (newStatus == 'done') _completedAt = DateTime.now();
          });
          _updateStore(newStatus);
          Navigator.pop(context);
        },
      ),
    );
  }

  _StatusConfig _statusConfig() => _statusConfigForKey(_status);

  String get _completedAtLabel {
    if (_completedAt == null) return '';
    final h = _completedAt!.hour.toString().padLeft(2, '0');
    final m = _completedAt!.minute.toString().padLeft(2, '0');
    final prefix = _texts.length > 1 ? _texts[1] : 'Completed at';
    return '$prefix $h:$m';
  }

  String? get _subtitleText {
    switch (_status) {
      case 'not_available':
        return _texts.length > 2 ? _texts[2] : null;
      case 'skipped':
        return _texts.length > 3 ? _texts[3] : null;
      case 'issue':
        return _texts.length > 4 ? _texts[4] : null;
      default:
        return null;
    }
  }

  IconData? get _circleIcon {
    switch (_status) {
      case 'done':
        return Icons.check;
      case 'not_available':
        return Icons.close;
      case 'skipped':
        return Icons.chevron_right;
      case 'issue':
        return Icons.priority_high;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _statusConfig();
    final isActive = _status != 'pending';
    final isDone = _status == 'done';
    final taskName = _texts.isNotEmpty ? _texts[0] : '';

    return Padding(
      padding: EdgeInsets.only(top: _margin[0], bottom: _margin[1], left: widget.lPad + _margin[2], right: widget.rPad + _margin[3]),
      child: GestureDetector(
        onTap: _showStatusSheet,
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? config.color.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(_borderRadius),
            border: Border.all(
              color: isActive
                  ? config.color.withValues(alpha: 0.4)
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circle toggle
              GestureDetector(
                onTap: _toggleDone,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? config.color : Colors.transparent,
                    border: Border.all(
                      color: isActive ? config.color : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                  ),
                  child: _circleIcon != null
                      ? Icon(_circleIcon, size: 14, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              // Category badge + task name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_category.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xff3b82f6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _category,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xff3b82f6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      taskName,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDone
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF374151),
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: const Color(0xFF9CA3AF),
                      ),
                    ),
                    if (isDone && _completedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _completedAtLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                    if (_subtitleText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _subtitleText!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status badge + ... button (vertically centered)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive) ...[
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: config.color.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        config.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: config.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  GestureDetector(
                    onTap: _showStatusSheet,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.more_horiz,
                        size: 16,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusSheet extends StatelessWidget {
  final List<_OptionConfig> options;
  final List<String> statusKeys;
  final String currentStatus;
  final void Function(String) onSelect;

  const _StatusSheet({
    required this.options,
    required this.statusKeys,
    required this.currentStatus,
    required this.onSelect,
  });

  Color _colorFor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFF22C55E);
      case 1:
        return const Color(0xFF9CA3AF);
      case 2:
        return const Color(0xFFF59E0B);
      case 3:
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Change Status',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              ),
            ),
            Divider(),
            ...List.generate(options.length, (i) {
              if (i >= statusKeys.length) return const SizedBox.shrink();
              final opt = options[i];
              final key = statusKeys[i];
              final color = _colorFor(i);
              final isSelected = currentStatus == key;
              return InkWell(
                onTap: () => onSelect(key),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: isSelected
                      ? BoxDecoration(
                    color: color.withValues(alpha: 0.05),
                    border:
                    Border.all(color: color.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  )
                      : null,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            opt.icon,
                            style: TextStyle(
                              fontSize: 16,
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                            Text(
                              opt.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, color: color, size: 20),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _OptionConfig {
  final String icon;
  final String label;
  final String description;

  const _OptionConfig({
    required this.icon,
    required this.label,
    required this.description,
  });
}

class _StatusConfig {
  final Color color;
  final String label;

  const _StatusConfig({required this.color, required this.label});
}
