import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../redux/screen_transaction.dart';
import 'do_chain.dart';

class ListItemCard extends StatefulWidget {
  const ListItemCard({
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
  State<ListItemCard> createState() => _ListItemCardState();
}

class _ListItemCardState extends State<ListItemCard> {
  int _selectedTabIndex = 0;
  List<String> _tabs = [];
  List<String> _textArray = [];
  int _statusFieldIndex = 2;
  String _tableCode = '';
  String _role = '';
  int _myApprovalLevel = -1;
  final Map<int, String> _fieldConditions = {};
  final Map<int, String> _searchFilters = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _showIcon = true;
  bool _showProgress = true;

  @override
  void initState() {
    super.initState();
    _initConfig();
    _subscribeTable();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initConfig() {
    String todoStr = (widget.component['toDo'] ?? '').toString();
    todoStr = todoStr.replaceAll('[', '').replaceAll(']', '').trim();
    _tabs = todoStr
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      _textArray = diamondTextToList(widget.component['text'] ?? '');
    } catch (_) {
      _textArray = [];
    }

    _role = (widget.component['role'] ?? '').toString().trim().toUpperCase();

    String searchRaw = (widget.component['search'] ?? '').toString();
    String search = autheniumDecode(searchRaw) ?? searchRaw;
    for (var part in search.split('⭘')) {
      List<String> kv = part.split('◼');
      if (kv.length >= 2) {
        int? idx = int.tryParse(kv[0].trim());
        String val = kv[1].trim();
        if (idx != null) {
          if (_tabs.any((t) => t.toUpperCase() == val.toUpperCase())) {
            _statusFieldIndex = idx;
          } else {
            _searchFilters[idx] = val;
          }
        }
      }
    }
    _showIcon =
        (widget.component['showIcon'] ?? '').toString().toUpperCase() !=
        'FALSE';
    _showProgress =
        (widget.component['showProgress'] ?? '').toString().toUpperCase() !=
        'FALSE';

    if (_role == 'APPROVER') {
      String condRaw = (widget.component['conditions'] ?? '').toString().trim();
      String condStr = autheniumDecode(condRaw) ?? condRaw;

      RegExp fieldPattern = RegExp(r'◀(\d+)▶◼([^◁◀]+)');
      for (var match in fieldPattern.allMatches(condStr)) {
        int idx = int.parse(match.group(1)!);
        String val = match.group(2)!.trim();
        if (val.endsWith(',')) val = val.substring(0, val.length - 1).trim();
        _fieldConditions[idx] = val;
      }

      RegExp stepPattern = RegExp(r'◁(\d+)▷◼([^◁◀,\]]+)');
      for (var match in stepPattern.allMatches(condStr)) {
        int step = int.parse(match.group(1)!);
        String val = match.group(2)!.trim().toUpperCase();
        if (_tabs.isNotEmpty && val == _tabs[0].toUpperCase()) {
          _myApprovalLevel = step;
          break;
        }
      }
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

  String _resolveText(String template, List<dynamic> row) {
    return replaceMarker(
      template,
      row,
      widget.component['indexStart'] ?? 1,
      false,
    );
  }

  String _getStatus(List<dynamic> row) {
    String statusTemplate = (widget.component['status'] ?? '').toString();
    if (statusTemplate.isNotEmpty) {
      return _resolveText(statusTemplate, row).trim().toUpperCase();
    }
    if (_statusFieldIndex >= 0 && _statusFieldIndex < row.length) {
      return row[_statusFieldIndex].toString().trim().toUpperCase();
    }
    return '';
  }

  String _getChainStatus(List<dynamic> row) {
    if (_myApprovalLevel <= 0) return _getStatus(row);
    Map<int, String> chain = _parseApprovalChain(row);
    return chain[_myApprovalLevel] ?? _getStatus(row);
  }

  String _getChainProgress(List<dynamic> row) {
    if (_tabs.length < 2) return '';
    Map<int, String> chain = _parseApprovalChain(row);
    if (chain.isEmpty) return '';
    String continueStatus = _tabs[1].toUpperCase();
    int done = chain.values.where((s) => s == continueStatus).length;
    return '($done/${chain.length})';
  }

  List<dynamic> _applySearchFilter(List<dynamic> data) {
    if (_searchFilters.isEmpty) return data;
    return data.where((row) {
      for (var entry in _searchFilters.entries) {
        if (entry.key >= row.length) return false;
        if (row[entry.key].toString().trim() != entry.value) return false;
      }
      return true;
    }).toList();
  }

  Map<int, String> _parseApprovalChain(List<dynamic> row) {
    Map<int, String> steps = {};
    for (var field in row) {
      String s = field.toString().trim();
      if (s.startsWith('[[') && s.contains(',')) {
        try {
          String inner = s.substring(1, s.length - 1);
          for (var stepStr in inner.split(RegExp(r'\]\s*,\s*\['))) {
            stepStr = stepStr.replaceAll('[', '').replaceAll(']', '').trim();
            List<String> parts = stepStr
                .split(',')
                .map((e) => e.trim())
                .toList();
            if (parts.length >= 2) {
              int? stepNum = int.tryParse(parts[0]);
              String status = parts[1].trim();
              if (stepNum != null && status.isNotEmpty) {
                steps[stepNum] = status.toUpperCase();
              }
            }
          }
        } catch (_) {}
        break;
      }
    }
    return steps;
  }

  List<dynamic> _applyFieldConditions(List<dynamic> data) {
    if (_fieldConditions.isEmpty) return data;
    return data.where((row) {
      for (var entry in _fieldConditions.entries) {
        if (entry.key >= row.length) return false;
        if (row[entry.key].toString().trim() != entry.value) return false;
      }
      return true;
    }).toList();
  }

  List<dynamic> _applyApproverTabFilter(List<dynamic> data, String tabStatus) {
    if (_myApprovalLevel <= 0 || _tabs.isEmpty) return data;
    final String defaultStatus = _tabs[0].toUpperCase();
    final String continueStatus = _tabs.length > 1
        ? _tabs[1].toUpperCase()
        : '';
    return data.where((row) {
      Map<int, String> chain = _parseApprovalChain(row);
      if (tabStatus == defaultStatus) {
        for (int i = 1; i < _myApprovalLevel; i++) {
          if ((chain[i] ?? '') != continueStatus) return false;
        }
        return (chain[_myApprovalLevel] ?? '') == defaultStatus;
      }
      return (chain[_myApprovalLevel] ?? '') == tabStatus;
    }).toList();
  }

  static Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
      case 'MENUNGGU':
        return const Color(0xFFE8910C);
      case 'APPROVED':
      case 'SELESAI':
        return const Color(0xFF16A34A);
      case 'REJECTED':
      case 'DITUTUP':
        return const Color(0xFFDC2626);
      case 'DITINJAU':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF6B7280);
    }
  }

  static Color _statusBgColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
      case 'MENUNGGU':
        return const Color(0xFFFEF3C7);
      case 'APPROVED':
      case 'SELESAI':
        return const Color(0xFFDCFCE7);
      case 'REJECTED':
      case 'DITUTUP':
        return const Color(0xFFFEE2E2);
      case 'DITINJAU':
        return const Color(0xFFDBEAFE);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static Color _priorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'KRITIS':
        return const Color(0xFFDC2626);
      case 'TINGGI':
        return const Color(0xFFEA580C);
      case 'SEDANG':
        return const Color(0xFFE8910C);
      case 'RENDAH':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFF6B7280);
    }
  }

  static Color _priorityBgColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'KRITIS':
        return const Color(0xFFFEE2E2);
      case 'TINGGI':
        return const Color(0xFFFFF7ED);
      case 'SEDANG':
        return const Color(0xFFFEF3C7);
      case 'RENDAH':
        return const Color(0xFFDCFCE7);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static IconData _typeIcon(String text) {
    String s = text.toLowerCase();
    if (s.contains('permission') ||
        s.contains('izin') ||
        s.contains('leave') ||
        s.contains('cuti')) {
      return Icons.access_time_rounded;
    }
    if (s.contains('time correction') || s.contains('koreksi waktu')) {
      return Icons.history_rounded;
    }
    if (s.contains('attendance') || s.contains('kehadiran')) {
      return Icons.edit_note_rounded;
    }
    if (s.contains('sick') || s.contains('sakit')) {
      return Icons.medical_services_outlined;
    }
    if (s.contains('swap') || s.contains('tukar')) {
      return Icons.swap_horiz_rounded;
    }
    if (s.contains('overtime') || s.contains('lembur')) {
      return Icons.more_time_rounded;
    }
    return Icons.description_outlined;
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  void _onCardTap(List<dynamic> row) {
    String noRequest = row.length > 1 ? row[1].toString() : '';
    String requestVid = row.length > 1 ? row[1].toString() : '';
    String requestDocT = row.isNotEmpty ? row[0].toString() : '';
    String status = _getStatus(row);
    if (noRequest.isNotEmpty) {
      transactionStore.dispatch(
        UpdateScreenTxAction(
          ScreenTransaction({
            'no_request': noRequest,
            'request_vid': requestVid,
            'request_doc_t': requestDocT,
            'approval_status': status,
            'approval_role': _role,
            'approval_tabs': _tabs,
            'approval_level': _myApprovalLevel,
            'approval_buttons': widget.component['buttons'],
            'approval_table': widget.component['table'],
            'approval_vidtable': widget.component['vidtable'],
            'approval_flag': widget.component['flag'],
            'approval_status_field': _statusFieldIndex,
          }),
        ),
      );
    }

    String route = (widget.component['route'] ?? '').toString();
    if (route.isNotEmpty && routeExist(route)) {
      routeStack.push(route);
      gotoRoute(route);
    }
  }

  void _onActionPressed(
    List<dynamic> row,
    Map<String, dynamic> buttonConfig,
  ) async {
    try {
      String rawActions = (buttonConfig['actions'] ?? '').toString();
      String actionsStr = autheniumDecode(rawActions) ?? rawActions;
      if (actionsStr.isNotEmpty) {
        // 1. Auto-detect chain column (field starting with '[[')
        int chainColIdx = -1;
        String chainStr = '';
        for (int i = 0; i < row.length; i++) {
          String s = row[i].toString().trim();
          if (s.startsWith('[[') && s.contains(',')) {
            chainColIdx = i;
            chainStr = s;
            break;
          }
        }

        if (chainColIdx >= 0) {
          // 2. Parse chain into step entries
          String inner = chainStr.substring(1, chainStr.length - 1);
          List<List<String>> steps = [];
          for (var stepStr in inner.split(RegExp(r'\]\s*,\s*\['))) {
            stepStr = stepStr.replaceAll('[', '').replaceAll(']', '').trim();
            steps.add(stepStr.split(',').map((e) => e.trim()).toList());
          }

          // 3. Find step with default status
          String defaultStatus = _tabs.isNotEmpty
              ? _tabs[0].toUpperCase()
              : 'PENDING';
          int targetIdx = steps.indexWhere(
            (s) => s.length > 1 && s[1].toUpperCase() == defaultStatus,
          );

          if (targetIdx >= 0) {
            // 4. Apply actions template to step (markers stay intact for backend resolution)
            List<String> newStep = List<String>.from(steps[targetIdx]);
            for (var part in actionsStr.split('⭘')) {
              List<String> kv = part.split('◼');
              if (kv.length < 2) continue;
              String key = kv[0].trim();
              String value = kv.sublist(1).join('◼').trim();
              if (key.startsWith('<') && key.endsWith('>')) {
                try {
                  int pos = int.parse(key.substring(1, key.length - 1)) - 1;
                  while (newStep.length <= pos) {
                    newStep.add('');
                  }
                  newStep[pos] = value;
                } catch (_) {}
              }
            }
            steps[targetIdx] = newStep;

            // 5. Re-encode chain
            String newChainStr =
                '[${steps.map((s) => '[${s.join(', ')}]').join(', ')}]';

            // 5b. Determine action status and whether to update overall status (field 2)
            String actionStatus = newStep.length > 1
                ? newStep[1].trim().toUpperCase()
                : '';
            String continueStatus = _tabs.length > 1
                ? _tabs[1].toUpperCase()
                : '';
            bool isLastLevel =
                _myApprovalLevel > 0 && _myApprovalLevel == steps.length;
            bool updateOverallStatus =
                isLastLevel || actionStatus != continueStatus;

            debugPrint(
              '[Approval] actionStatus=$actionStatus | myLevel=$_myApprovalLevel | totalSteps=${steps.length} | isLastLevel=$isLastLevel | updateOverall=$updateOverallStatus',
            );

            // 6. Build updateTableRow input: search by field "1" (no_request)
            String tableRaw = (widget.component['table'] ?? '').toString();
            String vid = (widget.component['vidtable'] ?? '').toString();
            String noRequest = row.length > 1 ? row[1].toString() : '';
            int chainPos = chainColIdx;

            String input =
                '$tableRaw⭘tablevid◼$vid⭘search◼1${separator[3]}$noRequest⭘<$chainPos>◼$newChainStr';

            if (updateOverallStatus) {
              input += '⭘<$_statusFieldIndex>◼$actionStatus';
              debugPrint(
                '[Approval] updating overall status field $_statusFieldIndex → $actionStatus',
              );
            }

            // 7. Build event row JSON
            // ref[0] structure (after parseEventString):
            //   [0] = "②{nowMs}"  (prefix-tagged action timestamp)
            //   [1] = scrName
            //   [2] = row[1]  (no_request)
            //   [3] = row[2]  (overall status)
            //   [4] = nowMs   ← ref[0][4] = action timestamp ms (for ◀5▶ marker)
            //   [5..] = row[3..] (rest of content)
            int nowMs = DateTime.now().millisecondsSinceEpoch;
            List<String> contentParts = [
              '${separator[7]}$nowMs',
              widget.scrName,
              row.length > 1 ? row[1].toString() : '',
              row.length > 2 ? row[2].toString() : '',
              '$nowMs',
            ];
            for (int i = 3; i < row.length; i++) {
              contentParts.add(row[i].toString());
            }
            String eventContent = '0${contentParts.join(separator[1])}';
            String eventRowString = jsonEncode([
              nowMs,
              widget.scrName,
              eventContent,
            ]);

            debugPrint('[Approval] action input: $input');
            debugPrint('[Approval] event row: $eventRowString');
            List<String> result = await updateTableRow(input, eventRowString);
            debugPrint('[Approval] updateTableRow result: $result');

            // Create Event C via DSL if button has 'event' property
            String eventDSL = (buttonConfig['event'] ?? '').toString();
            if (eventDSL.isNotEmpty &&
                result.isNotEmpty &&
                result[0].startsWith('OK')) {
              String eventFlag = (widget.component['flag'] ?? '').toString();
              int appVid = defaultVid();
              String vidTable = (widget.component['vidtable'] ?? '').toString();
              if (vidTable.isNotEmpty) {
                appVid = int.tryParse(vidTable) ?? defaultVid();
              }

              List<dynamic> updatedRow = List.from(row);
              // Resolve ◀...▶ markers in chain for event DSL
              final openM = forbiddenCharacter[7];
              final closeM = forbiddenCharacter[9];
              String formattedNow = DateFormat(
                'dd MMM yyyy HH:mm',
              ).format(DateTime.fromMillisecondsSinceEpoch(nowMs));
              String resolvedChain = newChainStr;
              int mPos = 0;
              while (mPos < resolvedChain.length) {
                int start = resolvedChain.indexOf('${openM}5|', mPos);
                if (start < 0) break;
                int end = resolvedChain.indexOf(closeM, start);
                if (end < 0) break;
                resolvedChain =
                    resolvedChain.substring(0, start) +
                    formattedNow +
                    resolvedChain.substring(end + 1);
                mPos = start + formattedNow.length;
              }
              resolvedChain = resolvedChain.replaceAll(
                '${openM}5$closeM',
                '$nowMs',
              );
              updatedRow[chainColIdx] = resolvedChain;
              if (updateOverallStatus) {
                updatedRow[_statusFieldIndex] = actionStatus;
              }

              buildAndSaveEventFromDSL(
                eventDSL: eventDSL,
                updatedRow: updatedRow,
                scrName: widget.scrName,
                flag: eventFlag,
                appVid: appVid,
              );
            }
          } else {
            debugPrint('[Approval] no PENDING step found in chain');
          }
        } else {
          debugPrint('[Approval] no chain field found in row');
        }
      }

      if (buttonConfig['chain'] != null && mounted) {
        await doChain(context, widget.scrName, buttonConfig['chain']);
      }
    } catch (e) {
      debugPrint('Approval action error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      List<dynamic> allData = List.from(tableContent[_tableCode] ?? []);

      // [1] Base filtering by role
      List<dynamic> baseFiltered;
      if (_role == 'APPROVER') {
        baseFiltered = _applyFieldConditions(allData);
      } else {
        baseFiltered = _applySearchFilter(allData);
      }

      // [2] Tab counts — APPROVER uses chain step, MAKER uses overall status
      String selStatus = _tabs.isNotEmpty && _selectedTabIndex < _tabs.length
          ? _tabs[_selectedTabIndex]
          : '';
      bool isAllTab =
          selStatus.toUpperCase() == 'SEMUA' ||
          selStatus.toUpperCase() == 'ALL';
      Map<String, int> counts = {};
      for (var tab in _tabs) {
        String tabUpper = tab.toUpperCase();
        if (tabUpper == 'SEMUA' || tabUpper == 'ALL') {
          counts[tab] = baseFiltered.length;
        } else if (_role == 'APPROVER') {
          counts[tab] = _applyApproverTabFilter(baseFiltered, tabUpper).length;
        } else {
          counts[tab] = baseFiltered
              .where((r) => _getStatus(r) == tabUpper)
              .length;
        }
      }

      // [3] Filter by selected tab
      List<dynamic> filtered;
      if (selStatus.isEmpty || isAllTab) {
        filtered = baseFiltered;
      } else if (_role == 'APPROVER') {
        filtered = _applyApproverTabFilter(
          baseFiltered,
          selStatus.toUpperCase(),
        );
      } else {
        filtered = baseFiltered
            .where((r) => _getStatus(r) == selStatus.toUpperCase())
            .toList();
      }

      // [4] Apply text search
      filtered = searchTable(_searchQuery, filtered);

      // [5] Sort descending by request timestamp (field [12])
      filtered.sort((a, b) {
        final tA =
            int.tryParse(
              (a as List).length > 12 ? a[12]?.toString() ?? '0' : '0',
            ) ??
            0;
        final tB =
            int.tryParse(
              (b as List).length > 12 ? b[12]?.toString() ?? '0' : '0',
            ) ??
            0;
        return tB.compareTo(tA);
      });

      double screenH = MediaQuery.of(context).size.height;
      double availableH = screenH * 0.79;
      return SizedBox(
        height: availableH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.lPad,
            widget.tPad,
            widget.rPad,
            widget.bPad,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_textArray.isNotEmpty && _textArray[0].isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _textArray[0],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
              _buildSearchField(),
              const SizedBox(height: 12),
              _buildTabBar(counts),
              const SizedBox(height: 14),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(selStatus)
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          Widget card = _buildCard(filtered[i], context);
                          if (i == filtered.length - 1) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: card,
                            );
                          }
                          return card;
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildSearchField() {
    String label = _textArray.length > 4 ? _textArray[4] : 'Search';
    String hint = _textArray.length > 5 ? _textArray[5] : label;
    return TextFormField(
      controller: _searchController,
      keyboardType: TextInputType.text,
      onChanged: (value) {
        // Debounce: run the heavy filter/sort pipeline once the user pauses
        // typing instead of on every keystroke.
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _searchQuery = value);
        });
      },
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        hintText: hint,
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2563EB)),
        ),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildTabBar(Map<String, int> counts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool needsScroll = _tabs.length > 3;

        List<Widget> tabWidgets = List.generate(_tabs.length, (i) {
          bool selected = i == _selectedTabIndex;
          String tab = _tabs[i];
          int count = counts[tab] ?? 0;

          Widget tabChild = GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _capitalize(tab),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? const Color(0xFF1F2937)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? _statusColor(tab)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                ],
              ),
            ),
          );

          if (needsScroll) return tabChild;
          return Expanded(child: tabChild);
        });

        Widget row = Row(children: tabWidgets);

        Widget content;
        if (needsScroll) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: row,
          );
        } else {
          content = row;
        }

        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildEmptyState(String status) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.inbox_outlined,
              size: 28,
              color: Color(0xFFD1D5DB),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _textArray.length > 6 ? _textArray[6] : 'Data tidak ditemukan',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(List<dynamic> row, BuildContext context) {
    String id = row.length > 1 ? row[1].toString() : '';
    String title = _textArray.length > 1
        ? _resolveText(_textArray[1], row)
        : id;
    String subtitle = _textArray.length > 2
        ? _resolveText(_textArray[2], row)
        : '';
    String dateText = _textArray.length > 3
        ? _resolveText(_textArray[3], row)
        : '';
    String status = _role == 'APPROVER'
        ? _getChainStatus(row)
        : _getStatus(row);
    String progress = _showProgress ? _getChainProgress(row) : '';
    Color sColor = _statusColor(status);
    Color sBgColor = _statusBgColor(status);

    String priorityTemplate = (widget.component['priority'] ?? '').toString();
    String priority = priorityTemplate.isNotEmpty
        ? _resolveText(priorityTemplate, row).trim().toUpperCase()
        : '';

    String assigneeTemplate = (widget.component['assignee'] ?? '').toString();
    if (assigneeTemplate.isEmpty && _textArray.length > 7) {
      assigneeTemplate = _textArray[7];
    }
    String assignee = assigneeTemplate.isNotEmpty
        ? _resolveText(assigneeTemplate, row).trim()
        : '';
    String assigneeDefault = _textArray.length > 8 ? _textArray[8] : '';
    if (assignee.isEmpty) assignee = assigneeDefault;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _onCardTap(row),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: sColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  id,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.3,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (priority.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _priorityBgColor(priority),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    priority,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _priorityColor(priority),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty || dateText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (subtitle.isNotEmpty) ...[
                                  Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      subtitle,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                if (dateText.isNotEmpty) ...[
                                  if (subtitle.isNotEmpty)
                                    const SizedBox(width: 12),
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dateText,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: sBgColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: sColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      progress.isEmpty
                                          ? _capitalize(status)
                                          : '${_capitalize(status)} $progress',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: sColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (assignee.isNotEmpty) ...[
                                const Spacer(),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      assignee,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: assignee == assigneeDefault
                                            ? const Color(0xFF9CA3AF)
                                            : const Color(0xFF1F2937),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(List<dynamic> row, BuildContext context) {
    if (!_showIcon) return _buildReportCard(row, context);

    String name = _textArray.length > 1
        ? _resolveText(_textArray[1], row)
        : (row.length > 1 ? row[1].toString() : '');
    String subtitle = _textArray.length > 2
        ? _resolveText(_textArray[2], row)
        : '';
    String dateText = _textArray.length > 3
        ? _resolveText(_textArray[3], row)
        : '';
    String status = _role == 'APPROVER'
        ? _getChainStatus(row)
        : _getStatus(row);
    String progress = _getChainProgress(row);
    Color sColor = _statusColor(status);
    Color sBgColor = _statusBgColor(status);

    int typeField = widget.component['typeField'] ?? 0;
    String typeText = '';
    if (typeField > 0 && typeField < row.length) {
      typeText = row[typeField]?.toString() ?? '';
    }
    if (typeText.isEmpty) typeText = subtitle;
    IconData icon = _typeIcon(typeText);

    List<dynamic>? buttons = widget.component['buttons'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _onCardTap(row),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: sColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  icon,
                                  size: 20,
                                  color: const Color(0xFF6B7280),
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
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (subtitle.isNotEmpty ||
                                        dateText.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          if (subtitle.isNotEmpty)
                                            Flexible(
                                              child: Text(
                                                subtitle,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF9CA3AF),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          if (dateText.isNotEmpty) ...[
                                            if (subtitle.isNotEmpty)
                                              Text(
                                                ' · ',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  color: Color(0xFF9CA3AF),
                                                ),
                                              ),
                                            Text(
                                              dateText,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF9CA3AF),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: const Color(0xFFD1D5DB),
                                size: 22,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: sBgColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: sColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      progress.isEmpty
                                          ? _capitalize(status)
                                          : '${_capitalize(status)} $progress',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: sColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_role == 'APPROVER' &&
                                  buttons != null &&
                                  _tabs.isNotEmpty &&
                                  status == _tabs[0].toUpperCase()) ...[
                                const Spacer(),
                                ..._buildActionButtons(row, buttons),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(List<dynamic> row, List<dynamic> buttons) {
    List<Widget> result = [];
    for (int i = 0; i < buttons.length; i++) {
      Map<String, dynamic> btn = buttons[i] is Map<String, dynamic>
          ? buttons[i]
          : {};
      String text = btn['text'] ?? '';
      String colorStr = (btn['color'] ?? '').toString().toLowerCase();

      Color btnColor;
      switch (colorStr) {
        case 'red':
          btnColor = const Color(0xFFDC2626);
          break;
        case 'green':
          btnColor = const Color(0xFF16A34A);
          break;
        case 'blue':
          btnColor = const Color(0xFF2563EB);
          break;
        default:
          btnColor = const Color(0xFF6B7280);
      }

      if (i > 0) result.add(const SizedBox(width: 8));

      result.add(
        SizedBox(
          height: 30,
          child: TextButton(
            onPressed: () => _onActionPressed(row, btn),
            style: TextButton.styleFrom(
              foregroundColor: btnColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: btnColor.withValues(alpha: 0.3)),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: btnColor,
              ),
            ),
          ),
        ),
      );
    }
    return result;
  }
}
