import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// import 'package:audioplayers/audioplayers.dart';
import 'package:collection/collection.dart';
import 'package:vibration/vibration.dart';
import '../crypto/auth_crypto.dart';
import '../global.dart';
import '../global2.dart';
import '../firestore_repository/table_repository.dart';
import '../model/ftz_scanned_code.dart';

const int _kSnackBarDuration = 1;
const String _kOkButtonColor = 'blue';
const String _kNotValidGroupColor = 'amber_800';
const String _kValidCounterColor = 'green';

// Status Color Constants
const String _kValidStatusBgColor = 'green_100';
const String _kValidStatusFgColor = 'green_700';
const String _kRejectedStatusBgColor = 'pink_100';
const String _kRejectedStatusFgColor = 'pink_700';
const String _kInvalidStatusBgColor = 'amber_100';
const String _kInvalidStatusFgColor = 'deep_orange_700';
const String _kDuplicateStatusBgColor = 'pink_100';
const String _kDuplicateStatusFgColor = 'pink_700';
//const int otonomiqVid = 60936087747650;

/// Helper class to parse and store list display options.
class ListOptions {
  final List<int> displayFields;
  final int? groupField;
  final int? sortField;

  ListOptions({
    required this.displayFields,
    this.groupField,
    this.sortField,
  });

  factory ListOptions.fromString(String? rawOptionsString) {
    if (rawOptionsString == null || rawOptionsString.isEmpty) {
      return ListOptions(displayFields: []);
    }

    try {
      String? optionsString = rawOptionsString
          .replaceAll('_u25C6_', separator[1])
          .replaceAll('_u25C7_', separator[5]);
      final parts = optionsString.split(separator[1]); // black diamond
      final displayFieldsStr = parts.isNotEmpty ? parts[0] : '';
      final groupFieldStr = parts.length > 1 ? parts[1] : null;
      final sortFieldStr = parts.length > 2 ? parts[2] : null;

      final displayFields = displayFieldsStr
          .split(separator[5]) // white diamond
          .map((e) => int.tryParse(e.trim()))
          .where((e) => e != null && e >= 0)
          .map((e) => e!)
          .toList();

      final groupField = (groupFieldStr != null && groupFieldStr.isNotEmpty)
          ? (int.tryParse(groupFieldStr.trim()) ?? 1)
          : null;

      final sortField = (sortFieldStr != null && sortFieldStr.isNotEmpty)
          ? (int.tryParse(sortFieldStr.trim()) ?? 1)
          : null;

      return ListOptions(
        displayFields: displayFields,
        groupField: groupField,
        sortField: sortField,
      );
    } catch (e) {
      debugPrint('Error parsing listOptions: $e');
      return ListOptions(displayFields: []);
    }
  }
}

({ValidationStatus status, List<dynamic>? row, String qrCode})
validateManualCode({
  required String code,
  required bool isMainRefCheckEnabled,
  required List<dynamic> mainRefData,
  required int mainRefField,
  required bool isPositiveRefCheckEnabled,
  required List<dynamic> positiveRefData,
  required bool isNegativeRefCheckEnabled,
  required List<dynamic> negativeRefData,
}) {
  String qrCode = code;
  // if (qrCode.length > 14) {
  //   qrCode = assetVerify(code, 9);
  // }
  if (qrCode == errorString) {
    return (status: ValidationStatus.invalidFormat, row: null, qrCode: qrCode);
  }

  List<dynamic>? foundRow;
  if (isMainRefCheckEnabled) {
    bool isFoundInMainRef = false;
    for (var row in mainRefData) {
      if (row.length > mainRefField && row[mainRefField].toString() == qrCode) {
        isFoundInMainRef = true;
        foundRow = row;
        break;
      }
    }
    if (!isFoundInMainRef) {
      return (
      status: ValidationStatus.notFoundInRef,
      row: null,
      qrCode: qrCode
      );
    }
  }

  if (isPositiveRefCheckEnabled &&
      !positiveRefData.map((e) => e.toString()).contains(qrCode)) {
    return (
    status: ValidationStatus.notInPositiveRef,
    row: foundRow,
    qrCode: qrCode
    );
  }

  if (isNegativeRefCheckEnabled &&
      negativeRefData.map((e) => e.toString()).contains(qrCode)) {
    return (
    status: ValidationStatus.foundInNegativeRef,
    row: foundRow,
    qrCode: qrCode
    );
  }

  return (status: ValidationStatus.valid, row: foundRow, qrCode: qrCode);
} // end validateManualCode

({ValidationStatus status, List<dynamic>? row, String qrCode}) validateCode({
  required String code,
  required bool isMainRefCheckEnabled,
  required List<dynamic> mainRefData,
  required int mainRefField,
  required bool isPositiveRefCheckEnabled,
  required List<dynamic> positiveRefData,
  required bool isNegativeRefCheckEnabled,
  required List<dynamic> negativeRefData,
}) {
  String qrCode = code;
  if (qrCode.length > 14) {
    qrCode = assetVerify(code, 9);
  }
  // debugPrint('mainRefField:$mainRefField');
  // debugPrint('mainRefData: $mainRefData');
  // debugPrint('Code: $qrCode in mainRefData.length = ${mainRefData.length}, ${mainRefData[0][1]}');

  if (qrCode == errorString) {
    // debugPrint('Code: $qrCode is invalid');
    return (status: ValidationStatus.invalidFormat, row: null, qrCode: qrCode);
  }
  List<dynamic>? foundRow;
  if (isMainRefCheckEnabled) {
    bool isFoundInMainRef = false;
    for (var row in mainRefData) {
      if (row.length > mainRefField && row[mainRefField].toString() == qrCode) {
        isFoundInMainRef = true;
        foundRow = row;
        break;
      }
    }
    if (!isFoundInMainRef) {
      // debugPrint('$qrCode not found in mainRefData');
      return (
      status: ValidationStatus.notFoundInRef,
      row: null,
      qrCode: qrCode
      );
    } else {
      // debugPrint('$qrCode found in mainRefData row $foundRow');
    }
  }

  if (isPositiveRefCheckEnabled &&
      !positiveRefData.map((e) => e.toString()).contains(qrCode)) {
    return (
    status: ValidationStatus.notInPositiveRef,
    row: foundRow,
    qrCode: qrCode
    );
  }

  if (isNegativeRefCheckEnabled &&
      negativeRefData.map((e) => e.toString()).contains(qrCode)) {
    return (
    status: ValidationStatus.foundInNegativeRef,
    row: foundRow,
    qrCode: qrCode
    );
  }

  return (status: ValidationStatus.valid, row: foundRow, qrCode: qrCode);
} // end validateCode

