// ftz_bluetooth_printer.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart'
    as fs; // GetOptions/Source for keyed cache-first read
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as pos_utils;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
// MODIFIED: Replaced flutter_blue_plus with flutter_reactive_ble
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:get/get.dart'; // MODIFIED: Added GetX for state management
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../firestore_repository/table_repository.dart';
import '../global.dart';
import '../global2.dart';
import '../template_pdf.dart';
import '../template_printer.dart';
import 'driver_home_support.dart'; // resolveDriverCurlyTokens, resolveAppVid
import 'panel_card_support.dart'; // parseTablePath/TablePath -- SAME parse the native write uses

class FtzBluetoothPrinter extends StatefulWidget {
  final Map<String, dynamic> component;
  final String scrName;

  const FtzBluetoothPrinter({
    super.key,
    required this.component,
    required this.scrName,
  });

  @override
  State<FtzBluetoothPrinter> createState() => _FtzBluetoothPrinterState();
}

class _FtzBluetoothPrinterState extends State<FtzBluetoothPrinter> {
  // MODIFIED: Combined state variable
  bool _isBusy = false;
  bool _isLoadingData = false;
  int currentTableVid = consteonVid;

  // MODIFIED: Add BLE plugin instance and stream subscriptions
  final _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  /// Last printer the user picked, remembered across prints (and screens, since
  /// it's static). When set, [_startPrintProcess] connects straight to it via
  /// connect-by-id and skips the 4s scan + selection dialog. Cleared on any
  /// connection failure so the next press falls back to scan+dialog.
  static DiscoveredDevice? _lastDevice;

  // Component Properties
  late final String _buttonText;
  late final IconData _buttonIcon;
  late final Color _buttonColor;
  late final Color _onButtonColor;
  late final pos_utils.PaperSize _paperSize;
  late final List<String> _labels;
  late final String _scrName;
  late final MainAxisAlignment _alignment;
  late final int? _position; // MODIFIED: Added position for state management

  // Properties for template printing
  late final String? _template;
  late final String? _tableNamesString;
  // NOTE: values may be List (positional) OR scalar/List<Map> (keyed variant),
  // so this is Map<String, dynamic>, matching TemplatePrinter.tables.
  final Map<String, dynamic> _tableData = {};

  // Keyed variant config (P3 walk-in nota reprint). Empty for positional.
  late final String _variant;
  late final String _searchConfig;

  // Share-PDF variant config. Null for bluetooth variants.
  late final PdfPageFormat? _pdfPageFormat;
  late final String _fileName;
  late final PdfColor? _borderColor;
  late final double _borderWidthPt;
  late final int _gridCols;
  late final int _gridRows;
  late final bool _isGridMode;

