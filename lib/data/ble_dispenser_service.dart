import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BleDispenserService {
  BleDispenserService._();
  static final BleDispenserService instance = BleDispenserService._();

  static const String serviceUuid = '12345678-1234-1234-1234-123456789000';
  static const String configCharUuid = '12345678-1234-1234-1234-123456789001';
  static const String statusCharUuid = '12345678-1234-1234-1234-123456789002';
  static const String responseCharUuid = '12345678-1234-1234-1234-123456789003';
  static const String expectedDeviceName = 'PillDispenser';
  static const String _prefLastDeviceIdKey = 'ble_last_connected_device_id';

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _configChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _responseChar;

  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  StreamSubscription<List<int>>? _responseNotifySub;

  final _connectionChangeController = StreamController<bool>.broadcast();
  final _responseController = StreamController<String>.broadcast();

  // Ping-Pong correlation table & sequence counter
  int _reqCounter = 0;
  String _generateReqId() {
    _reqCounter = (_reqCounter + 1) % 100000;
    return 'r$_reqCounter';
  }
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  bool _isMockConnected = false;
  String _lastStatusJson = '{"status":"ready"}';

  // Auto-reconnect state
  bool _manualDisconnect = false;
  bool _isReconnecting = false;
  Timer? _reconnectTimer;

  bool get isConnected =>
      _isMockConnected || (_connectedDevice != null && _statusChar != null);
  bool get isMock => _isMockConnected;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get connectedDeviceName => _isMockConnected
      ? 'MeDisP (Mock ESP32)'
      : (_connectedDevice?.platformName.isNotEmpty == true
          ? _connectedDevice!.platformName
          : _connectedDevice?.remoteId.str);
  String get lastStatusJson => _lastStatusJson;

  Stream<bool> get connectionStateStream => _connectionChangeController.stream;
  Stream<String> get responseStream => _responseController.stream;
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  Future<bool> isBluetoothSupported() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<BluetoothAdapterState> get adapterState async {
    try {
      return await FlutterBluePlus.adapterState.first;
    } catch (_) {
      return BluetoothAdapterState.unavailable;
    }
  }

  Future<List<BluetoothDevice>> getSystemDevices() async {
    try {
      return await FlutterBluePlus.systemDevices([]);
    } catch (e) {
      debugPrint('[BLE] Get system devices error: $e');
      return [];
    }
  }

  Future<void> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      debugPrint('[BLE] Turn on failed or unsupported: $e');
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      // 1. Wait for Bluetooth adapter to settle from 'unknown' or 'turningOn' on app launch
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => FlutterBluePlus.adapterStateNow);

      if (state != BluetoothAdapterState.on) {
        debugPrint('[BLE] Cannot start scan: Bluetooth adapter is $state');
        throw Exception('กรุณาเปิด Bluetooth ก่อนเริ่มค้นหา');
      }

      // 2. Ensure previous scan is safely stopped before initiating a new one
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('[BLE] Start scan error: $e');
      rethrow;
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<bool> connect(BluetoothDevice device, {bool isAutoReconnect = false}) async {
    if (!isAutoReconnect) {
      _stopAutoReconnect();
      _manualDisconnect = false;
      await disconnect(isInternal: true);
    }

    debugPrint('[BLE] Connecting to ${device.platformName} (${device.remoteId})...');
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      // Request larger MTU to match ESP32 (517)
      try {
        await device.requestMtu(517);
      } catch (_) {}

      // Discover Services
      final services = await device.discoverServices();
      debugPrint('[BLE] Discovered ${services.length} services');

      BluetoothService? targetService;
      final targetUuidLower = serviceUuid.toLowerCase();

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() == targetUuidLower) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        // Fallback: check if any service contains the characteristics
        for (final service in services) {
          for (final char in service.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            if (uuid == configCharUuid.toLowerCase() ||
                uuid == statusCharUuid.toLowerCase()) {
              targetService = service;
              break;
            }
          }
          if (targetService != null) break;
        }
      }

      if (targetService == null) {
        await device.disconnect();
        throw StateError('ไม่พบ MeDisP Service ($serviceUuid) บนอุปกรณ์นี้');
      }

      for (final char in targetService.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        if (uuid == configCharUuid.toLowerCase()) {
          _configChar = char;
        } else if (uuid == statusCharUuid.toLowerCase()) {
          _statusChar = char;
        } else if (uuid == responseCharUuid.toLowerCase()) {
          _responseChar = char;
        }
      }

      if (_statusChar == null && _configChar == null) {
        await device.disconnect();
        throw StateError('ไม่พบ Characteristic สำหรับควบคุมเครื่องจ่ายยา');
      }

      _connectedDevice = device;

      // Persist connected device ID for auto-reconnect
      _saveLastDeviceId(device.remoteId.str);

      // Subscribe to Response Notifications
      if (_responseChar != null) {
        try {
          await _responseChar!.setNotifyValue(true);
          _responseNotifySub = _responseChar!.onValueReceived.listen((bytes) {
            final payload = utf8.decode(bytes);
            debugPrint('[BLE NOTIFY RECV] $payload');
            _responseController.add(payload);
            _resolvePendingAck(payload);
          });
        } catch (e) {
          debugPrint('[BLE] Failed to subscribe to response notify: $e');
        }
      }

      // Listen to disconnect events and trigger auto-reconnect if unexpected
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('[BLE] Device disconnected (${device.remoteId.str})');
          _cleanup();
          _connectionChangeController.add(false);

          if (!_manualDisconnect) {
            _triggerAutoReconnect(device.remoteId.str);
          }
        }
      });

      // Read initial status
      await readStatus();

      _isMockConnected = false;
      _stopAutoReconnect();
      _connectionChangeController.add(true);
      return true;
    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
      _cleanup();
      try {
        await device.disconnect();
      } catch (_) {}
      if (isAutoReconnect) {
        return false;
      }
      rethrow;
    }
  }

  void _saveLastDeviceId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastDeviceIdKey, id);
    } catch (_) {}
  }

  Future<String?> getLastDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefLastDeviceIdKey);
    } catch (_) {
      return null;
    }
  }

  void _stopAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
  }

  bool _isScanOperationActive = false;

  /// Discovers target device via targeted scan to ensure Linux BlueZ / Android Bluetooth
  /// cache resolves the peripheral before initiating connection.
  Future<BluetoothDevice?> _scanForDevice(String targetId, {Duration timeout = const Duration(seconds: 4)}) async {
    if (_isScanOperationActive) return null;
    _isScanOperationActive = true;

    try {
      // 0. Wait for Bluetooth adapter to be ready (settle from 'unknown' at app startup)
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => FlutterBluePlus.adapterStateNow);
      if (state != BluetoothAdapterState.on) {
        debugPrint('[BLE AUTO-RECONNECT] Adapter is $state, skipping background scan');
        return null;
      }

      // 1. Check system devices first (already bonded/cached by BlueZ)
      try {
        final sysDevices = await getSystemDevices();
        for (final d in sysDevices) {
          if (d.remoteId.str.toUpperCase() == targetId.toUpperCase()) {
            debugPrint('[BLE AUTO-RECONNECT] Found in system devices: $targetId');
            return d;
          }
        }
      } catch (_) {}

      // 2. Ensure previous scan is safely stopped
      try {
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } catch (_) {}

      BluetoothDevice? matchedDevice;
      StreamSubscription? sub;

      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (r.device.remoteId.str.toUpperCase() == targetId.toUpperCase()) {
            matchedDevice = r.device;
            FlutterBluePlus.stopScan().catchError((_) {});
            break;
          }
        }
      });

      // Avoid withServices on Linux BlueZ as it causes NoDiscoveryStarted on some BlueZ versions
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      // Wait until scan finishes or device is found
      final start = DateTime.now();
      while (matchedDevice == null &&
             FlutterBluePlus.isScanningNow &&
             DateTime.now().difference(start) < timeout) {
        await Future.delayed(const Duration(milliseconds: 150));
      }

      await sub.cancel();
      try {
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
        }
      } catch (_) {}

      return matchedDevice;
    } catch (e) {
      debugPrint('[BLE AUTO-RECONNECT] Scan error: $e');
      return null;
    } finally {
      _isScanOperationActive = false;
    }
  }

  void _triggerAutoReconnect(String deviceId) {
    if (_manualDisconnect || _isReconnecting) return;
    _isReconnecting = true;
    debugPrint('[BLE AUTO-RECONNECT] Starting retry loop for device: $deviceId');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 6), (timer) async {
      if (_manualDisconnect || isConnected) {
        _stopAutoReconnect();
        return;
      }

      try {
        debugPrint('[BLE AUTO-RECONNECT] Scanning and attempting reconnect to $deviceId...');
        final foundDevice = await _scanForDevice(deviceId, timeout: const Duration(seconds: 3));
        if (foundDevice != null) {
          debugPrint('[BLE AUTO-RECONNECT] Device found via scan! Connecting to ${foundDevice.remoteId.str}...');
          final ok = await connect(foundDevice, isAutoReconnect: true);
          if (ok) {
            debugPrint('[BLE AUTO-RECONNECT] Reconnected successfully to $deviceId!');
            _stopAutoReconnect();
          }
        } else {
          debugPrint('[BLE AUTO-RECONNECT] Device not in range yet, will retry next cycle...');
        }
      } catch (e) {
        debugPrint('[BLE AUTO-RECONNECT] Reconnect retry error: $e');
      }
    });
  }

  /// Automatically attempt reconnecting to the last paired device on app startup
  Future<bool> tryAutoConnectLastDevice() async {
    if (isConnected) return true;
    final lastId = await getLastDeviceId();
    if (lastId == null || lastId.isEmpty) {
      debugPrint('[BLE AUTO-RECONNECT] No previous device found in storage');
      return false;
    }

    debugPrint('[BLE AUTO-RECONNECT] Found saved device ID: $lastId. Scanning to resolve peripheral...');
    try {
      final foundDevice = await _scanForDevice(lastId, timeout: const Duration(seconds: 4));
      if (foundDevice != null) {
        debugPrint('[BLE AUTO-RECONNECT] Peripheral detected in advertising range. Connecting now...');
        return await connect(foundDevice, isAutoReconnect: true);
      } else {
        debugPrint('[BLE AUTO-RECONNECT] Device not immediately detected in initial scan, starting background retry...');
        _triggerAutoReconnect(lastId);
        return false;
      }
    } catch (e) {
      debugPrint('[BLE AUTO-RECONNECT] Initial connect to $lastId failed, background loop will continue: $e');
      _triggerAutoReconnect(lastId);
      return false;
    }
  }

  void connectMock() {
    _stopAutoReconnect();
    _manualDisconnect = false;
    _cleanup();
    _isMockConnected = true;
    _lastStatusJson = '{"device":"PD001_MOCK","status":"ready"}';
    _connectionChangeController.add(true);
  }

  Future<void> disconnect({bool isInternal = false}) async {
    if (!isInternal) {
      _manualDisconnect = true;
      _stopAutoReconnect();
    }

    if (_isMockConnected) {
      _isMockConnected = false;
      _connectionChangeController.add(false);
      return;
    }

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
    }
    _cleanup();
    _connectionChangeController.add(false);
  }

  Future<String?> readStatus() async {
    if (_isMockConnected) return _lastStatusJson;
    if (_statusChar == null) return null;
    try {
      final bytes = await _statusChar!.read();
      final str = utf8.decode(bytes);
      _lastStatusJson = str;
      return str;
    } catch (e) {
      debugPrint('[BLE] Read status failed: $e');
      return null;
    }
  }

  Future<String?> readSchedule() async {
    if (_isMockConnected) return null;
    if (_configChar == null) return null;
    try {
      final bytes = await _configChar!.read();
      return utf8.decode(bytes);
    } catch (e) {
      debugPrint('[BLE] Read schedule failed: $e');
      return null;
    }
  }

  Future<bool> sendSchedule(String jsonPayload) async {
    if (_isMockConnected) {
      debugPrint('[BLE MOCK] Sent schedule payload: $jsonPayload');
      return true;
    }
    if (_configChar == null) {
      throw StateError('ยังไม่ได้เชื่อมต่อเครื่องจ่ายยา');
    }
    try {
      final bytes = utf8.encode(jsonPayload);
      await _configChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Successfully wrote schedule payload (${bytes.length} bytes)');
      return true;
    } catch (e) {
      debugPrint('[BLE] Write schedule error: $e');
      rethrow;
    }
  }

  /// Match incoming response with pending Ping-Pong request completer
  void _resolvePendingAck(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final reqId = decoded['req_id'] as String?;
        if (reqId != null && _pendingRequests.containsKey(reqId)) {
          final completer = _pendingRequests.remove(reqId);
          if (completer != null && !completer.isCompleted) {
            completer.complete(decoded);
          }
        }
      }
    } catch (_) {
      // Non-JSON or malformed payload, ignore
    }
  }

  /// Send a generic JSON command to ESP32 via Config characteristic
  Future<bool> sendCommand(Map<String, dynamic> command) async {
    final cmdMap = Map<String, dynamic>.from(command);
    cmdMap['req_id'] ??= _generateReqId();

    if (_isMockConnected) {
      debugPrint('[BLE MOCK] Sent command: ${cmdMap['cmd']} (${cmdMap['req_id']})');
      return true;
    }
    if (_configChar == null) {
      throw StateError('ยังไม่ได้เชื่อมต่อเครื่องจ่ายยา');
    }
    try {
      final payload = jsonEncode(cmdMap);
      final bytes = utf8.encode(payload);
      await _configChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Sent command: ${cmdMap['cmd']} (${bytes.length} bytes, req_id: ${cmdMap['req_id']})');
      return true;
    } catch (e) {
      debugPrint('[BLE] Send command error: $e');
      rethrow;
    }
  }

  /// Send command with explicit Ping-Pong Acknowledgment (waiting for matching req_id)
  Future<Map<String, dynamic>> sendCommandWithAck(
    Map<String, dynamic> command, {
    Duration timeout = const Duration(seconds: 5),
    String? expectedEvent,
  }) async {
    final cmdMap = Map<String, dynamic>.from(command);
    final reqId = (cmdMap['req_id'] as String?) ?? _generateReqId();
    cmdMap['req_id'] = reqId;

    if (_isMockConnected) {
      debugPrint('[BLE MOCK] Sent command with ACK: ${cmdMap['cmd']} ($reqId)');
      return {
        'event': expectedEvent ?? 'pong',
        'req_id': reqId,
        'status': 'success',
        'result': 'success',
      };
    }

    if (_configChar == null) {
      throw StateError('ยังไม่ได้เชื่อมต่อเครื่องจ่ายยา');
    }

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[reqId] = completer;

    try {
      final payload = jsonEncode(cmdMap);
      final bytes = utf8.encode(payload);
      await _configChar!.write(bytes, withoutResponse: false);
      debugPrint('[BLE] Sent command with ACK: ${cmdMap['cmd']} ($reqId, ${bytes.length} bytes)');

      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingRequests.remove(reqId);
          throw TimeoutException(
            'ตู้ยาไม่ตอบสนองตามเวลาที่กำหนด (${cmdMap['cmd']})',
            timeout,
          );
        },
      );
    } catch (e) {
      _pendingRequests.remove(reqId);
      debugPrint('[BLE] sendCommandWithAck error ($reqId): $e');
      rethrow;
    }
  }

  /// Heartbeat ping to verify ESP32 is alive and ready
  Future<bool> ping({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final res = await sendCommandWithAck({'cmd': 'ping'},
          timeout: timeout, expectedEvent: 'pong');
      return res['status'] == 'ready' ||
          res['status'] == 'success' ||
          res['event'] == 'pong';
    } catch (_) {
      return false;
    }
  }

  /// Sync current phone local time to ESP32
  Future<bool> syncTime() async {
    final now = DateTime.now();
    // Use local epoch so ESP32 internal clock matches the phone's actual display time
    final localEpoch = (now.millisecondsSinceEpoch ~/ 1000) + now.timeZoneOffset.inSeconds;
    debugPrint('[BLE SYNC] Sending local time sync: epoch=$localEpoch (Local: $now, offset=${now.timeZoneOffset.inHours}h)');
    return sendCommand({
      'cmd': 'sync_time',
      'epoch': localEpoch,
      'tz_offset': now.timeZoneOffset.inSeconds,
    });
  }

  /// Push full slots data to ESP32
  Future<bool> sendSlots(List<Map<String, dynamic>> slotsData) async {
    debugPrint('[BLE SYNC] Sending ${slotsData.length} slots to device');
    return sendCommand({'cmd': 'sync_slots', 'slots': slotsData});
  }

  /// Request full sync data from ESP32 (triggers SYNC_DATA_READY event)
  Future<bool> requestSyncData() async {
    debugPrint('[BLE SYNC] Requesting full sync data from device');
    return sendCommand({'cmd': 'get_sync_data'});
  }

  /// Request schedule sync from ESP32 (streams SLOT_SCHEDULE per slot)
  Future<bool> requestScheduleSync() async {
    debugPrint('[BLE SYNC] Requesting schedule sync from device');
    return sendCommand({'cmd': 'get_schedule'});
  }

  /// Request intake history sync from ESP32 (all un-cleared days)
  Future<bool> requestHistorySync({int? dayOffset}) async {
    debugPrint(
        '[BLE SYNC] Requesting intake history from device (dayOffset: $dayOffset)');
    return sendCommand({
      'cmd': 'sync_history',
      if (dayOffset != null) 'day_offset': dayOffset,
    });
  }

  /// Clear synced history from ESP32 Flash, selectively keeping today's active records
  Future<bool> clearHistory({String? beforeDate}) async {
    debugPrint('[BLE SYNC] Requesting clear_history (beforeDate: $beforeDate)');
    return sendCommand({
      'cmd': 'clear_history',
      if (beforeDate != null && beforeDate.isNotEmpty) 'before_date': beforeDate,
    });
  }

  /// Record medication intake on ESP32 history & trigger dispenser
  Future<bool> recordIntake({
    required int slot,
    int qty = 1,
    String? medicine,
    String type = 'meal',
    String? schedTime,
    String status = 'taken',
  }) async {
    debugPrint(
        '[BLE SYNC] Recording intake: Slot $slot, Qty $qty, $type, schedTime: $schedTime');
    return sendCommand({
      'cmd': 'record_intake',
      'slot': slot,
      'qty': qty,
      'medicine': medicine ?? '',
      'type': type,
      if (schedTime != null && schedTime.isNotEmpty) 'sched_time': schedTime,
      'status': status,
    });
  }

  /// Request dispense directly from ESP32
  Future<bool> dispense({
    required int slot,
    int qty = 1,
    String? medicine,
    String type = 'meal',
    String? schedTime,
  }) async {
    debugPrint('[BLE SYNC] Requesting dispense: Slot $slot, Qty $qty');
    return sendCommand({
      'cmd': 'dispense',
      'slot': slot,
      'qty': qty,
      'medicine': medicine ?? '',
      'type': type,
      if (schedTime != null && schedTime.isNotEmpty) 'sched_time': schedTime,
    });
  }

  void _cleanup() {
    _connectionStateSub?.cancel();
    _connectionStateSub = null;
    _responseNotifySub?.cancel();
    _responseNotifySub = null;
    _connectedDevice = null;
    _configChar = null;
    _statusChar = null;
    _responseChar = null;
    _isMockConnected = false;

    // Reject any pending Ping-Pong requests immediately on disconnect
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('การเชื่อมต่อกับเครื่องจ่ายยาขาดหาย'),
        );
      }
    }
    _pendingRequests.clear();
  }
}
