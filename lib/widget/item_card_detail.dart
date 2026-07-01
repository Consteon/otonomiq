import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import 'approver_sticky_bar.dart';

class ItemCardDetail extends StatefulWidget {
  static final RxString currentStatus = ''.obs;
  static final Rx<List<dynamic>> currentRow = Rx<List<dynamic>>([]);
  static final RxMap<String, String> screenStatus = RxMap<String, String>({});

  const ItemCardDetail({
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
  State<ItemCardDetail> createState() => _ItemCardDetailState();
}

class _ItemCardDetailState extends State<ItemCardDetail> {
  String _tableCode = '';
  List<String> _textArray = [];
  List<String> _contentArray = [];
  String _role = '';
  List<String> _tabs = [];
  int _myApprovalLevel = -1;

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
    try {
      _contentArray = diamondTextToList(widget.component['content'] ?? '');
    } catch (_) {
      _contentArray = [];
    }

    var screenTx = transactionStore.state.screenTx;
    String txRole = (screenTx['approval_role'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    _role = txRole.isNotEmpty
        ? txRole
        : (widget.component['role'] ?? '').toString().trim().toUpperCase();

    if (screenTx['approval_tabs'] is List) {
      _tabs = (screenTx['approval_tabs'] as List)
          .map((e) => e.toString())
          .toList();
    }
    _myApprovalLevel =
        int.tryParse((screenTx['approval_level'] ?? '').toString()) ?? -1;
  }

  void _subscribeTable() {
    String rawTable = (widget.component['table'] ?? '').toString().trim();
    String decoded = autheniumDecode(rawTable) ?? rawTable;
    _tableCode = normalizeTableName(decoded);
    var screenTx = transactionStore.state.screenTx;
    String txVid = (screenTx['approval_vidtable'] ?? '').toString();
    int tableVid =
        int.tryParse(txVid) ??
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
      template,
      row,
      int.tryParse((widget.component['indexStart'] ?? '1').toString()) ?? 1,
      false,
    );
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

  String _getChainStatus(List<dynamic> row) {
    if (_myApprovalLevel <= 0) return '';
    Map<int, String> chain = _parseApprovalChain(row);
    return chain[_myApprovalLevel] ?? '';
  }

  String _getChainProgress(List<dynamic> row) {
    if (_tabs.length < 2) return '';
    Map<int, String> chain = _parseApprovalChain(row);
    if (chain.isEmpty) return '';
    String continueStatus = _tabs[1].toUpperCase();
    int done = chain.values.where((s) => s == continueStatus).length;
    return '($done/${chain.length})';
  }

  static Color _statusAccentColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Color(0xFFE8910C);
      case 'APPROVED':
        return const Color(0xFF16A34A);
      case 'REJECTED':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF6B7280);
    }
  }

  static Color _statusBgColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Color(0xFFFEF3C7);
      case 'APPROVED':
        return const Color(0xFFDCFCE7);
      case 'REJECTED':
        return const Color(0xFFFEE2E2);
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
    if (s.contains('time correction') || s.contains('koreksi')) {
      return Icons.history_rounded;
    }
    if (s.contains('attendance') || s.contains('kehadiran')) {
      return Icons.edit_note_rounded;
    }
    if (s.contains('sick') || s.contains('sakit')) {
      return Icons.medical_services_outlined;
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

  static String _formatDateValue(String raw) {
    if (raw.isEmpty) return raw;
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    try {
      final trimmed = raw.trim();
      final spaceParts = trimmed.split(' ');
      // dd MMM yyyy HH:mm or dd MMM yyyy
      if (spaceParts.length >= 3) {
        int? day = int.tryParse(spaceParts[0]);
        String monthStr = spaceParts[1];
        int? year = int.tryParse(spaceParts[2]);
        if (day != null && year != null && months.contains(monthStr)) {
          return '$day $monthStr $year';
        }
      }
      // yyyy-MM-dd or yyyy-MM-dd HH:mm:ss
      final dashParts = spaceParts[0].split('-');
      if (dashParts.length == 3) {
        int year = int.parse(dashParts[0]);
        int month = int.parse(dashParts[1]);
        int day = int.parse(dashParts[2]);
        if (month >= 1 && month <= 12) {
          return '$day ${months[month]} $year';
        }
      }
    } catch (_) {}
    return raw;
  }

  void _showFullImage(BuildContext ctx, List<String> urls, int initial) {
    ApproverStickyBar.overlaysHidden.value = true;
    Navigator.of(ctx)
        .push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black87,
            pageBuilder: (_, _, _) =>
                _FullImageViewer(urls: urls, initialIndex: initial),
          ),
        )
        .whenComplete(() => ApproverStickyBar.overlaysHidden.value = false);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      List<dynamic> allData = List.from(tableContent[_tableCode] ?? []);
      String condRaw = (widget.component['conditions'] ?? '').toString();
      debugPrint(
        '[ItemCardDetail] tableCode=$_tableCode | rows=${allData.length} | conditions=$condRaw',
      );
      allData = _applyConditions(allData);
      debugPrint('[ItemCardDetail] after conditions: ${allData.length} rows');