class MultiScanWidget extends StatefulWidget {
  final Map<String, dynamic> component;
  final String scrName;
  final ValueChanged<List<List<String>>>? onScanCompleted;
  final double listLength;
  final Widget? logo;

  const MultiScanWidget({
    super.key,
    required this.component,
    required this.scrName,
    this.onScanCompleted,
    this.listLength = 350.0,
    this.logo,
  });

  @override
  State<MultiScanWidget> createState() => _MultiScanWidgetState();
}

class _MultiScanWidgetState extends State<MultiScanWidget> {
  List<ScannedCode> _finalScannedCodes = [];
  late final List<String> _labels;
  late final Color _titleColor;
  late final bool _flashDefaultOn;
  late final CameraFacing _defaultCamera;

  late final String _targetTables;
  late final String _refTable;
  late final String _refTablePositive;
  late final String _refTableNegative;
  late final String _userAction;
  late final String _scrName;
  late final int? _position;
  late final ListOptions _listOptions;
  late final String? _table;

  late final EdgeInsets _margin;
  late final double _titleSize;
  late final double _otherTextSize;

  late final IconData _scanIcon;
  late final IconData _listIcon;

  List<dynamic> _mainRefData = [];
  List<dynamic> _positiveRefData = [];
  List<dynamic> _negativeRefData = [];
  int _mainRefField = 1;
  int _mainManualRefField = 2;
  int currentTableVid = consteonVid;

  bool _isMainRefCheckEnabled = true;
  bool _isPositiveRefCheckEnabled = false;
  bool _isNegativeRefCheckEnabled = false;
  bool _isLoading = false; // Set to false initially
  bool _isRefTablesSetupDone = false; // Flag to track one-time setup

  @override
  void initState() {
    super.initState();
    _labels = diamondTextToList(widget.component['text'] ?? '');
    _position = widget.component['position'] as int?;
    if (_position != null) {
      // State is managed by txfController, retrieve it.
      _finalScannedCodes = txfController[widget.scrName]![_position]!
          .stateObject as List<ScannedCode>;
    } else {
      // Fallback for widgets without a position (state will be ephemeral).
      _finalScannedCodes = [];
    } // end if _position != null
    _titleColor = stringToColor(
        (widget.component['titleColor'] as String? ?? 'black').toLowerCase());
    _flashDefaultOn =
        (widget.component['flash'] as String? ?? 'off').toLowerCase() == 'on';
    _defaultCamera =
    (widget.component['camera'] as String? ?? 'back').toLowerCase() ==
        'front'
        ? CameraFacing.front
        : CameraFacing.back;
    _userAction = (widget.component['userAction'] as String? ?? 'add delete')
        .toLowerCase();
    _scanIcon = stringToIconData(
        (widget.component['scanIcon'] as String? ?? 'qr_code_scanner')
            .toLowerCase());
    _listIcon = stringToIconData(
        (widget.component['listIcon'] as String? ?? 'list_alt').toLowerCase());
    _targetTables = widget.component['targetTables'] as String? ?? '';
    _refTable = autheniumDecode(widget.component['refTable'] as String?) ?? '';
    _refTablePositive =
        autheniumDecode(widget.component['refTablePositive'] as String?) ?? '';
    _refTableNegative =
        autheniumDecode(widget.component['refTableNegative'] as String?) ?? '';

    _scrName = widget.scrName;
    _margin =
        stringToEdgeInsets(widget.component['margin'] as String? ?? '8,16,0,0');
    _titleSize =
        (widget.component['titleSize'] ?? 16).toDouble() as double? ?? 20.0;
    _otherTextSize =
        (widget.component['size'] ?? 16).toDouble() as double? ?? 16.0;
    _listOptions = ListOptions.fromString((widget.component['listOptions'])
        .replaceAll("_u25C6_", separator[1]) as String?);
    _table = widget.component['table'] as String?;

    // DO NOT run _setupRefTables() here anymore.
  }

