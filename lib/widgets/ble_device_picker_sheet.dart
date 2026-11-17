import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../application/app_controller.dart';
import '../data/ble_dispenser_service.dart';
import '../theme/medis_theme.dart';

Future<void> showBleDevicePickerSheet({
  required BuildContext context,
  required AppController controller,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => BleDevicePickerSheet(controller: controller),
  );
}

class BleDevicePickerSheet extends StatefulWidget {
  const BleDevicePickerSheet({required this.controller, super.key});
  final AppController controller;

  @override
  State<BleDevicePickerSheet> createState() => _BleDevicePickerSheetState();
}

class DiscoveredBleEntry {
  final BluetoothDevice device;
  final int? rssi;
  final bool isSystemDevice;
  final AdvertisementData? advertisementData;

  const DiscoveredBleEntry({
    required this.device,
    this.rssi,
    this.isSystemDevice = false,
    this.advertisementData,
  });
}

class _BleDevicePickerSheetState extends State<BleDevicePickerSheet> {
  final BleDispenserService _ble = BleDispenserService.instance;
  BluetoothDevice? _connectingDevice;
  String? _errorMessage;
  String? _lastRememberedDeviceId;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  final Map<String, DiscoveredBleEntry> _devices = {};
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initScan();
  }

  Future<void> _loadSystemDevices() async {
    final sysDevices = await _ble.getSystemDevices();
    if (!mounted) return;
    setState(() {
      for (final device in sysDevices) {
        final id = device.remoteId.str;
        if (!_devices.containsKey(id)) {
          _devices[id] = DiscoveredBleEntry(
            device: device,
            isSystemDevice: true,
          );
        }
      }
    });
  }

  Future<void> _initScan() async {
    setState(() {
      _errorMessage = null;
    });

    final supported = await _ble.isBluetoothSupported();
    if (!supported && mounted) {
      setState(() {
        _errorMessage = 'อุปกรณ์นี้ไม่รองรับ Bluetooth หรือไม่ได้เปิดใช้งาน';
      });
      return;
    }

    // Load remembered/paired device from persistent storage
    final savedId = await _ble.getLastDeviceId();
    if (mounted) {
      setState(() {
        _lastRememberedDeviceId = savedId;
      });
    }

    // Load devices already known to the OS Bluetooth stack (crucial for Linux)
    await _loadSystemDevices();

    _scanSub = _ble.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          for (final r in results) {
            _devices[r.device.remoteId.str] = DiscoveredBleEntry(
              device: r.device,
              rssi: r.rssi,
              isSystemDevice: false,
              advertisementData: r.advertisementData,
            );
          }
        });
      }
    });

    _ble.isScanning.listen((scanning) {
      if (mounted) {
        setState(() {
          _isScanning = scanning;
        });
      }
    });

    // Reactive adapter listener: automatically starts scan when adapter turns ON
    // (Resolves initial launch race condition when adapter starts as 'unknown')
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      if (state == BluetoothAdapterState.on) {
        setState(() {
          _errorMessage = null;
        });
        if (!_isScanning && _devices.isEmpty) {
          _startScan();
        }
      } else if (state == BluetoothAdapterState.off) {
        setState(() {
          _errorMessage = 'กรุณาเปิด Bluetooth ก่อนเริ่มค้นหา';
        });
      }
    });

    // Wait for initial adapter state to settle from 'unknown' or 'turningOn'
    try {
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => FlutterBluePlus.adapterStateNow);

      if (state == BluetoothAdapterState.on) {
        if (mounted) {
          _startScan();
        }
      } else if (mounted) {
        setState(() {
          _errorMessage = 'กรุณาเปิด Bluetooth ก่อนเริ่มค้นหา';
        });
      }
    } catch (_) {
      if (mounted) {
        _startScan();
      }
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _errorMessage = null;
    });
    try {
      await _loadSystemDevices();
      await _ble.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'ไม่สามารถเริ่มสแกนได้: $e';
        });
      }
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _connectingDevice = device;
      _errorMessage = null;
    });

    try {
      final success = await widget.controller.connectBleDevice(device);
      if (success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: MeDisColors.success,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'เชื่อมต่อกับ ${device.platformName.isEmpty ? "MeDisP" : device.platformName} สำเร็จแล้ว',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      } else if (mounted) {
        setState(() {
          _errorMessage =
              widget.controller.errorMessage ?? 'การเชื่อมต่อล้มเหลว กรุณาลองใหม่';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'เกิดข้อผิดพลาดในการเชื่อมต่อ: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _connectingDevice = null;
        });
      }
    }
  }

  void _connectMock() {
    widget.controller.connectMockDevice();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: MeDisColors.primary,
        content: Row(
          children: [
            Icon(Icons.developer_mode, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'เปิดใช้งานโหมดจำลอง (Mock Dispenser) เรียบร้อยแล้ว',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _scanSub?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  String _getDeviceDisplayName(DiscoveredBleEntry entry) {
    if (entry.device.platformName.isNotEmpty) {
      return entry.device.platformName;
    }
    if (entry.advertisementData != null && entry.advertisementData!.advName.isNotEmpty) {
      return entry.advertisementData!.advName;
    }
    if (entry.device.advName.isNotEmpty) {
      return entry.device.advName;
    }
    final hasPillService = entry.advertisementData?.serviceUuids.any(
      (u) => u.toString().toLowerCase().contains('12345678-1234-1234-1234-123456789000'),
    ) ?? false;
    if (hasPillService) {
      return 'PillDispenser';
    }
    final mac = entry.device.remoteId.str.toUpperCase();
    if (mac.startsWith('CC:68:C7') || mac.startsWith('30:30:F9') || mac.startsWith('40:22:D8') || mac.startsWith('48:27:E2')) {
      return 'PillDispenser (MeDisP)';
    }
    return '';
  }

  // ==========================================================================
  // [CUSTOMIZE HERE / เปลี่ยนตรงนี้ให้เครื่องรู้เป็นเครื่องจ่ายยา]:
  // Recognition criteria for MeDisP Pill Dispenser hardware.
  // Modify or extend any of the 3 checks below to match your hardware:
  //
  // 1. BLE Broadcast Device Name (case-insensitive):
  //    Default checks for 'pill' or 'medis' (e.g. 'PillDispenser', 'MeDisP_S3').
  //
  // 2. Custom BLE Service UUID (from MeDisP_Config.h):
  //    Default: '12345678-1234-1234-1234-123456789000'.
  //
  // 3. Hardware MAC Address Prefix / OUI:
  //    Espressif ESP32-S3 factory OUI prefixes (e.g. 'CC:68:C7', '30:30:F9').
  //    You can add your specific board's MAC prefix here if needed!
  // ==========================================================================
  bool _isMeDisPDevice(DiscoveredBleEntry entry) {
    // Check 1: Match by advertised device name
    final name = _getDeviceDisplayName(entry).toLowerCase();
    if (name.contains('pill') || name.contains('medis')) return true;

    // Check 2: Match by Custom Pill Dispenser Service UUID
    final hasPillService = entry.advertisementData?.serviceUuids.any(
      (u) => u.toString().toLowerCase().contains('12345678-1234-1234-1234-123456789000'),
    ) ?? false;
    if (hasPillService) return true;

    // Check 3: Match by ESP32-S3 MAC Vendor Prefix (OUI)
    final mac = entry.device.remoteId.str.toUpperCase();
    if (mac.startsWith('CC:68:C7') ||
        mac.startsWith('30:30:F9') ||
        mac.startsWith('40:22:D8') ||
        mac.startsWith('48:27:E2')) {
      return true;
    }

    return false;
  }

  // ==========================================================================
  // [HIGHLIGHT 1]: Check if this device was previously connected / remembered
  // ==========================================================================
  bool _isRemembered(DiscoveredBleEntry entry) {
    if (_lastRememberedDeviceId == null || _lastRememberedDeviceId!.isEmpty) return false;
    return _lastRememberedDeviceId!.toLowerCase() == entry.device.remoteId.str.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    // Sort devices: 1) Remembered & Dispenser, 2) Dispenser, 3) Remembered, 4) Named, 5) RSSI
    final sortedList = _devices.values.toList();
    sortedList.sort((a, b) {
      final aIsRemembered = _isRemembered(a);
      final bIsRemembered = _isRemembered(b);
      final aIsPill = _isMeDisPDevice(a);
      final bIsPill = _isMeDisPDevice(b);

      final aScore = (aIsRemembered ? 2 : 0) + (aIsPill ? 1 : 0);
      final bScore = (bIsRemembered ? 2 : 0) + (bIsPill ? 1 : 0);
      if (aScore != bScore) return bScore.compareTo(aScore);

      final aName = _getDeviceDisplayName(a).toLowerCase();
      final bName = _getDeviceDisplayName(b).toLowerCase();
      if (aName.isNotEmpty && bName.isEmpty) return -1;
      if (aName.isEmpty && bName.isNotEmpty) return 1;
      final aRssi = a.rssi ?? -100;
      final bRssi = b.rssi ?? -100;
      return bRssi.compareTo(aRssi);
    });

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: MeDisColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MeDisRadius.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: MeDisColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MeDisSpace.page),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MeDisColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bluetooth_searching,
                    color: MeDisColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ค้นหาเครื่องจ่ายยา',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'เลือกเครื่องจ่ายยา MeDisP เพื่อเชื่อมต่อ',
                        style: TextStyle(
                          color: MeDisColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'ปิด',
                ),
              ],
            ),
          ),

          if (_isScanning) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: MeDisColors.primarySoft,
              valueColor: AlwaysStoppedAnimation(MeDisColors.primary),
            ),
          ] else ...[
            const SizedBox(height: 14),
          ],

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MeDisSpace.page,
                0,
                MeDisSpace.page,
                8,
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MeDisColors.errorSoft,
                  borderRadius: BorderRadius.circular(MeDisRadius.input),
                  border: Border.all(color: MeDisColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: MeDisColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: MeDisColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Device List
          Expanded(
            child: sortedList.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(MeDisSpace.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isScanning
                                ? Icons.bluetooth_searching
                                : Icons.bluetooth_disabled,
                            size: 48,
                            color: MeDisColors.muted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isScanning
                                ? 'กำลังค้นหาอุปกรณ์ MeDisP ใกล้เคียง...'
                                : 'ยังไม่พบอุปกรณ์บลูทูธ',
                            style: const TextStyle(
                              color: MeDisColors.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'กรุณาตรวจสอบว่าบอร์ด ESP32 เปิดอยู่และวางอยู่ใกล้ๆ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: MeDisColors.subtle,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MeDisSpace.page,
                      vertical: 8,
                    ),
                    itemCount: sortedList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = sortedList[index];
                      final name = _getDeviceDisplayName(item);
                      final isPillDispenser = _isMeDisPDevice(item);
                      final isRemembered = _isRemembered(item);
                      final isConnectingThis =
                          _connectingDevice?.remoteId == item.device.remoteId;

                      // Highlight styling: Pill Dispenser (Teal) vs Remembered (Amber/Gold)
                      final Color cardBg;
                      final Border cardBorder;
                      if (isPillDispenser && isRemembered) {
                        cardBg = MeDisColors.primarySoft.withValues(alpha: 0.7);
                        cardBorder = Border.all(color: MeDisColors.primary, width: 2.0);
                      } else if (isPillDispenser) {
                        cardBg = MeDisColors.primarySoft.withValues(alpha: 0.45);
                        cardBorder = Border.all(color: MeDisColors.primary.withValues(alpha: 0.6), width: 1.5);
                      } else if (isRemembered) {
                        cardBg = MeDisColors.warningSoft.withValues(alpha: 0.5);
                        cardBorder = Border.all(color: MeDisColors.warning.withValues(alpha: 0.6), width: 1.5);
                      } else {
                        cardBg = MeDisColors.background;
                        cardBorder = Border.all(color: MeDisColors.border, width: 1.0);
                      }

                      // Leading icon based on highlight state
                      final Color avatarBg;
                      final IconData avatarIcon;
                      final Color iconColor;
                      if (isPillDispenser) {
                        avatarBg = MeDisColors.primary;
                        avatarIcon = Icons.medication_rounded;
                        iconColor = Colors.white;
                      } else if (isRemembered) {
                        avatarBg = MeDisColors.warning;
                        avatarIcon = Icons.history_rounded;
                        iconColor = Colors.white;
                      } else {
                        avatarBg = MeDisColors.surface;
                        avatarIcon = Icons.bluetooth;
                        iconColor = MeDisColors.muted;
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(MeDisRadius.card),
                          border: cardBorder,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: avatarBg,
                            child: Icon(avatarIcon, color: iconColor),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isNotEmpty
                                    ? name
                                    : 'อุปกรณ์ที่ไม่ระบุชื่อ',
                                style: TextStyle(
                                  fontWeight: (isPillDispenser || isRemembered)
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: MeDisColors.text,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isPillDispenser || isRemembered) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    // Highlight 2: Pill Dispenser Hardware Badge
                                    if (isPillDispenser)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: MeDisColors.primary,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.medication_rounded, size: 12, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text(
                                              'เครื่องจ่ายยา MeDisP',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Highlight 1: Previously Connected / Remembered Badge
                                    if (isRemembered)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: MeDisColors.warningSoft,
                                          border: Border.all(
                                            color: MeDisColors.warning.withValues(alpha: 0.6),
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.history_rounded, size: 12, color: MeDisColors.warning),
                                            SizedBox(width: 4),
                                            Text(
                                              'เคยเชื่อมต่อแล้ว',
                                              style: TextStyle(
                                                color: MeDisColors.warning,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              item.rssi != null
                                  ? '${item.device.remoteId.str} • ${item.rssi} dBm'
                                  : '${item.device.remoteId.str} • อุปกรณ์ในระบบ',
                              style: const TextStyle(
                                color: MeDisColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          trailing: isConnectingThis
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: (isPillDispenser || isRemembered)
                                        ? MeDisColors.primary
                                        : MeDisColors.muted,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: _connectingDevice != null
                                      ? null
                                      : () => _connect(item.device),
                                  child: const Text('เชื่อมต่อ'),
                                ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Bar Actions
          Container(
            padding: const EdgeInsets.fromLTRB(
              MeDisSpace.page,
              12,
              MeDisSpace.page,
              24,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: MeDisColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: Icon(
                      _isScanning
                          ? Icons.hourglass_top
                          : Icons.refresh,
                      size: 18,
                    ),
                    label: Text(
                      _isScanning ? 'กำลังสแกน...' : 'สแกนอีกครั้ง',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _connectMock,
                  icon: const Icon(Icons.developer_mode, size: 18),
                  label: const Text('โหมดจำลอง (Mock)'),
                  style: TextButton.styleFrom(
                    foregroundColor: MeDisColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