      if (allData.isEmpty) return const SizedBox.shrink();

      var row = allData[0];

      String typeLabel = _textArray.isNotEmpty
          ? _resolveText(_textArray[0], row)
          : '';
      String titleText = _textArray.length > 1
          ? _resolveText(_textArray[1], row)
          : '';
      String submittedText = _textArray.length > 2
          ? _resolveText(_textArray[2], row)
          : '';

      String statusTemplate = (widget.component['status'] ?? '').toString();
      String status = statusTemplate.isNotEmpty
          ? _resolveText(statusTemplate, row).trim().toUpperCase()
          : '';
      if (_role == 'APPROVER') {
        String chainStatus = _getChainStatus(row);
        if (chainStatus.isNotEmpty) status = chainStatus;
      }
      String progress = _getChainProgress(row);
      String statusDisplay = progress.isEmpty
          ? _capitalize(status)
          : '${_capitalize(status)} $progress';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ItemCardDetail.currentStatus.value != status) {
          ItemCardDetail.currentStatus.value = status;
        }
        ItemCardDetail.screenStatus[widget.scrName] = status;
        ItemCardDetail.currentRow.value = List.from(row);
      });

      String reasonTemplate = (widget.component['reason'] ?? '').toString();
      String reason = reasonTemplate.isNotEmpty
          ? _resolveText(reasonTemplate, row)
          : '';

      String imageTemplate = (widget.component['image'] ?? '').toString();
      String imageUrl = imageTemplate.isNotEmpty
          ? _resolveText(imageTemplate, row)
          : '';

      Color accentColor = _statusAccentColor(status);
      Color statusBg = _statusBgColor(status);
      IconData icon = _typeIcon(typeLabel);

      List<MapEntry<String, String>> details = [];
      int labelStart = 3;
      int labelEnd = _textArray.length - 2;
      for (int i = labelStart; i < labelEnd; i++) {
        String label = _textArray[i];
        int contentIdx = i - labelStart;
        String rawValue = contentIdx < _contentArray.length
            ? _resolveText(_contentArray[contentIdx], row)
            : '';
        String value = label.toLowerCase().contains('date')
            ? _formatDateValue(rawValue)
            : rawValue;
        if (label.isNotEmpty) {
          details.add(MapEntry(label, value));
        }
      }

      String reasonHeader = _textArray.length >= 2
          ? _textArray[_textArray.length - 2]
          : 'REASON';
      String imageTitle = _textArray.isNotEmpty
          ? _textArray.last
          : 'DATA PENDUKUNG';

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.lPad,
          widget.tPad,
          widget.rPad,
          widget.bPad,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Accent bar
              Container(height: 3, color: accentColor),

              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: icon + type label | status badge
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            icon,
                            size: 18,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            typeLabel.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        if (status.isNotEmpty)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusDisplay,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Title
                    if (titleText.isNotEmpty)
                      Text(
                        titleText,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),

                    // Submitted
                    if (submittedText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        submittedText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],

                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      const SizedBox(height: 14),

                      // Key-value rows
                      ...details.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  entry.value,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Reason section
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      const SizedBox(height: 14),
                      Text(
                        reasonHeader.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reason,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF374151),
                          height: 1.5,
                        ),
                      ),
                    ],

                    // Image gallery
                    if (imageUrl.isNotEmpty) ...[
                      () {
                        List<String> urls = imageUrl
                            .split('◇')
                            .map((u) => u.trim())
                            .where((u) => u.startsWith('http'))
                            .take(5)
                            .toList();
                        if (urls.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            const SizedBox(height: 14),
                            Text(
                              imageTitle.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 90,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: urls.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (_, idx) => GestureDetector(
                                  onTap: () =>
                                      _showFullImage(context, urls, idx),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      urls[idx],
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 90,
                                        height: 90,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.broken_image_outlined,
                                          size: 20,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }(),
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

class _FullImageViewer extends StatefulWidget {
  const _FullImageViewer({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<_FullImageViewer> {
  late PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    widget.urls[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.urls.length,
                    (i) => Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _current ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
