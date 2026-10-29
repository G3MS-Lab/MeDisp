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

  const DiscoveredBleEntry({
    required this.device,
    this.rssi,
    this.isSystemDevice = false,
  });
}

class _BleDevicePickerSheetState extends State<BleDevicePickerSheet> {
  final BleDispenserService _ble = BleDispenserService.instance;
  BluetoothDevice? _connectingDevice;
  String? _errorMessage;
  StreamSubscription<List<ScanResult>>? _scanSub;
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

    final state = await _ble.adapterState;
    if (state != BluetoothAdapterState.on && mounted) {
      setState(() {
        _errorMessage = 'กรุณาเปิด Bluetooth ก่อนเริ่มค้นหา';
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

    _startScan();
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
    _scanSub?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sort devices: PillDispenser / MeDis first, then named devices, then MAC
    final sortedList = _devices.values.toList();
    sortedList.sort((a, b) {
      final aName = a.device.platformName.toLowerCase();
      final bName = b.device.platformName.toLowerCase();
      final aIsPill = aName.contains('pill') || aName.contains('medis');
      final bIsPill = bName.contains('pill') || bName.contains('medis');
      if (aIsPill && !bIsPill) return -1;
      if (!aIsPill && bIsPill) return 1;
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
                      final name = item.device.platformName;
                      final isPillDispenser = name.toLowerCase().contains('pill') ||
                          name.toLowerCase().contains('medis');
                      final isConnectingThis =
                          _connectingDevice?.remoteId == item.device.remoteId;

                      return Container(
                        decoration: BoxDecoration(
                          color: isPillDispenser
                              ? MeDisColors.primarySoft.withValues(alpha: 0.5)
                              : MeDisColors.background,
                          borderRadius:
                              BorderRadius.circular(MeDisRadius.card),
                          border: Border.all(
                            color: isPillDispenser
                                ? MeDisColors.primary.withValues(alpha: 0.4)
                                : MeDisColors.border,
                            width: isPillDispenser ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isPillDispenser
                                ? MeDisColors.primary
                                : MeDisColors.surface,
                            child: Icon(
                              isPillDispenser
                                  ? Icons.medication
                                  : Icons.bluetooth,
                              color: isPillDispenser
                                  ? Colors.white
                                  : MeDisColors.muted,
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name.isNotEmpty
                                      ? name
                                      : 'อุปกรณ์ที่ไม่ระบุชื่อ',
                                  style: TextStyle(
                                    fontWeight: isPillDispenser
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: MeDisColors.text,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isPillDispenser) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: MeDisColors.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'MeDisP',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            item.rssi != null
                                ? '${item.device.remoteId.str} • ${item.rssi} dBm'
                                : '${item.device.remoteId.str} • อุปกรณ์ในระบบ',
                            style: const TextStyle(
                              color: MeDisColors.muted,
                              fontSize: 12,
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
                                    backgroundColor: isPillDispenser
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
