import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleDispenserService {
  BleDispenserService._();
  static final BleDispenserService instance = BleDispenserService._();

  static const String serviceUuid = '12345678-1234-1234-1234-123456789000';
  static const String configCharUuid = '12345678-1234-1234-1234-123456789001';
  static const String statusCharUuid = '12345678-1234-1234-1234-123456789002';
  static const String responseCharUuid = '12345678-1234-1234-1234-123456789003';
  static const String expectedDeviceName = 'PillDispenser';

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _configChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _responseChar;

  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  StreamSubscription<List<int>>? _responseNotifySub;

  final _connectionChangeController = StreamController<bool>.broadcast();
  final _responseController = StreamController<String>.broadcast();

  bool _isMockConnected = false;
  String _lastStatusJson = '{"status":"ready"}';

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

  Future<void> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      debugPrint('[BLE] Turn on failed or unsupported: $e');
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
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

  Future<bool> connect(BluetoothDevice device) async {
    await disconnect();

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

      // Subscribe to Response Notifications
      if (_responseChar != null) {
        try {
          await _responseChar!.setNotifyValue(true);
          _responseNotifySub = _responseChar!.onValueReceived.listen((bytes) {
            final payload = utf8.decode(bytes);
            debugPrint('[BLE NOTIFY RECV] $payload');
            _responseController.add(payload);
          });
        } catch (e) {
          debugPrint('[BLE] Failed to subscribe to response notify: $e');
        }
      }

      // Listen to disconnect events
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('[BLE] Device disconnected unexpectedly');
          _cleanup();
          _connectionChangeController.add(false);
        }
      });

      // Read initial status
      await readStatus();

      _isMockConnected = false;
      _connectionChangeController.add(true);
      return true;
    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
      _cleanup();
      try {
        await device.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  void connectMock() {
    _cleanup();
    _isMockConnected = true;
    _lastStatusJson = '{"device":"PD001_MOCK","status":"ready"}';
    _connectionChangeController.add(true);
  }

  Future<void> disconnect() async {
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
  }
}