  Future<void> _setupRefTables() async {
    final List<Future<void>> futures = [];

    // Helper function to parse placeholders like {{n}}
    String processFilterString(String filter) {
      if (!filter.contains('{{')) return filter;

      final RegExp placeholderRegex = RegExp(r'\{\{(\d+)\}\}');
      return filter.replaceAllMapped(placeholderRegex, (match) {
        try {
          final int position = int.parse(match.group(1)!);
          // Access txfController safely
          final controllerData =
              txfController[widget.scrName]?[position]?.finalData;
          return controllerData?.toString() ??
              ''; // Replace with data or empty string
        } catch (e) {
          debugPrint('Error parsing placeholder ${match.group(0)}: $e');
          return ''; // Return empty string on error
        }
      });
    }

    // Main reference table
    if (_refTable.isNotEmpty) {
      final parts = _refTable.split(separator[1]);
      if (parts.length >= 2) {
        String tableName = normalizeTableName(parts[0]);
        final fieldPart = parts[1].split(separator[5]);
        int fieldNum = int.tryParse(fieldPart[0]) ?? 1;
        int manualFieldNum =
        fieldPart.length > 1 ? (int.tryParse(fieldPart[1]) ?? 2) : 2;
        String rawFilterString = parts.length > 2 ? parts[2] : '';
        String filterString = processFilterString(rawFilterString);

        if (tableName.isNotEmpty && fieldNum > 0) {
          _isMainRefCheckEnabled = true;
          _mainRefField = fieldNum;
          _mainManualRefField = manualFieldNum;

          final future = readFromFirestoreTable(
            currentTableVid,
            tableName,
            tableName,
            index: fieldNum,
            indexTableString: filterString,
          ).then((data) {
            if (mounted) {
              _mainRefData = data ??
                  [
                    ['no Data from line 326 ftz_multi_scan.dart']
                  ];
            }
          });
          futures.add(future);
        }
      }
    }

    // Positive reference table
    if (_refTablePositive.isNotEmpty) {
      final parts = _refTablePositive.split(separator[1]);
      if (parts.length >= 2) {
        final tableName = normalizeTableName(parts[0]);
        final fieldNum = int.tryParse(parts[1]) ?? 1;
        final rawFilterString = parts.length > 2 ? parts[2] : '';
        final filterString = processFilterString(rawFilterString);

        if (tableName.isNotEmpty && fieldNum > 0) {
          _isPositiveRefCheckEnabled = true;
          final future = readFromFirestoreTable(
            currentTableVid,
            tableName,
            tableName,
            index: fieldNum,
            indexTableString: filterString,
          ).then((data) {
            if (mounted && data != null) {
              _positiveRefData = data
                  .where((row) => row.length >= fieldNum)
                  .map((row) => row[fieldNum - 1])
                  .toList();
            }
          });
          futures.add(future);
        }
      }
    }

    // Negative reference table
    if (_refTableNegative.isNotEmpty) {
      final parts = _refTableNegative.split(separator[1]);
      if (parts.length >= 2) {
        final tableName = normalizeTableName(parts[0]);
        final fieldNum = int.tryParse(parts[1]) ?? 1;
        final rawFilterString = parts.length > 2 ? parts[2] : '';
        final filterString = processFilterString(rawFilterString);

        if (tableName.isNotEmpty && fieldNum > 0) {
          _isNegativeRefCheckEnabled = true;
          final future = readFromFirestoreTable(
            currentTableVid,
            tableName,
            tableName,
            index: fieldNum,
            indexTableString: filterString,
          ).then((data) {
            if (mounted && data != null) {
              _negativeRefData = data
                  .where((row) => row.length >= fieldNum)
                  .map((row) => row[fieldNum - 1])
                  .toList();
            }
          });
          futures.add(future);
        }
      }
    }

    if (futures.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Helper method to run the one-time setup if it hasn't been run yet.
  Future<void> _runSetupIfNeeded() async {
    if (!_isRefTablesSetupDone) {
      setState(() {
        _isLoading = true;
      });
      await _setupRefTables(); // This method will set _isLoading to false when done
      _isRefTablesSetupDone = true;
    }
  }

  void _launchScanner(bool isEnabled) async {
    // Await the setup process on the first press
    await _runSetupIfNeeded();

    // Do not proceed if the setup is still running (e.g., due to quick taps)
    if (_isLoading) return;

    final result = await Get.dialog<List<ScannedCode>>(
      _ScannerDialog(
        initialCodes: _finalScannedCodes,
        labels: _labels,
        isFlashOnByDefault: _flashDefaultOn,
        defaultCamera: _defaultCamera,
        listIcon: _listIcon,
        scrName: _scrName,
        position: _position ?? 0,
        targetTables: _targetTables,
        userAction: _userAction,
        listOptions: _listOptions,
        isMainRefCheckEnabled: _isMainRefCheckEnabled,
        mainRefData: _mainRefData,
        mainRefField: _mainRefField,
        mainManualRefField: _mainManualRefField,
        isPositiveRefCheckEnabled: _isPositiveRefCheckEnabled,
        positiveRefData: _positiveRefData,
        isNegativeRefCheckEnabled: _isNegativeRefCheckEnabled,
        negativeRefData: _negativeRefData,
        table: _table,
        isEnabled: isEnabled,
      ),
    );

    if (result != null) {
      setState(() {
        _finalScannedCodes = result;
        // Update the controller with the new state
        if (_position != null) {
          txfController[widget.scrName]![_position]!.stateObject =
              _finalScannedCodes;
        }
      });
      widget.onScanCompleted
          ?.call(result.map((sc) => [sc.code, sc.status.toString()]).toList());
    }
  }

  void _showDataManagerDialog(bool isEnabled) async {
    // Await the setup process on the first press
    await _runSetupIfNeeded();

    // Do not proceed if the setup is still running
    if (_isLoading) return;

    final result = await Get.dialog<List<ScannedCode>>(
      _DataManagerDialog(
        initialCodes: _finalScannedCodes,
        labels: _labels,
        listIcon: _listIcon,
        scrName: _scrName,
        position: _position ?? 0,
        targetTables: _targetTables,
        userAction: _userAction,
        listOptions: _listOptions,
        isMainRefCheckEnabled: _isMainRefCheckEnabled,
        mainRefData: _mainRefData,
        mainRefField: _mainRefField,
        mainManualRefField: _mainManualRefField,
        isPositiveRefCheckEnabled: _isPositiveRefCheckEnabled,
        positiveRefData: _positiveRefData,
        isNegativeRefCheckEnabled: _isNegativeRefCheckEnabled,
        negativeRefData: _negativeRefData,
        table: _table,
        isEnabled: isEnabled,
      ),
      barrierDismissible: false,
    );
    if (result != null) {
      setState(() {
        _finalScannedCodes = result;
        // Update the controller with the new state
        if (_position != null) {
          txfController[widget.scrName]![_position]!.stateObject =
              _finalScannedCodes;
        }
      });
      widget.onScanCompleted
          ?.call(result.map((sc) => [sc.code, sc.status.toString()]).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final validCodeCount = _finalScannedCodes
        .where((c) => c.status == ValidationStatus.valid)
        .length;

    if (_labels.isEmpty || widget.component['text'] == null) {
      return Card(
        margin: _margin,
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Component text configuration error. The "text" field is mandatory and cannot be empty.',
            style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    if (_labels.length < 37) {
      return Card(
        margin: _margin,
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Component text configuration error. Expected 37 labels, but found ${_labels.length}. Please check the diamond-separated string.',
            style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Container(
      margin: _margin,
      padding: const EdgeInsetsDirectional.only(
        start: 16.0,
        end: 16.0,
        top: 8.0,
        bottom: 6.0,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: _titleColor, width: 1.5),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              _labels[0],
              style: textTheme.titleLarge?.copyWith(
                fontSize: _titleSize,
                fontWeight: FontWeight.bold,
                color: _titleColor,
              ),
            ),
          ),
          if (widget.logo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: widget.logo,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 70.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _labels[1],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _otherTextSize,
                      ),
                    ),
                    Text(
                      '$validCodeCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _otherTextSize * 2.25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (isEnabled && !_isLoading)
                              ? () => _launchScanner(isEnabled)
                              : null,
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade500,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12),
                            textStyle: TextStyle(
                              fontSize: _otherTextSize,
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                              : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_scanIcon),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _labels[2],
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (!_isLoading)
                              ? () => _showDataManagerDialog(isEnabled)
                              : null,
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade500,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12),
                            textStyle: TextStyle(fontSize: _otherTextSize),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_listIcon),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _labels[3],
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}

class _DataManagerDialog extends StatefulWidget {
  final List<ScannedCode> initialCodes;
  final List<String> labels;
  final IconData listIcon;
  final int position;
  final String scrName;
  final String targetTables;
  final String userAction;
  final ListOptions listOptions;
  final bool isMainRefCheckEnabled;
  final List<dynamic> mainRefData;
  final int mainRefField;
  final int mainManualRefField;
  final bool isPositiveRefCheckEnabled;
  final List<dynamic> positiveRefData;
  final bool isNegativeRefCheckEnabled;
  final List<dynamic> negativeRefData;
  final String? table;
  final bool isEnabled;

  const _DataManagerDialog({
    required this.initialCodes,
    required this.labels,
    required this.scrName,
    required this.listIcon,
    required this.position,
    required this.targetTables,
    required this.userAction,
    required this.listOptions,
    required this.isMainRefCheckEnabled,
    required this.mainRefData,
    required this.mainRefField,
    required this.mainManualRefField,
    required this.isPositiveRefCheckEnabled,
    required this.positiveRefData,
    required this.isNegativeRefCheckEnabled,
    required this.negativeRefData,
    required this.table,
    required this.isEnabled,
  });
  @override
  State<_DataManagerDialog> createState() => _DataManagerDialogState();
}

class _DataManagerDialogState extends State<_DataManagerDialog> {
  late List<ScannedCode> _codes;
  late Set<String> _codeStrings;
  late TextEditingController _manualInputController;

  @override
  void initState() {
    super.initState();
    _codes = List.from(widget.initialCodes);
    _codeStrings = Set.from(widget.initialCodes.map((sc) => sc.code));
    _manualInputController = TextEditingController();
  }

  @override
  void dispose() {
    _manualInputController.dispose();
    super.dispose();
  }

  void _addManualCode() {
    final String code = _manualInputController.text.trim();
    if (code.isEmpty) return;

    final validationResult = validateManualCode(
      code: code,
      isMainRefCheckEnabled: widget.isMainRefCheckEnabled,
      mainRefData: widget.mainRefData,
      mainRefField: widget.mainRefField,
      isPositiveRefCheckEnabled: widget.isPositiveRefCheckEnabled,
      positiveRefData: widget.positiveRefData,
      isNegativeRefCheckEnabled: widget.isNegativeRefCheckEnabled,
      negativeRefData: widget.negativeRefData,
    );
    String codeToAdd = validationResult.qrCode;
    if (_codeStrings.contains(codeToAdd)) {
      Get.snackbar(widget.labels[25], widget.labels[16],
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: _kSnackBarDuration),
          margin: const EdgeInsets.all(12));
      return;
    }
    if (_codeStrings.contains(validationResult.qrCode)) {
      Get.snackbar(widget.labels[25], widget.labels[16],
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: _kSnackBarDuration),
          margin: const EdgeInsets.all(12));
      return;
    }
    setState(() {
      final newScannedCode = ScannedCode(codeToAdd, validationResult.status,
          refDataRow: validationResult.row);
      _codes.add(newScannedCode);
      _codeStrings.add(codeToAdd);
    });

    _manualInputController.clear();

    String title, message;
    switch (validationResult.status) {
      case ValidationStatus.valid:
        title = widget.labels[24];
        message = widget.labels[15];
        break;
      case ValidationStatus.invalidFormat:
      case ValidationStatus.rejected:
        title = widget.labels[26];
        message = widget.labels[17];
        break;
      case ValidationStatus.notFoundInRef:
        title = widget.labels[26];
        message = widget.labels[28];
        break;
      case ValidationStatus.notInPositiveRef:
        title = widget.labels[26];
        message = widget.labels.length > 36
            ? widget.labels[36]
            : "Not in positive list";
        break;
      case ValidationStatus.foundInNegativeRef:
        title = widget.labels[26];
        message = widget.labels[29];
        break;
      case ValidationStatus.duplicate:
        return;
    }

    Get.snackbar(title, message,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: _kSnackBarDuration),
        margin: const EdgeInsets.all(12));
  }

  void _handleDelete(int index) {
    final removedCode = _codes.removeAt(index);
    _codeStrings.remove(removedCode.code);
    setState(() {});
    Get.snackbar(widget.labels[27], widget.labels[18],
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: _kSnackBarDuration),
        margin: const EdgeInsets.all(12));
  }

  void _toggleValidationStatus(int index) {
    setState(() {
      final ScannedCode currentCode = _codes[index];
      ValidationStatus newStatus;
      String codeForValidation = currentCode.code;
      if (widget.isMainRefCheckEnabled &&
          currentCode.refDataRow != null &&
          currentCode.refDataRow!.length > widget.mainRefField) {
        codeForValidation =
            currentCode.refDataRow![widget.mainRefField].toString();
      }
      dynamic validation = validateCode(
        code: codeForValidation,
        isMainRefCheckEnabled: widget.isMainRefCheckEnabled,
        mainRefData: widget.mainRefData,
        mainRefField: widget.mainRefField,
        isPositiveRefCheckEnabled: widget.isPositiveRefCheckEnabled,
        positiveRefData: widget.positiveRefData,
        isNegativeRefCheckEnabled: widget.isNegativeRefCheckEnabled,
        negativeRefData: widget.negativeRefData,
      );
      if (currentCode.status == ValidationStatus.valid) {
        newStatus = ValidationStatus.rejected;
      } else if (currentCode.status != ValidationStatus.valid) {
        newStatus = ValidationStatus.valid;
      } else {
        newStatus = validation.status;
      }

      _codes[index] = ScannedCode(currentCode.code, newStatus,
          refDataRow: currentCode.refDataRow);
    });
  }

  void _clearAllData() {
    if (_codes.isEmpty) return;

    Get.dialog(
      AlertDialog(
        title: Text(widget.labels[20]),
        content: Text(widget.labels[21]),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(widget.labels[22]),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _codes.clear();
                _codeStrings.clear();
              });
              Get.back();
            },
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(widget.labels[23]),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTile(ScannedCode scannedCode, int index) {
    Color backgroundColor;
    Color textColor;
    String statusText;
    Widget displayContent;

    switch (scannedCode.status) {
      case ValidationStatus.valid:
        backgroundColor = stringToColor(_kValidStatusBgColor);
        textColor = stringToColor(_kValidStatusFgColor);
        statusText = widget.labels[31];
        break;
      case ValidationStatus.rejected:
        backgroundColor = stringToColor(_kRejectedStatusBgColor);
        textColor = stringToColor(_kRejectedStatusFgColor);
        statusText = widget.labels[34];
        break;
      case ValidationStatus.notFoundInRef:
      case ValidationStatus.foundInNegativeRef:
      case ValidationStatus.notInPositiveRef:
      case ValidationStatus.invalidFormat:
        backgroundColor = stringToColor(_kInvalidStatusBgColor);
        textColor = stringToColor(_kInvalidStatusFgColor);
        statusText = widget.labels[32];
        break;
      default:
        backgroundColor = stringToColor(_kDuplicateStatusBgColor);
        textColor = stringToColor(_kDuplicateStatusFgColor);
        statusText = widget.labels[33];
    }

    if (widget.isMainRefCheckEnabled &&
        widget.listOptions.displayFields.isNotEmpty &&
        scannedCode.refDataRow != null) {
      final List<Widget> columns = [];
      for (var i = 0; i < widget.listOptions.displayFields.length; i++) {
        final fieldIndex = widget.listOptions.displayFields[i];
        final text = (fieldIndex < scannedCode.refDataRow!.length)
            ? scannedCode.refDataRow![fieldIndex].toString()
            : '';
        columns.add(Text(text));
        if (i < widget.listOptions.displayFields.length - 1) {
          columns.add(const SizedBox(width: 16));
        }
      }
      displayContent = Row(mainAxisSize: MainAxisSize.min, children: columns);
    } else {
      displayContent = Text(scannedCode.code);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: displayContent,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: const BoxConstraints(
                    maxWidth: 120,
                  ),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (widget.userAction.contains('toggle') &&
                        widget.isEnabled)
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                          icon: const Icon(Icons.swap_horiz),
                          onPressed: () => _toggleValidationStatus(index),
                          tooltip: 'Toggle Status',
                        ),
                      ),
                    if (widget.userAction.contains('toggle') &&
                        widget.userAction.contains('delete') &&
                        widget.isEnabled)
                      const SizedBox(width: 8),
                    if (widget.userAction.contains('delete') &&
                        widget.isEnabled)
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _handleDelete(index),
                          tooltip: 'Delete',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSummary(
      Map<String, List<ScannedCode>> groupedCodes, TextTheme textTheme) {
    final notValidGroupName =
    widget.labels.length > 35 ? widget.labels[35] : 'Not Valid';

    final displayableGroups = groupedCodes.entries
        .where(
            (entry) => entry.key != notValidGroupName && entry.value.isNotEmpty)
        .toList();

    if (displayableGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: displayableGroups.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key, style: textTheme.bodyMedium),
                  Text(
                    '${entry.value.length}',
                    style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: stringToColor(_kValidCounterColor)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final validCodeCount =
        _codes.where((c) => c.status == ValidationStatus.valid).length;

    Map<String, List<ScannedCode>> groupedCodesForAllItems = {};
    List<ScannedCode> sortedCodes = List.from(_codes);

    final groupFieldIndex = widget.listOptions.groupField;
    final sortFieldIndex = widget.listOptions.sortField;
    final notValidGroupName =
    widget.labels.length > 35 ? widget.labels[35] : 'Not Valid';

    Map<String, List<ScannedCode>> summaryGroupedCodes = {};
    if (widget.isMainRefCheckEnabled &&
        groupFieldIndex != null &&
        groupFieldIndex >= 0) {
      final validCodes =
      _codes.where((c) => c.status == ValidationStatus.valid).toList();
      summaryGroupedCodes = groupBy(
          validCodes,
              (code) => (code.refDataRow != null &&
              code.refDataRow!.length > groupFieldIndex)
              ? code.refDataRow![groupFieldIndex].toString()
              : notValidGroupName);
    }

    if (widget.isMainRefCheckEnabled &&
        groupFieldIndex != null &&
        groupFieldIndex >= 0) {
      groupedCodesForAllItems = groupBy(
          _codes,
              (code) => (code.refDataRow != null &&
              code.refDataRow!.length > groupFieldIndex)
              ? code.refDataRow![groupFieldIndex].toString()
              : notValidGroupName);

      groupedCodesForAllItems.forEach((key, value) {
        value.sort((a, b) {
          if (sortFieldIndex != null && sortFieldIndex >= 0) {
            final aVal =
            (a.refDataRow != null && a.refDataRow!.length > sortFieldIndex)
                ? a.refDataRow![sortFieldIndex].toString()
                : '';
            final bVal =
            (b.refDataRow != null && b.refDataRow!.length > sortFieldIndex)
                ? b.refDataRow![sortFieldIndex].toString()
                : '';
            return aVal.compareTo(bVal);
          }
          return a.code.compareTo(b.code);
        });
      });
    } else {
      sortedCodes.sort((a, b) => a.code.compareTo(b.code));
    }

    final validGroupEntries = groupedCodesForAllItems.entries
        .where((entry) => entry.key != notValidGroupName)
        .toList();
    final notValidGroupEntry = groupedCodesForAllItems.entries
        .firstWhereOrNull((entry) => entry.key == notValidGroupName);

    return Dialog(
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(widget.labels[12],
                        style: textTheme.headlineSmall?.copyWith()),
                  ),
                  TextButton.icon(
                    onPressed: widget.isEnabled ? _clearAllData : null,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(widget.labels[19]),
                    style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _codes.isEmpty
                    ? Center(child: Text(widget.labels[13]))
                    : Column(
                  children: [
                    Expanded(
                      child: widget.isMainRefCheckEnabled &&
                          groupFieldIndex != null &&
                          groupFieldIndex >= 0
                          ? ListView(
                        children: [
                          ...validGroupEntries.map((entry) {
                            final groupName = entry.key;
                            final items = entry.value;
                            final validCount = items
                                .where((i) =>
                            i.status ==
                                ValidationStatus.valid)
                                .length;
                            return ExpansionTile(
                              title: RichText(
                                text: TextSpan(
                                  style:
                                  textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color:
                                    textTheme.bodyLarge?.color,
                                  ),
                                  children: <TextSpan>[
                                    TextSpan(text: '$groupName ('),
                                    TextSpan(
                                        text: '$validCount',
                                        style: TextStyle(
                                            color: stringToColor(
                                                _kValidCounterColor))),
                                    TextSpan(
                                        text:
                                        ' / ${items.length})'),
                                  ],
                                ),
                              ),
                              children: items.map((code) {
                                final index = _codes.indexOf(code);
                                return _buildStatusTile(
                                    code, index);
                              }).toList(),
                            );
                          }),
                          if (notValidGroupEntry != null &&
                              notValidGroupEntry.value.isNotEmpty)
                            ExpansionTile(
                              collapsedTextColor: stringToColor(
                                  _kNotValidGroupColor),
                              textColor: stringToColor(
                                  _kNotValidGroupColor),
                              iconColor: stringToColor(
                                  _kNotValidGroupColor),
                              collapsedIconColor: stringToColor(
                                  _kNotValidGroupColor),
                              title: Text(
                                '${notValidGroupEntry.key} (${notValidGroupEntry.value.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              children: notValidGroupEntry.value
                                  .map((code) {
                                final index = _codes.indexOf(code);
                                return _buildStatusTile(
                                    code, index);
                              }).toList(),
                            ),
                        ],
                      )
                          : ListView.builder(
                        itemCount: sortedCodes.length,
                        itemBuilder: (context, index) {
                          final code = sortedCodes[index];
                          final originalIndex =
                          _codes.indexOf(code);
                          return _buildStatusTile(
                              code, originalIndex);
                        },
                      ),
                    ),
                    if (widget.isMainRefCheckEnabled &&
                        groupFieldIndex != null &&
                        groupFieldIndex >= 0)
                      _buildGroupSummary(summaryGroupedCodes, textTheme),
                  ],
                ),
              ),
              if (widget.userAction.contains('add') && widget.isEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                          child: TextField(
                              controller: _manualInputController,
                              decoration: InputDecoration(
                                  labelText: widget.labels[6],
                                  labelStyle: const TextStyle(),
                                  border: const OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      ElevatedButton(
                          onPressed: _addManualCode,
                          style: ElevatedButton.styleFrom(),
                          child: Text(widget.labels[7])),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(widget.labels[5],
                          style: textTheme.titleMedium?.copyWith()),
                      Text('${_codes.length}',
                          style: textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      Text(widget.labels[30],
                          style: textTheme.titleMedium?.copyWith(
                              color: stringToColor(_kValidCounterColor))),
                      Text('$validCodeCount',
                          style: textTheme.headlineLarge?.copyWith(
                              color: stringToColor(_kValidCounterColor),
                              fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: widget.isEnabled
                        ? () {
                      Map<String, dynamic> tempTable = {};
                      if (widget.isMainRefCheckEnabled) {
                        tempTable = writeMultipleTablesTemporary(
                            widget.targetTables, groupedCodesForAllItems);
                      } else {
                        final Map<String, List<ScannedCode>> allCodesMap =
                        {'all': _codes};
                        tempTable = writeMultipleTablesTemporary(
                            widget.targetTables, allCodesMap);
                      }

                      final validCodes = _codes
                          .where(
                              (sc) => sc.status == ValidationStatus.valid)
                          .map((sc) => sc.code)
                          .toList();
                      final content = validCodes.join(separator[5]);
                      addToTxfController(
                          widget.position, widget.scrName, content,
                          table: tempTable,
                          stateObject: _codes); // Pass the state object

                      Get.back(result: _codes);
                    }
                        : () => Get.back(result: _codes),
                    style: TextButton.styleFrom(),
                    child: Text(widget.labels[14])),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerDialog extends StatefulWidget {
  final List<ScannedCode>? initialCodes;
  final List<String> labels;
  final bool isFlashOnByDefault;
  final CameraFacing defaultCamera;
  final IconData listIcon;
  final String scrName;
  final int position;
  final String targetTables;
  final String userAction;
  final ListOptions listOptions;
  final bool isMainRefCheckEnabled;
  final List<dynamic> mainRefData;
  final int mainRefField;
  final int mainManualRefField;
  final bool isPositiveRefCheckEnabled;
  final List<dynamic> positiveRefData;
  final bool isNegativeRefCheckEnabled;
  final List<dynamic> negativeRefData;
  final String? table;
  final bool isEnabled;

  const _ScannerDialog({
    this.initialCodes,
    required this.labels,
    required this.isFlashOnByDefault,
    required this.defaultCamera,
    required this.listIcon,
    required this.scrName,
    required this.position,
    required this.targetTables,
    required this.userAction,
    required this.listOptions,
    required this.isMainRefCheckEnabled,
    required this.mainRefData,
    required this.mainManualRefField,
    required this.mainRefField,
    required this.isPositiveRefCheckEnabled,
    required this.positiveRefData,
    required this.isNegativeRefCheckEnabled,
    required this.negativeRefData,
    required this.table,
    required this.isEnabled,
  });
  @override
  State<_ScannerDialog> createState() => _ScannerDialogState();
}

class _ScannerDialogState extends State<_ScannerDialog> {
  late final MobileScannerController _scannerController;
  late List<ScannedCode> _scannedBarcodes;
  late Set<String> _scannedBarcodeStrings;
  bool _isScanning = true;
  // final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _manualInputController = TextEditingController();
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      facing: widget.defaultCamera,
      torchEnabled: widget.isFlashOnByDefault,
    );

    _isTorchOn = widget.isFlashOnByDefault;

    // _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _scannedBarcodes = List.from(widget.initialCodes ?? []);
    _scannedBarcodeStrings = Set.from(_scannedBarcodes.map((e) => e.code));
  }

  @override
  void dispose() {
    _scannerController.dispose();
    // _audioPlayer.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  void _toggleTorch() async {
    await _scannerController.toggleTorch();
    setState(() => _isTorchOn = !_isTorchOn);
  }

  void _triggerFeedback() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 50);
    }
    // await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
  }

  void _processScannedCode(String code) {
    final validationResult = validateCode(
      code: code,
      isMainRefCheckEnabled: widget.isMainRefCheckEnabled,
      mainRefData: widget.mainRefData,
      mainRefField: widget.mainRefField,
      isPositiveRefCheckEnabled: widget.isPositiveRefCheckEnabled,
      positiveRefData: widget.positiveRefData,
      isNegativeRefCheckEnabled: widget.isNegativeRefCheckEnabled,
      negativeRefData: widget.negativeRefData,
    );
    if (_scannedBarcodeStrings.contains(validationResult.qrCode)) return;

    setState(() {
      _scannedBarcodes.add(ScannedCode(
          validationResult.qrCode, validationResult.status,
          refDataRow: validationResult.row));
      _scannedBarcodeStrings.add(validationResult.qrCode);
    });

    if (validationResult.status == ValidationStatus.valid) {
      _triggerFeedback();
    }
  }

  void _addManualCode() {
    final String code = _manualInputController.text.trim();

    final validationResult = validateCode(
      code: code,
      isMainRefCheckEnabled: widget.isMainRefCheckEnabled,
      mainRefData: widget.mainRefData,
      mainRefField: widget.mainRefField,
      isPositiveRefCheckEnabled: widget.isPositiveRefCheckEnabled,
      positiveRefData: widget.positiveRefData,
      isNegativeRefCheckEnabled: widget.isNegativeRefCheckEnabled,
      negativeRefData: widget.negativeRefData,
    );

    String codeToAdd = validationResult.qrCode;
    if (validationResult.row != null) {
      if (validationResult.row!.length > 1) {
        codeToAdd = validationResult.row![1].toString();
      }
    }
    if (_scannedBarcodeStrings.contains(codeToAdd)) {
      Get.snackbar(widget.labels[25], widget.labels[16],
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: _kSnackBarDuration),
          margin: const EdgeInsets.all(12));
      return;
    }
    setState(() {
      _scannedBarcodes.add(ScannedCode(codeToAdd, validationResult.status,
          refDataRow: validationResult.row));
      _scannedBarcodeStrings.add(codeToAdd);
    });

    _manualInputController.clear();
    FocusScope.of(context).unfocus();

    String title, message;
    switch (validationResult.status) {
      case ValidationStatus.valid:
        _triggerFeedback();
        title = widget.labels[24];
        message = widget.labels[15];
        break;
      case ValidationStatus.invalidFormat:
      case ValidationStatus.rejected:
        title = widget.labels[26];
        message = widget.labels[17];
        break;
      case ValidationStatus.notFoundInRef:
        title = widget.labels[26];
        message = widget.labels[28];
        break;
      case ValidationStatus.notInPositiveRef:
        title = widget.labels[26];
        message = widget.labels.length > 36
            ? widget.labels[36]
            : "Not in positive list";
        break;
      case ValidationStatus.foundInNegativeRef:
        title = widget.labels[26];
        message = widget.labels[29];
        break;
      case ValidationStatus.duplicate:
        return;
    }

    Get.snackbar(title, message,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: _kSnackBarDuration),
        margin: const EdgeInsets.all(12));
  }

  void _pauseScanning() => setState(() {
    _isScanning = false;
    _scannerController.stop();
  });
  void _resumeScanning() => setState(() {
    _isScanning = true;
    _scannerController.start();
  });

  void _showListDialog() async {
    _pauseScanning();
    final result = await Get.dialog<List<ScannedCode>>(
      _DataManagerDialog(
          initialCodes: _scannedBarcodes,
          labels: widget.labels,
          listIcon: widget.listIcon,
          scrName: widget.scrName,
          position: widget.position,
          targetTables: widget.targetTables,
          userAction: widget.userAction,
          listOptions: widget.listOptions,
          isMainRefCheckEnabled: widget.isMainRefCheckEnabled,
          mainRefData: widget.mainRefData,
          mainRefField: widget.mainRefField,
          mainManualRefField: widget.mainManualRefField,
          isPositiveRefCheckEnabled: widget.isPositiveRefCheckEnabled,
          positiveRefData: widget.positiveRefData,
          isNegativeRefCheckEnabled: widget.isNegativeRefCheckEnabled,
          negativeRefData: widget.negativeRefData,
          table: widget.table,
          isEnabled: widget.isEnabled),
      barrierDismissible: false,
    );
    if (result != null) {
      setState(() {
        _scannedBarcodes = result;
        _scannedBarcodeStrings = Set.from(result.map((sc) => sc.code));
      });
    }
    _resumeScanning();
  }

  void _clearAllData() {
    if (_scannedBarcodes.isEmpty) return;

    Get.dialog(
      AlertDialog(
        title: Text(widget.labels[20]),
        content: Text(widget.labels[21]),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(widget.labels[22]),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _scannedBarcodes.clear();
                _scannedBarcodeStrings.clear();
              });
              Get.back();
            },
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(widget.labels[23]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final validCodeCount = _scannedBarcodes
        .where((c) => c.status == ValidationStatus.valid)
        .length;

    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.labels[4]),
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Get.back(result: _scannedBarcodes)),
            actions: [
              IconButton(
                  icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
                  onPressed: _toggleTorch),
              IconButton(
                  icon: const Icon(Icons.flip_camera_ios_outlined),
                  onPressed: () => _scannerController.switchCamera()),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                flex: 3,
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    if (!_isScanning || !widget.isEnabled) return;
                    for (final barcode in capture.barcodes) {
                      if (barcode.rawValue != null) {
                        _processScannedCode(barcode.rawValue!);
                      }
                    }
                  },
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(widget.labels[5],
                                    style: textTheme.titleMedium?.copyWith()),
                                Text('${_scannedBarcodes.length}',
                                    style: textTheme.headlineLarge?.copyWith(
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              children: [
                                Text(widget.labels[30],
                                    style: textTheme.titleMedium?.copyWith(
                                        color: stringToColor(
                                            _kValidCounterColor))),
                                Text('$validCodeCount',
                                    style: textTheme.headlineLarge?.copyWith(
                                        color:
                                        stringToColor(_kValidCounterColor),
                                        fontWeight: FontWeight.bold)),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (widget.userAction.contains('add'))
                          Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Row(children: [
                              Expanded(
                                  child: TextField(
                                      controller: _manualInputController,
                                      enabled: widget.isEnabled,
                                      decoration: InputDecoration(
                                          labelText: widget.labels[6],
                                          labelStyle: const TextStyle(),
                                          border: const OutlineInputBorder()))),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                  onPressed:
                                  widget.isEnabled ? _addManualCode : null,
                                  style: ElevatedButton.styleFrom(),
                                  child: Text(widget.labels[7])),
                            ]),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: [
                            if (_isScanning)
                              ElevatedButton.icon(
                                  onPressed:
                                  widget.isEnabled ? _pauseScanning : null,
                                  icon: const Icon(Icons.pause),
                                  style: ElevatedButton.styleFrom(),
                                  label: Text(widget.labels[8]))
                            else
                              ElevatedButton.icon(
                                  onPressed:
                                  widget.isEnabled ? _resumeScanning : null,
                                  icon: const Icon(Icons.play_arrow),
                                  style: ElevatedButton.styleFrom(),
                                  label: Text(widget.labels[9])),
                            ElevatedButton.icon(
                                icon: Icon(widget.listIcon),
                                style: ElevatedButton.styleFrom(),
                                label: Text(widget.labels[10]),
                                onPressed: _showListDialog),
                            OutlinedButton.icon(
                              onPressed:
                              widget.isEnabled ? _clearAllData : null,
                              icon: const Icon(Icons.delete_sweep_outlined),
                              label: Text(widget.labels[19]),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error),
                              ),
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(widget.labels[11]),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  stringToColor(_kOkButtonColor),
                                  foregroundColor: colorScheme.onPrimary),
                              onPressed: widget.isEnabled
                                  ? () {
                                final groupFieldIndex =
                                    widget.listOptions.groupField;
                                final notValidGroupName =
                                widget.labels.length > 35
                                    ? widget.labels[35]
                                    : 'Not Valid';
                                Map<String, List<ScannedCode>>
                                groupedCodes = {};

                                if (widget.isMainRefCheckEnabled &&
                                    groupFieldIndex != null &&
                                    groupFieldIndex >= 0) {
                                  groupedCodes = groupBy(
                                      _scannedBarcodes,
                                          (code) => (code.refDataRow !=
                                          null &&
                                          code.refDataRow!.length >
                                              groupFieldIndex)
                                          ? code.refDataRow![
                                      groupFieldIndex]
                                          .toString()
                                          : notValidGroupName);
                                } else {
                                  groupedCodes = {
                                    'all': _scannedBarcodes
                                  };
                                }

                                Map<String, dynamic> tempTable =
                                writeMultipleTablesTemporary(
                                    widget.targetTables,
                                    groupedCodes);

                                final validCodes = _scannedBarcodes
                                    .where((sc) =>
                                sc.status ==
                                    ValidationStatus.valid)
                                    .map((sc) => sc.code)
                                    .toList();
                                final content =
                                validCodes.join(separator[5]);
                                addToTxfController(widget.position,
                                    widget.scrName, content,
                                    table: tempTable,
                                    stateObject:
                                    _scannedBarcodes); // Pass the state object

                                Get.back(result: _scannedBarcodes);
                              }
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
} // End of _ScannerDialog