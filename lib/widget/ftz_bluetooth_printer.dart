// ftz_bluetooth_printer.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as pos_utils;
// MODIFIED: Replaced flutter_blue_plus with flutter_reactive_ble
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../api.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:get/get.dart'; // MODIFIED: Added GetX for state management
import '../global.dart';
import '../global2.dart';
import '../template_printer.dart';
import '../firestore_repository/table_repository.dart';

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
  final Map<String, List<dynamic>> _tableData = {};

  @override
  void initState() {
    super.initState();

    _labels = diamondTextToList(widget.component['text'] ?? '');
    _buttonText = _labels.isNotEmpty ? _labels[0] : 'Print';
    _buttonIcon =
        stringToIconData(widget.component['buttonIcon'] as String? ?? 'print');
    _buttonColor =
        stringToColor(widget.component['buttonColor'] as String? ?? 'teal');
    _onButtonColor =
        stringToColor(widget.component['onButtonColor'] as String? ?? 'white');
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
    _tableNamesString =
        normalizeTableName(autheniumDecode(widget.component['table']) ?? '');
  }

  // MODIFIED: Added dispose to cancel streams
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<List<List<dynamic>>> readFromTable(
      String scrName, String rawTableName) async {
// ... existing code ...
    dynamic tableArray = rawTableName.split(separator[2]);
    String tableName =
    replacePlaceHoldersFromTxfController(scrName, tableArray[0].trim());
    if (_tableData.containsKey(tableName)) {
      return [_tableData[tableName] ?? []];
    } else {
      late String internalTableCode;
      if (tableArray.length > 1) {
        internalTableCode = tableArray[1]
            .trim();
      } else {
        internalTableCode = tableName
            .substring(tableName.lastIndexOf('/') + 1)
            .replaceAll('.', '_');
      }
      final data = await readFromFirestoreTable(
          currentTableVid, tableName, internalTableCode);
      _tableData[internalTableCode] = data ?? [];
      return [data ?? []];
    }
  }

  Future<void> _loadPrintData() async {
    if (mounted) {
// ... existing code ...
      setState(() => _isLoadingData = true);
    }

    _tableData.clear();

    try {
      if (_tableNamesString == null || _tableNamesString!.isEmpty) {
        return;
      }

      final List<String> tablesToLoad = diamondTextToList(_tableNamesString!);
      if (tablesToLoad.isEmpty) {
        return;
      }

      final List<Future<List<List<dynamic>>>> futures =
      tablesToLoad.map((tableName) {
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
    } catch (e) {
      _showSnackBar('Error loading table data: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
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
      List<DiscoveredDevice> devices) async {
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
                final deviceName =
                device.name.isNotEmpty ? device.name : 'Unknown Device';
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
          _showSnackBar('Bluetooth permissions are required to find printers.',
              Colors.red);
          if (scanStatus.isPermanentlyDenied ||
              connectStatus.isPermanentlyDenied) {
            await openAppSettings();
          }
          return;
        }
      }
      await _loadPrintData();
      if (_isLoadingData || !mounted) return;

      // MODIFIED: Check BLE status with flutter_reactive_ble
      if (_ble.status != BleStatus.ready) {
        _showSnackBar("Bluetooth is OFF. Please turn it ON.", Colors.red);
        return;
      }

      // MODIFIED: Start scanning
      _showSnackBar("Scanning for printers for 4 seconds...", Colors.blue);
      _scanSubscription =
          _ble.scanForDevices(withServices: []).listen((device) {
            // MODIFIED: Corrected 'connectable' check
            if (device.name.isNotEmpty || device.connectable == Connectable.available) {
              _discoveredDevices.putIfAbsent(device.id, () => device);
            }
          }, onError: (e) {
            _showSnackBar("Scan Error: $e", Colors.red);
            if (mounted) setState(() => _isBusy = false);
          });

      // Stop scanning after 4 seconds
      await Future.delayed(const Duration(seconds: 4));
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      if (!mounted) return;
      if (_discoveredDevices.isEmpty) {
        _showSnackBar("No Bluetooth devices found.", Colors.orange);
        return;
      }

      final selectedDevice =
      await _showDeviceSelectionDialog(_discoveredDevices.values.toList());

      if (selectedDevice == null) {
        _showSnackBar("No printer selected.", Colors.grey);
        return;
      }

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

    _connectionSubscription = _ble.connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 15),
    ).listen(
          (connectionState) async {
        if (connectionState.connectionState ==
            DeviceConnectionState.connected) {
          _showSnackBar("Connected. Negotiating MTU...", Colors.blue); // Updated message
          try {
            // MODIFIED: Request MTU after connection. 512 is a common request size.
            final int mtu = await _ble.requestMtu(deviceId: device.id, mtu: 512);
            _showSnackBar("Printing...", Colors.blue);
            await _performPrint(device, mtu);
            _showSnackBar("Print command sent successfully!", Colors.green);
          } catch (e) {
            _showSnackBar("Print Error: $e", Colors.red);
          } finally {
            // Disconnect after printing
            _connectionSubscription?.cancel();
          }
        } else if (connectionState.connectionState ==
            DeviceConnectionState.disconnected) {
          if (mounted) {
            setState(() => _isBusy = false);
          }
          // Only show "Disconnected" if it wasn't an immediate failure
          if (connectionState.failure == null) {
            _showSnackBar("Disconnected.", Colors.grey);
          }
        }
      },
      onError: (e) {
        _showSnackBar("Connection Error: $e", Colors.red);
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
    List<DiscoveredService> services =
    await _ble.discoverServices(connectedDevice.id);

    for (DiscoveredService service in services) {
      for (DiscoveredCharacteristic characteristic
      in service.characteristics) {
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
          i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
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
    if (_template == null || _template!.isEmpty) {
      throw Exception('Printer template is not defined.');
    }
    final templatePrinter = TemplatePrinter(
      template: _template!,
      paperSize: _paperSize,
      tables: _tableData,
    );
    return await templatePrinter.getBytes();
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
        final controller = txfController[widget.scrName]![_position!]!;
        final bool isEnabled = controller.isEnabled;
        return _buildContent(context, isEnabled);
      },
    );
  }

  Widget _buildContent(BuildContext context, bool isEnabled) {
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
                color: Colors.white, fontWeight: FontWeight.bold),
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
            colors: [_buttonColor.withOpacity(0.9), _buttonColor],
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
                fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade500,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0)),
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
      return Row(
        children: [
          Expanded(child: printerButton),
        ],
      );
    }

    final double? specificWidth = double.tryParse(widthValue?.toString() ?? '');

    if (specificWidth != null) {
      // If a specific width is provided, use it.
      return Row(
        mainAxisAlignment: _alignment,
        children: [
          SizedBox(
            width: specificWidth,
            child: printerButton,
          ),
        ],
      );
    }

    // Default behavior if 'width' is null or invalid.
    return Row(
      mainAxisAlignment: _alignment,
      children: [
        printerButton,
      ],
    );
  }
}