  @override
  void initState() {
    super.initState();

    _labels = diamondTextToList(widget.component['text'] ?? '');
    _buttonText = _labels.isNotEmpty ? _labels[0] : 'Print';
    _buttonIcon = stringToIconData(
      widget.component['buttonIcon'] as String? ?? 'print',
    );
    _buttonColor = stringToColor(
      widget.component['buttonColor'] as String? ?? 'teal',
    );
    _onButtonColor = stringToColor(
      widget.component['onButtonColor'] as String? ?? 'white',
    );
    _paperSize =
        (widget.component['paperSize'] as String? ?? 'mm80').toLowerCase() ==
            'mm58'
        ? pos_utils.PaperSize.mm58
        : pos_utils.PaperSize.mm80;
    _scrName = widget.scrName;
    _position = widget.component['position'] as int?; // MODIFIED

    final String alignStr = widget.component['alignment'] ?? 'center';
    switch (alignStr.toLowerCase()) {
      case 'left':
        _alignment = MainAxisAlignment.start;
        break;
      case 'right':
        _alignment = MainAxisAlignment.end;
        break;
      case 'center':
      default:
        _alignment = MainAxisAlignment.center;
        break;
    }

    _template = widget.component['template'] as String?;
    _tableNamesString = normalizeTableName(
      autheniumDecode(widget.component['table']) ?? '',
    );

    _variant = (widget.component['variant'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    // FIX-1: decode the search config BEFORE it is split on separator[2]
    // (◼ = U+25FC). The server encodes ◼ as _25FC_; a raw split would yield
    // <2 parts and the keyed print would never load. Mirrors the table decode
    // above (autheniumDecode(widget.component['table'])).
    _searchConfig = (autheniumDecode(widget.component['search']) ?? '')
        .toString()
        .trim();

    // ── Share-PDF variant: parse PDF page format, file name, border ──
    if (_variant == 'share-pdf') {
      final String ps = (widget.component['paperSize'] as String? ?? 'a6')
          .toLowerCase();
      _pdfPageFormat = ps == 'a4' ? PdfPageFormat.a4 : PdfPageFormat.a6;
      _fileName = (widget.component['fileName'] as String? ?? 'share.pdf')
          .toString()
          .trim();
      final String? borderName = (widget.component['border'] as String?)
          ?.trim();
      _borderColor = (borderName != null && borderName.isNotEmpty)
          ? _resolvePdfColor(borderName)
          : null;

      // borderWidth: only meaningful when border is present (spec §3).
      // Parsed always; TemplatePdf ignores it when borderColor is null.
      final String bwStr = (widget.component['borderWidth'] as String? ?? '8')
          .toString()
          .trim();
      _borderWidthPt = double.tryParse(bwStr) ?? 8.0;

      // Grid config: "KxB" (e.g. "4x4" = 4 cols x 4 rows).
      // Malformed -> WARN + fall back to single mode.
      final String? gridStr = (widget.component['grid'] as String?)
          ?.trim()
          .toLowerCase();
      if (gridStr != null && gridStr.isNotEmpty) {
        final List<String> gParts = gridStr.split('x');
        final int? k = gParts.isNotEmpty ? int.tryParse(gParts[0]) : null;
        final int? b = gParts.length > 1 ? int.tryParse(gParts[1]) : null;
        if (k != null && k >= 1 && b != null && b >= 1) {
          _gridCols = k;
          _gridRows = b;
          _isGridMode = true;
        } else {
          devPrint(
            '[PRN share-pdf] WARN: malformed grid "$gridStr", '
            'falling back to single mode',
          );
          _gridCols = 1;
          _gridRows = 1;
          _isGridMode = false;
        }
      } else {
        _gridCols = 1;
        _gridRows = 1;
        _isGridMode = false;
      }
    } else {
      _pdfPageFormat = null;
      _fileName = '';
      _borderColor = null;
      _borderWidthPt = 8.0;
      _gridCols = 1;
      _gridRows = 1;
      _isGridMode = false;
    }
  }

  // MODIFIED: Added dispose to cancel streams
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<List<List<dynamic>>> readFromTable(
    String scrName,
    String rawTableName,
  ) async {
    // ... existing code ...
    dynamic tableArray = rawTableName.split(separator[2]);
    String tableName = replacePlaceHoldersFromTxfController(
      scrName,
      tableArray[0].trim(),
    );
    if (_tableData.containsKey(tableName)) {
      return [_tableData[tableName] ?? []];
    } else {
      late String internalTableCode;
      if (tableArray.length > 1) {
        internalTableCode = tableArray[1].trim();
      } else {
        internalTableCode = tableName
            .substring(tableName.lastIndexOf('/') + 1)
            .replaceAll('.', '_');
      }
      final data = await readFromFirestoreTable(
        currentTableVid,
        tableName,
        internalTableCode,
      );
      _tableData[internalTableCode] = data ?? [];
      return [data ?? []];
    }
  }

  Future<void> _loadPrintData() async {
    if (mounted) {
      setState(() => _isLoadingData = true);
    }

    _tableData.clear();

    try {
      if (_variant == 'keyed' || _variant == 'share-pdf') {
        // ── Keyed variant: fetch ONE doc by search, populate _tableData ──
        await _loadKeyedData();
      } else {
        // ── Positional variant (existing): read from proxy tables ────────
        if (_tableNamesString == null || _tableNamesString.isEmpty) {
          return;
        }

        final List<String> tablesToLoad = diamondTextToList(_tableNamesString);
        if (tablesToLoad.isEmpty) {
          return;
        }

        final List<Future<List<List<dynamic>>>> futures = tablesToLoad.map((
          tableName,
        ) {
          return readFromTable(_scrName, tableName);
        }).toList();

        await Future.wait(futures);
        for (int i = 0; i < tablesToLoad.length; i++) {
          dynamic tableArray = tablesToLoad[i].split(separator[2]);
          final String originalName = tableArray[0];
          late String mapKey;
          if (tableArray.length > 1) {
            mapKey = tableArray[1].trim();
          } else {
            mapKey = originalName
                .substring(originalName.lastIndexOf('/') + 1)
                .replaceAll('.', '_');
          }
          _tableData[mapKey] = tableContent[mapKey];
        }
      }
    } catch (e) {
      _showSnackBar('Error loading table data: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  /// Load a single Firestore doc by search for the keyed PRN variant.
  ///
  /// Search config format: "field◼{token}" (separator[2] = U+25FC).
  /// Example: "nno◼{nno}" -> query where nno == resolved {nno} token value.
  /// The search config is decoded (autheniumDecode) in initState BEFORE this
  /// split, so `_25FC_` is already back to ◼.
  ///
  /// Populates [_tableData] with the doc's fields as a flat Map so
  /// TemplatePrinter._interpolate resolves {{field}} via path-traversal.
  /// Array fields (like li[]) stay as List<Map> for LOOP source binding.
  Future<void> _loadKeyedData() async {
    // W1: the share-pdf variant owns ALL its user-facing messaging in
    // _startSharePdfProcess (text[4] on _tableData.isEmpty). Suppress the
    // keyed-variant failure toasts here so share-pdf shows exactly ONE
    // (translated) snackbar instead of two -- the first an untranslated
    // 'PRN keyed: ...' string. Diagnostics (errorReport/devPrint) stay intact.
    // Bluetooth ('keyed'/other) variants: unchanged -- toasts still show.
    final bool silent = _variant == 'share-pdf';
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (_searchConfig.isEmpty || rawTable.isEmpty) {
      if (!silent) {
        _showSnackBar('PRN keyed: missing search or table config', Colors.red);
      }
      return;
    }

    // Parse search: split on separator[2] (◼ = U+25FC)
    final List<String> searchParts = _searchConfig.split(separator[2]);
    if (searchParts.length < 2) {
      if (!silent)
        _showSnackBar('PRN keyed: invalid search format', Colors.red);
      return;
    }
    final String searchField = searchParts[0].trim();
    final String rawValue = searchParts[1].trim();

    // Resolve {token} in the search value (e.g. {nno} -> screenTx['nno'])
    final String resolvedValue = resolveDriverCurlyTokens(rawValue, _scrName);

    // Guard: unresolved token still contains '{' -> abort
    if (resolvedValue.contains('{')) {
      if (!silent) {
        _showSnackBar('PRN keyed: unresolved token in search', Colors.red);
      }
      return;
    }

    // Build the collection path EXACTLY like the native write
    // (createNativeDocAutoId): parseTablePath(rawTable) -> {docId}/{subColl}.
    // NOT eventCollectionPath(normalizeTableName(...)) -- that form collapses
    // "84214220504259//nota" to ".../84214220504259%nota/content" and never
    // matches the doc the write created at ".../tables/84214220504259/nota".
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty || tp.subColl.isEmpty) {
      if (!silent) _showSnackBar('PRN keyed: invalid table path', Colors.red);
      errorReport('[PRN keyed] bad table path: $rawTable');
      return;
    }
    final String appVid = resolveAppVid(widget.component);
    final String path =
        '$mobileTable/$appVid/$mobileTableCollection/${tp.tableDocId}/${tp.subColl}';

    devPrint('[PRN keyed] query path=$path $searchField=$resolvedValue');

    // Match string first, then numeric (Firestore is type-exact). Each tries
    // CACHE then SERVER -- see _queryNota. Cache-first because the common path
    // is printing right after creating the nota, whose fire-and-forget write
    // (createNativeDocAutoId) is not yet server-ack'd; the local cache already
    // holds it, so a direct server .get() would miss (the immediate-print race
    // the plan flagged) and offline reprint would fail.
    List<dynamic> docs = await _queryNota(path, searchField, resolvedValue);
    if (docs.isEmpty) {
      final num? numValue = num.tryParse(resolvedValue);
      if (numValue != null) {
        docs = await _queryNota(path, searchField, numValue);
      }
    }

    if (docs.isEmpty) {
      if (!silent) _showSnackBar('PRN keyed: nota not found', Colors.orange);
      errorReport(
        '[PRN keyed] nota not found: path=$path $searchField=$resolvedValue',
      );
      return;
    }
    if (docs.length > 1) {
      errorReport('[PRN keyed] >1 match for $searchField=$resolvedValue');
    }
    // Populate _tableData with the doc's fields directly. TemplatePrinter
    // receives tables = _tableData and _createContext() returns it, so
    // {{nno}} resolves via context['nno'] and <LOOP source='li'> reads
    // context['li'] (List<Map>).
    _populateFromDoc(docs.first.data() as Map);
  }

  /// Query the nota collection for [field]==[value], CACHE first then SERVER.
  ///
  /// Cache-first: the just-created nota's write (createNativeDocAutoId) is
  /// fire-and-forget and may not be server-ack'd when the user prints, but the
  /// SDK's local cache already reflects the pending mutation -- so cache finds
  /// it (fixes the immediate-print race) and reprint works offline. Server is
  /// the fallback for notas created on another device or evicted from cache.
  /// nota docs are immutable snapshots, so a cache hit is never stale.
  /// Returns [] on miss (each source's errors are swallowed + logged).
  ///
  /// [limit] caps the query result count. Default 2 (single-doc callers only
  /// need 1, limit 2 to detect duplicates). Pass null for grid mode (all docs).
  Future<List<dynamic>> _queryNota(
    String path,
    String field,
    dynamic value, {
    int? limit = 2,
  }) async {
    for (final fs.Source src in <fs.Source>[
      fs.Source.cache,
      fs.Source.server,
    ]) {
      try {
        dynamic query = firestoreDb
            .collection(path)
            .where(field, isEqualTo: value);
        if (limit != null) query = query.limit(limit);
        final dynamic snap = await query.get(fs.GetOptions(source: src));
        final List<dynamic> docs = snap.docs as List;
        if (docs.isNotEmpty) return docs;
      } catch (e) {
        devPrint('[PRN keyed] query($src) $field=$value error: $e');
      }
    }
    return const <dynamic>[];
  }

  /// Copy a fetched doc's fields into [_tableData] (scalars + arrays).
  void _populateFromDoc(Map docData) {
    _tableData.clear();
    docData.forEach((key, value) {
      _tableData[key.toString()] = value;
    });
  }

  /// Resolve a color string to PdfColor. Hex (#RRGGBB) -> PdfColor.fromHex;
  /// named (e.g. 'blue') -> stringToColor -> PdfColor. Default black.
  /// Single point of resolution for both borderColor and colorResolver.
  PdfColor _resolvePdfColor(String value) {
    if (value.startsWith('#')) {
      return PdfColor.fromHex(value);
    }
    return PdfColor.fromInt(stringToColor(value).toARGB32());
  }

  /// Load image bytes by key for TemplatePdf IMAGE tags.
  /// - `http://` / `https://` key -> fetched over the network (e.g. a Firebase
  ///   Storage branding image). Offline / non-200 -> null -> renderer skips it.
  /// - otherwise -> bundle asset `assets/images/{key}.png`.
  /// Returns null on any failure (silently skipped by renderer).
  Future<Uint8List?> _loadAssetBytes(String key) async {
    try {
      if (key.startsWith('http://') || key.startsWith('https://')) {
        final resp = await http
            .get(Uri.parse(key))
            .timeout(const Duration(seconds: 5));
        return resp.statusCode == 200 ? resp.bodyBytes : null;
      }
      final data = await rootBundle.load('assets/images/$key.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Load ALL matching docs for grid mode. Returns list of doc-data maps,
  /// sorted by 'ln' field A->Z. 0 docs -> empty list (caller shows text[4]).
  /// Reuses search-parsing logic from _loadKeyedData but queries without limit.
  /// Does NOT modify _tableData (grid renderer receives items directly).
  Future<List<Map<String, dynamic>>> _loadKeyedDataGrid() async {
    final String rawTable = (widget.component['table'] ?? '').toString().trim();
    if (_searchConfig.isEmpty || rawTable.isEmpty) return const [];

    // Parse search: split on separator[2] (U+25FC).
    // _searchConfig already autheniumDecoded in initState.
    final List<String> searchParts = _searchConfig.split(separator[2]);
    if (searchParts.length < 2) return const [];
    final String searchField = searchParts[0].trim();
    final String rawValue = searchParts[1].trim();

    // Resolve {token} in the search value
    final String resolvedValue = resolveDriverCurlyTokens(rawValue, _scrName);

    // Guard: unresolved token still contains '{'
    if (resolvedValue.contains('{')) {
      devPrint('[PRN share-pdf grid] unresolved token in search: $rawValue');
      return const [];
    }

    // Build collection path (same as _loadKeyedData)
    final TablePath tp = parseTablePath(rawTable);
    if (tp.tableDocId.isEmpty || tp.subColl.isEmpty) {
      errorReport('[PRN share-pdf grid] bad table path: $rawTable');
      return const [];
    }
    final String appVid = resolveAppVid(widget.component);
    final String path =
        '$mobileTable/$appVid/$mobileTableCollection/${tp.tableDocId}/${tp.subColl}';

    devPrint(
      '[PRN share-pdf grid] query path=$path $searchField=$resolvedValue',
    );

    // String match first, then numeric fallback (Firestore is type-exact).
    // limit: null -> no cap, fetch ALL matching docs.
    List<dynamic> docs = await _queryNota(
      path,
      searchField,
      resolvedValue,
      limit: null,
    );
    if (docs.isEmpty) {
      final num? numValue = num.tryParse(resolvedValue);
      if (numValue != null) {
        docs = await _queryNota(path, searchField, numValue, limit: null);
      }
    }

    if (docs.isEmpty) return const [];

    // Convert to typed maps. Guard dynamic cast (firestoreDb is dynamic).
    final List<Map<String, dynamic>> items = [];
    for (final doc in docs) {
      final dynamic rawData = doc.data();
      if (rawData is Map) {
        items.add(Map<String, dynamic>.from(rawData));
      }
    }

    // Sort by 'ln' field A->Z (spec §5: deterministic order).
    items.sort((a, b) {
      final String aLn = (a['ln'] ?? '').toString();
      final String bLn = (b['ln'] ?? '').toString();
      return aLn.compareTo(bLn);
    });

    return items;
  }

  void _showSnackBar(String message, [Color? color]) {
    // ... existing code ...
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? Colors.blueGrey,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // MODIFIED: Updated function signature to use DiscoveredDevice
  Future<DiscoveredDevice?> _showDeviceSelectionDialog(
    List<DiscoveredDevice> devices,
  ) async {
    return await showDialog<DiscoveredDevice>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select a Printer'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: devices.length,
              shrinkWrap: true,
              itemBuilder: (context, index) {
                final device = devices[index];
                // MODIFIED: Use device.name and device.id
                final deviceName = device.name.isNotEmpty
                    ? device.name
                    : 'Unknown Device';
                return ListTile(
                  title: Text(deviceName),
                  subtitle: Text(device.id),
                  onTap: () {
                    Navigator.of(context).pop(device);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ],
        );
      },
    );
  }

  // MODIFIED: Rewritten function to use flutter_reactive_ble
  Future<void> _startPrintProcess() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);
    _discoveredDevices.clear();

    try {
      if (Platform.isAndroid) {
        var scanStatus = await Permission.bluetoothScan.request();
        var connectStatus = await Permission.bluetoothConnect.request();

        if (scanStatus.isDenied ||
            connectStatus.isDenied ||
            scanStatus.isPermanentlyDenied ||
            connectStatus.isPermanentlyDenied) {
          _showSnackBar(
            'Bluetooth permissions are required to find printers.',
            Colors.red,
          );
          if (scanStatus.isPermanentlyDenied ||
              connectStatus.isPermanentlyDenied) {
            await openAppSettings();
          }
          return;
        }
      }
      await _loadPrintData();
      if (_isLoadingData || !mounted) return;
      // Keyed variant: if the doc didn't load (_tableData empty), abort BEFORE
      // the BLE scan/connect -- otherwise <LOOP source='li'> throws a cryptic
      // "Source not found" mid-print and wastes a printer connection.
      // _loadKeyedData already surfaced the specific cause via snackbar.
      if (_variant == 'keyed' && _tableData.isEmpty) {
        setState(() => _isBusy = false);
        return;
      }

      // MODIFIED: Check BLE status with flutter_reactive_ble
      if (_ble.status != BleStatus.ready) {
        _showSnackBar("Bluetooth is OFF. Please turn it ON.", Colors.red);
        return;
      }

      // Reuse the last-selected printer: skip the 4s scan + selection dialog
      // when one is remembered (connect-by-id needs no prior scan). On a
      // connection failure _connectAndPrint clears _lastDevice, so the next
      // press falls back to the scan+dialog path below.
      if (_lastDevice != null) {
        _connectAndPrint(_lastDevice!);
        return;
      }

      // MODIFIED: Start scanning
      _showSnackBar("Scanning for printers for 4 seconds...", Colors.blue);
      _scanSubscription = _ble
          .scanForDevices(withServices: [])
          .listen(
            (device) {
              // MODIFIED: Corrected 'connectable' check
              if (device.name.isNotEmpty ||
                  device.connectable == Connectable.available) {
                _discoveredDevices.putIfAbsent(device.id, () => device);
              }
            },
            onError: (e) {
              _showSnackBar("Scan Error: $e", Colors.red);
              if (mounted) setState(() => _isBusy = false);
            },
          );

      // Stop scanning after 4 seconds
      await Future.delayed(const Duration(seconds: 4));
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (!mounted) return;
      if (_discoveredDevices.isEmpty) {
        _showSnackBar("No Bluetooth devices found.", Colors.orange);
        return;
      }

      final selectedDevice = await _showDeviceSelectionDialog(
        _discoveredDevices.values.toList(),
      );

      if (selectedDevice == null) {
        _showSnackBar("No printer selected.", Colors.grey);
        return;
      }

      // Remember for next print -> skips scan+dialog while the printer stays on.
      _lastDevice = selectedDevice;

      // MODIFIED: Handle connection and printing in a separate stream-based function
      _connectAndPrint(selectedDevice);
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
      if (mounted) setState(() => _isBusy = false);
    } finally {
      // MODIFIED: Most cleanup is now handled by stream listeners.
      // We only set busy to false if a device wasn't selected.
      if (_connectionSubscription == null && mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  // MODIFIED: New function to handle reactive connection and print logic
  void _connectAndPrint(DiscoveredDevice device) {
    // Cancel any previous connection
    _connectionSubscription?.cancel();

    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 15),
        )
        .listen(
          (connectionState) async {
            if (connectionState.connectionState ==
                DeviceConnectionState.connected) {
              _showSnackBar(
                "Connected. Negotiating MTU...",
                Colors.blue,
              ); // Updated message
              try {
                // MODIFIED: Request MTU after connection. 512 is a common request size.
                final int mtu = await _ble.requestMtu(
                  deviceId: device.id,
                  mtu: 512,
                );
                _showSnackBar("Printing...", Colors.blue);
                await _performPrint(device, mtu);
                _showSnackBar("Print command sent successfully!", Colors.green);
              } catch (e) {
                _showSnackBar("Print Error: $e", Colors.red);
              } finally {
                // Disconnect after printing. Reset _isBusy HERE too: cancelling the
                // stream stops the "disconnected" event that is otherwise the only
                // place _isBusy clears, so without this the button stays stuck on
                // "Processing..." after a successful print.
                _connectionSubscription?.cancel();
                if (mounted) setState(() => _isBusy = false);
              }
            } else if (connectionState.connectionState ==
                DeviceConnectionState.disconnected) {
              if (mounted) {
                setState(() => _isBusy = false);
              }
              // Only show "Disconnected" if it wasn't an immediate failure
              if (connectionState.failure == null) {
                _showSnackBar("Disconnected.", Colors.grey);
              } else {
                // Immediate connect failure (printer off / out of range):
                // forget it so the next press re-scans instead of retrying a
                // dead device silently.
                _lastDevice = null;
              }
            }
          },
          onError: (e) {
            _showSnackBar("Connection Error: $e", Colors.red);
            _lastDevice = null; // forget on error -> next press re-scans
            if (mounted) {
              setState(() => _isBusy = false);
            }
          },
        );
  }

  // MODIFIED: Rewritten to use flutter_reactive_ble
  Future<void> _performPrint(DiscoveredDevice connectedDevice, int mtu) async {
    QualifiedCharacteristic? writableCharacteristic;

    // Discover services
    List<DiscoveredService> services = await _ble.discoverServices(
      connectedDevice.id,
    );

    for (DiscoveredService service in services) {
      for (DiscoveredCharacteristic characteristic in service.characteristics) {
        // Check for write properties
        if (characteristic.isWritableWithoutResponse ||
            characteristic.isWritableWithResponse) {
          writableCharacteristic = QualifiedCharacteristic(
            characteristicId: characteristic.characteristicId,
            serviceId: service.serviceId,
            deviceId: connectedDevice.id,
          );
          break;
        }
      }
      if (writableCharacteristic != null) break;
    }

    if (writableCharacteristic == null) {
      throw Exception("Could not find a writable characteristic.");
    }

    List<int> bytes = await _generateBytesFromTemplate();
    // MODIFIED: Use negotiated MTU. Overhead for writeWithoutResponse is 3 bytes.
    final int chunkSize = mtu - 3;

    for (int i = 0; i < bytes.length; i += chunkSize) {
      List<int> chunk = bytes.sublist(
        i,
        i + chunkSize > bytes.length ? bytes.length : i + chunkSize,
      );
      // MODIFIED: Use writeCharacteristicWithoutResponse
      await _ble.writeCharacteristicWithoutResponse(
        writableCharacteristic,
        value: chunk,
      );
      // No delay needed, plugin handles queue
    }
  }

  Future<List<int>> _generateBytesFromTemplate() async {
    // ... existing code ...
    if (_template == null || _template.isEmpty) {
      throw Exception('Printer template is not defined.');
    }
    final templatePrinter = TemplatePrinter(
      template: _template,
      paperSize: _paperSize,
      tables: _tableData,
    );
    return await templatePrinter.getBytes();
  }

  /// Share-PDF action: load doc(s) -> render PDF -> write temp file -> share.
  /// No BLE code touched. Busy flag cleared in finally on every exit.
  /// Branches on _isGridMode: grid loads ALL docs, single loads ONE.
  Future<void> _startSharePdfProcess() async {
    if (_isBusy) return;
    if (mounted) setState(() => _isBusy = true);

    try {
      Uint8List pdfBytes;
      String resolvedName;

      if (_isGridMode) {
        // ── Grid mode: load ALL matching docs ────────────────────────
        if (mounted) setState(() => _isLoadingData = true);
        final List<Map<String, dynamic>> items = await _loadKeyedDataGrid();
        if (mounted) setState(() => _isLoadingData = false);
        if (!mounted) return;

        if (items.isEmpty) {
          final String notFoundLabel = _labels.length > 4
              ? _labels[4]
              : 'Data not found.';
          _showSnackBar(notFoundLabel, Colors.orange);
          return;
        }

        if (_template == null || _template.isEmpty) {
          _showSnackBar('PDF template is not defined.', Colors.red);
          return;
        }

        // QR < 25mm warning (approximate, spec §5 guard).
        // approxQrMm = 0.6 * min(cellW, cellH) / mm. Conservative: assumes
        // QR takes ~60% of the smaller cell dimension after text/padding.
        final double pW = (_pdfPageFormat ?? PdfPageFormat.a4).width;
        final double pH = (_pdfPageFormat ?? PdfPageFormat.a4).height;
        final double cW = (pW - 20) / _gridCols;
        final double cH = (pH - 20) / _gridRows;
        final double minCell = cW < cH ? cW : cH;
        final double approxQrMm = minCell * 0.6 / PdfPageFormat.mm;
        if (approxQrMm < 25.0) {
          devPrint(
            '[PRN share-pdf] WARN: grid ${_gridCols}x$_gridRows on '
            '${(pW / PdfPageFormat.mm).toStringAsFixed(0)}x'
            '${(pH / PdfPageFormat.mm).toStringAsFixed(0)}mm '
            'QR ~${approxQrMm.toStringAsFixed(1)}mm (<25mm minimum)',
          );
        }

        final pdfRenderer = TemplatePdf(
          template: _template,
          pageFormat: _pdfPageFormat ?? PdfPageFormat.a4,
          tables: const {},
          colorResolver: (String name) => _resolvePdfColor(name),
          borderColor: _borderColor,
          assetLoader: _loadAssetBytes,
          borderWidth: _borderWidthPt,
        );
        pdfBytes = await pdfRenderer.generateGridBytes(
          items: items,
          gridCols: _gridCols,
          gridRows: _gridRows,
        );
        // Grid fileName: literal, no per-doc {{field}} resolution.
        resolvedName = resolveAndSanitizeFileName(_fileName, const {});
      } else {
        // ── Single mode: load ONE doc (existing path) ────────────────
        await _loadPrintData();
        if (!mounted) return;

        // Guard: keyed doc didn't load. _loadKeyedData is variant-gated
        // SILENT for share-pdf (W1), so text[4] here is the ONLY
        // user-facing not-found message.
        if (_tableData.isEmpty) {
          final String notFoundLabel = _labels.length > 4
              ? _labels[4]
              : 'Data not found.';
          _showSnackBar(notFoundLabel, Colors.orange);
          return;
        }

        if (_template == null || _template.isEmpty) {
          _showSnackBar('PDF template is not defined.', Colors.red);
          return;
        }

        final pdfRenderer = TemplatePdf(
          template: _template,
          pageFormat: _pdfPageFormat ?? PdfPageFormat.a6,
          tables: _tableData,
          colorResolver: (String name) => _resolvePdfColor(name),
          borderColor: _borderColor,
          assetLoader: _loadAssetBytes,
          borderWidth: _borderWidthPt,
        );
        pdfBytes = await pdfRenderer.generateBytes();
        resolvedName = resolveAndSanitizeFileName(_fileName, _tableData);
      }

      // ── Shared: write temp file + OS share sheet ───────────────────
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$resolvedName');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (!mounted) return;
      // sharePositionOrigin is REQUIRED on iPad: the native plugin
      // otherwise falls back to CGRectZero and anchors the popover at the
      // screen's top-left corner. Harmless/ignored on phones and Android.
      final RenderObject? box = context.findRenderObject();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          fileNameOverrides: [resolvedName],
          sharePositionOrigin: box is RenderBox
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
        ),
      );
    } catch (e) {
      // text[3] = error label ("Gagal membuat PDF. Coba lagi.")
      final String errorLabel = _labels.length > 3
          ? _labels[3]
          : 'Failed to create PDF.';
      _showSnackBar(errorLabel, Colors.red);
      errorReport('[PRN share-pdf] $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... existing code ...
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
    // ── Share-PDF variant: simpler button, no 16-label guard, no BLE ──
    if (_variant == 'share-pdf') {
      return _buildSharePdfContent(context, isEnabled);
    }

    // ... existing code ...
    if (_labels.isEmpty || _labels.length < 16) {
      return Card(
        margin: const EdgeInsets.all(16.0),
        color: Colors.redAccent,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Error: Component text configuration missing or incomplete. Expected at least 16 labels, got ${_labels.length}.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // MODIFIED: Updated state check
    final bool isBusy = _isBusy || _isLoadingData;
    final String buttonLabel = _isLoadingData
        ? 'Loading Data...'
        : (_isBusy ? 'Processing...' : _buttonText);

    // The core button widget is created here
    final Widget printerButton = Card(
      // ... existing code ...
      elevation: 8.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_buttonColor.withValues(alpha: 0.9), _buttonColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ElevatedButton.icon(
          onPressed: isBusy || !isEnabled ? null : _startPrintProcess,
          icon: isBusy
              ? Container(
                  // ... existing code ...
                  width: 24,
                  height: 24,
                  padding: const EdgeInsets.all(2.0),
                  child: CircularProgressIndicator(
                    color: _onButtonColor,
                    strokeWidth: 3,
                  ),
                )
              : Icon(_buttonIcon, color: _onButtonColor),
          label: Text(
            buttonLabel,
            style: TextStyle(
              color: _onButtonColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade500,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ),
      ),
    );

    // MODIFIED: Handle the layout based on the 'width' property
    final dynamic widthValue =
        // ... existing code ...
        widget.component['width'].toString().toLowerCase();

    if (widthValue == 'full') {
      // ... existing code ...
      // If 'full', the button should expand. The Row acts as a container.
      return Row(children: [Expanded(child: printerButton)]);
    }

    final double? specificWidth = double.tryParse(widthValue?.toString() ?? '');

    if (specificWidth != null) {
      // If a specific width is provided, use it.
      return Row(
        mainAxisAlignment: _alignment,
        children: [SizedBox(width: specificWidth, child: printerButton)],
      );
    }

    // Default behavior if 'width' is null or invalid.
    return Row(mainAxisAlignment: _alignment, children: [printerButton]);
  }

  /// Build the share-pdf button UI. No BLE, no 16-label guard.
  /// Button state labels read from _labels with length guards (Conventions Block #3).
  /// Slot 0 = idle label, slot 1 = loading label, slot 2 = sharing label.
  Widget _buildSharePdfContent(BuildContext context, bool isEnabled) {
    final bool isBusy = _isBusy || _isLoadingData;
    final String loadingLabel = _labels.length > 1 ? _labels[1] : 'Loading...';
    final String sharingLabel = _labels.length > 2 ? _labels[2] : 'Sharing...';
    // Slot 0 needs an EMPTY check, not just a length check: diamondTextToList('')
    // returns [''] (not []), so an absent `text` yields _buttonText == '' and the
    // button would render with an icon and no label. Applied here only -- the
    // shared _buttonText assignment in initState is also read by the bluetooth
    // variants, which the <16-label error card already shields.
    final String idleLabel = _buttonText.isNotEmpty ? _buttonText : 'Print';
    final String buttonLabel = _isLoadingData
        ? loadingLabel
        : (_isBusy ? sharingLabel : idleLabel);

    final Widget shareButton = Card(
      elevation: 8.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_buttonColor.withValues(alpha: 0.9), _buttonColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ElevatedButton.icon(
          onPressed: isBusy || !isEnabled ? null : _startSharePdfProcess,
          icon: isBusy
              ? Container(
                  width: 24,
                  height: 24,
                  padding: const EdgeInsets.all(2.0),
                  child: CircularProgressIndicator(
                    color: _onButtonColor,
                    strokeWidth: 3,
                  ),
                )
              : Icon(_buttonIcon, color: _onButtonColor),
          label: Text(
            buttonLabel,
            style: TextStyle(
              color: _onButtonColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade500,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ),
      ),
    );

    // Layout: same pattern as bluetooth variant (width / alignment)
    final dynamic widthValue = widget.component['width']
        .toString()
        .toLowerCase();

    if (widthValue == 'full') {
      return Row(children: [Expanded(child: shareButton)]);
    }

    final double? specificWidth = double.tryParse(widthValue?.toString() ?? '');

    if (specificWidth != null) {
      return Row(
        mainAxisAlignment: _alignment,
        children: [SizedBox(width: specificWidth, child: shareButton)],
      );
    }

    return Row(mainAxisAlignment: _alignment, children: [shareButton]);
  }
}
