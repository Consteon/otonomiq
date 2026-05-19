import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';

class WorkerCardDetail extends StatefulWidget {
  const WorkerCardDetail({
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
  State<WorkerCardDetail> createState() => _WorkerCardDetailState();
}

class _WorkerCardDetailState extends State<WorkerCardDetail> {
  String _tableCode = '';
  List<String> _textArray = [];

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribeTable();
  }

  void _initConfig() {
    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }
  }

  void _subscribeTable() {
    String rawTable = (widget.component['table'] ?? '').toString().trim();
    String decoded = autheniumDecode(rawTable) ?? rawTable;
    _tableCode = normalizeTableName(decoded);
    int tableVid =
        int.tryParse((widget.component['vidtable'] ?? '').toString()) ??
            appCodeController.applicationTableVid;
    if (_tableCode.isNotEmpty) {
      tableSourceUpdated[_tableCode] = true;
      subscribeToTable(_tableCode, tableVid);
    }
  }

  String _resolveNamedMarkers(String text) {
    var screenTx = transactionStore.state.screenTx;
    return text.replaceAllMapped(RegExp(r'<([a-zA-Z_][a-zA-Z0-9_]*)>'), (m) {
      String key = m.group(1)!;
      return screenTx[key]?.toString() ?? m.group(0)!;
    });
  }

  String _resolveText(String template, List<dynamic> row) {
    return replaceMarker(
        template, row, widget.component['indexStart'] ?? 1, false);
  }

  List<dynamic> _applyConditions(List<dynamic> data) {
    String condRaw = (widget.component['conditions'] ?? '').toString().trim();
    String condStr = autheniumDecode(condRaw) ?? condRaw;
    condStr = _resolveNamedMarkers(condStr);
    if (condStr.isEmpty) return data;

    try {
      String inner = condStr;
      if (inner.startsWith('[')) inner = inner.substring(1);
      if (inner.endsWith(']')) inner = inner.substring(0, inner.length - 1);

      List<String> groupStrs = inner.split(RegExp(r'\]\s*,\s*\['));
      List<Map<int, String>> groups = [];

      for (var groupStr in groupStrs) {
        groupStr = groupStr.replaceAll('[', '').replaceAll(']', '').trim();
        Map<int, String> fieldConds = {};
        RegExp fieldPattern = RegExp(r'◀(\d+)▶◼([^◁◀]+)');
        for (var match in fieldPattern.allMatches(groupStr)) {
          int idx = int.parse(match.group(1)!);
          String val = match.group(2)!.trim();
          if (val.endsWith(',')) val = val.substring(0, val.length - 1).trim();
          fieldConds[idx] = val;
        }
        if (fieldConds.isNotEmpty) groups.add(fieldConds);
      }

      if (groups.isEmpty) return data;

      return data.where((row) {
        for (var group in groups) {
          bool match = true;
          for (var entry in group.entries) {
            if (entry.key < row.length) {
              if (row[entry.key].toString().trim() != entry.value) {
                match = false;
                break;
              }
            } else {
              match = false;
              break;
            }
          }
          if (match) return true;
        }
        return false;
      }).toList();
    } catch (_) {
      return data;
    }
  }

  String _getInitials(String name) {
    List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      List<dynamic> allData = List.from(tableContent[_tableCode] ?? []);
      String condRaw = (widget.component['conditions'] ?? '').toString();
      debugPrint(
          '[WorkerCardDetail] tableCode=$_tableCode | rows=${allData.length} | conditions=$condRaw');
      allData = _applyConditions(allData);
      debugPrint('[WorkerCardDetail] after conditions: ${allData.length} rows');

      if (allData.isEmpty) return const SizedBox.shrink();

      var row = allData[0];
      String name =
      _textArray.length > 1 ? _resolveText(_textArray[1], row) : '';
      String subtitle =
      _textArray.length > 2 ? _resolveText(_textArray[2], row) : '';
      subtitle = subtitle.replaceAll(' . ', ' · ');

      return Padding(
        padding: EdgeInsets.fromLTRB(
            widget.lPad, widget.tPad, widget.rPad, widget.bPad),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE0E7FF),
                child: Text(
                  _getInitials(name),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
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
    });
  }
}
